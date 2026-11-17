import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func reloadPlugins() {
        let loaded = PluginSystem.listPlugins(includeBuiltin: true, includeSecrets: false)
        plugins = loaded
        pluginCommands = PluginCommandRegistry.registeredCommands(for: loaded)
        enabledQuickButtons = PluginCommandRegistry.enabledQuickButtons(for: loaded)
        pluginSearchEntries = PluginSearchIndex.loadEntries(for: loaded)
        SelectionQuickBarController.shared.syncMonitoring(
            enabled: generalPreferences.enableSelectionQuickBar,
            plugins: loaded,
            viewModel: self
        )
    }

    func reloadPluginSearchIndex() {
        pluginSearchEntries = PluginSearchIndex.loadEntries(for: plugins)
    }

    func reloadPluginsAndHotKeys() {
        reloadPlugins()
        (hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.updateExternalPluginHotKeys(externalPluginHotKeyBindings())
    }

    func reloadAppsAndPlugins() {
        reloadPluginsAndHotKeys()
        Task {
            let apps = await Task.detached(priority: .userInitiated) { LauncherEngine.discoverInstalledApps() }.value
            self.installedApps = apps
            AppUsageTrackerController.shared.ensureSystemProbe(for: apps)
            if self.isOverlayVisible {
                IconCache.shared.prewarmDockIcons(self.cachedDockApps)
            }
        }
    }

    func makePluginBridgeContext() -> PluginBridgeHostContext {
        buildRichPluginBridgeContext()
    }

    func setPluginEnabled(_ plugin: PluginDescriptor, isEnabled: Bool) throws {
        if let builtin = BuiltinPluginID(rawValue: plugin.id) {
            switch builtin {
            case .mos:
                var next = mosConfig; next.enabled = isEnabled; applyMosConfig(next)
            case .systemPulse:
                SystemPulseWindowController.shared.setFloatingEnabled(isEnabled)
                if !isEnabled { SystemPulseWindowController.shared.setMenuBarEnabled(false) }
                reloadPlugins()
            }
            return
        }
        try PluginSystem.setPluginEnabled(id: plugin.id, isEnabled: isEnabled)
        if plugin.id == LumaLinkServer.companionPluginID {
            refreshLumaLinkStatus(refreshPermissions: false)
        }
        if !isEnabled && scopedPluginID == plugin.id { scopedPluginID = nil }
        reloadPluginsAndHotKeys()
    }

    func togglePluginOverlayPin(_ plugin: PluginDescriptor) {
        let next = !plugin.pinnedInOverlay
        try? PluginSystem.updatePluginOverrides(id: plugin.id) { $0.pinnedInOverlay = next }
        reloadPlugins()
        serviceMessage = next ? "已将「\(plugin.displayName)」添加到快捷按钮栏" : "已从快捷按钮栏移除「\(plugin.displayName)」"
    }

    func setPluginCapabilityGranted(_ plugin: PluginDescriptor, capability: PluginCapability, granted: Bool) throws {
        try PluginSystem.setPluginCapabilityGranted(id: plugin.id, capability: capability, granted: granted)
        reloadPlugins()
        PluginCustomWebWindowController.shared.syncPluginState(for: plugin.id, plugins: plugins)
    }

    func grantMissingCapabilitiesAndRerun(_ plugin: PluginDescriptor) {
        let missing = plugin.declaredCapabilities.filter { !plugin.grantedCapabilities.contains($0) }
        guard !missing.isEmpty else { return }
        for cap in missing {
            try? PluginSystem.setPluginCapabilityGranted(id: plugin.id, capability: cap, granted: true)
        }
        reloadPlugins()
        PluginCustomWebWindowController.shared.syncPluginState(for: plugin.id, plugins: plugins)
        guard let updated = plugins.first(where: { $0.id == plugin.id }) else { return }
        activeInlinePlugin = updated
        let q = scopedPluginID == updated.id
            ? overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            : stripMatchedPluginKeyword(from: overlayQuery, plugin: updated)
        runPlugin(updated, query: q, showInline: true)
    }

    func setPluginResourceScopeGranted(_ plugin: PluginDescriptor, scope: PluginResourceScope, granted: Bool) throws {
        try PluginSystem.setPluginResourceScopeGranted(id: plugin.id, scope: scope, granted: granted)
        reloadPlugins()
        PluginCustomWebWindowController.shared.syncPluginState(for: plugin.id, plugins: plugins)
    }

    func openBuiltinPluginSettings(_ plugin: PluginDescriptor) {
        switch plugin.builtinMetadata?.settingsTarget {
        case "mos": openRoute(.settings(.mos))
        case "lumaLink": openRoute(.settings(.lumaLink))
        case "monitor": openRoute(.settings(.monitor))
        default: openRoute(.settings(.plugins))
        }
    }

    func openPluginSettings(id: String) {
        if let plugin = plugins.first(where: { $0.id == id && $0.isBuiltin }) {
            openBuiltinPluginSettings(plugin)
            return
        }
        activePluginSettingsID = id
        openRoute(.pluginSettings(id))
    }

    func openPluginCustomWindow(_ plugin: PluginDescriptor) {
        guard plugin.isEnabled && plugin.isValid, plugin.manifest.window != nil else { return }
        if !plugin.grantedCapabilities.contains(.floatingWindow),
           plugin.declaredCapabilities.contains(.floatingWindow) {
            try? setPluginCapabilityGranted(plugin, capability: .floatingWindow, granted: true)
        }
        let updated = plugins.first(where: { $0.id == plugin.id }) ?? plugin
        let spec = PluginCustomWindowSpec.resolve(plugin: updated)
        _ = PluginCustomWebWindowController.shared.open(spec: spec, viewModel: self)
    }

    func openPreferredFloatingWindow(for plugin: PluginDescriptor, seedPayload: PluginViewPayload? = nil) {
        if plugin.manifest.window != nil {
            openPluginCustomWindow(plugin)
        } else {
            openFloatingPluginPanel(for: plugin, seedPayload: seedPayload)
        }
    }

    func enterPluginScopedOverlay(_ plugin: PluginDescriptor, initialQuery: String = "") {
        onShowOverlayRequest?(.plugins)
        scopedPluginID = plugin.id
        overlayQuery = initialQuery
        let hasIndexedItems = pluginSearchEntries.contains { $0.pluginID == plugin.id }
            || !plugin.declaredCommands.isEmpty
        if !hasIndexedItems {
            runPlugin(plugin, query: initialQuery, showInline: true)
        } else if !plugin.isBuiltin && PluginDataInspector.inspect(plugin).needsAutoRefresh {
            runBackgroundPluginSync(plugin)
        }
        refreshDisplayedCandidates(resetSelection: true)
        bumpFocusToken()
    }

    func runPluginWithContext(_ plugin: PluginDescriptor, context: PluginContextPayload) {
        onShowOverlayRequest?(.plugins)
        scopedPluginID = plugin.id
        overlayQuery = ""
        runPlugin(plugin, query: context.primaryQuery, contextPayload: context, showInline: true)
    }

    func triggerStalePluginIndexRefreshIfNeeded() {
        for plugin in plugins where !plugin.isBuiltin && plugin.isEnabled && plugin.isValid {
            if PluginDataInspector.inspect(plugin).needsAutoRefresh {
                runBackgroundPluginSync(plugin)
            }
        }
    }

    func runPlugin(
        _ plugin: PluginDescriptor,
        query: String,
        arguments: [String] = [],
        contextPayload: PluginContextPayload? = nil,
        showInline: Bool = false
    ) {
        pluginRunTask?.cancel()
        PluginSystem.recordPluginUsage(id: plugin.id)
        let clipText = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        let bridgeContext = makePluginBridgeContext()
        serviceMessage = L10n.pick("正在执行：\(plugin.displayName)…", "Running \(plugin.displayName)…")
        pluginRunTask = Task { [weak self] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: query, clipboardText: clipText,
                    arguments: arguments, contextPayload: contextPayload,
                    hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = resolved.plainText
                if plugin.isBuiltin, resolved.execution.exitCode == 0 {
                    self.syncBuiltinControllerState(id: plugin.id)
                } else if plugin.id == LumaLinkServer.companionPluginID, resolved.execution.exitCode == 0 {
                    self.refreshLumaLinkStatus(refreshPermissions: false)
                }
                if resolved.execution.exitCode == 0 {
                    self.reloadPlugins()
                }
                let updatedPlugin = self.plugins.first(where: { $0.id == plugin.id }) ?? plugin
                if let effect = resolved.viewPayload?.effect {
                    self.applyPluginPostActionEffect(effect, sourcePlugin: updatedPlugin, seedPayload: resolved.viewPayload)
                }
                let openedPanelAndClosed = (
                    resolved.viewPayload?.effect?.openFloatingPanel == true
                    || resolved.viewPayload?.effect?.openWindow != nil
                ) && resolved.viewPayload?.effect?.closeOverlay == true
                if showInline && !openedPanelAndClosed {
                    if let payload = resolved.viewPayload {
                        self.activeInlinePlugin = updatedPlugin
                        self.inlinePluginViewPayload = payload
                        self.inlineResultBody = nil
                    } else {
                        self.inlinePluginViewPayload = nil
                        self.inlineResultTitle = updatedPlugin.displayName
                        let diagNote = resolved.viewParseDiagnostic.map { "\($0)\n\n" } ?? ""
                        let body = resolved.plainText.isEmpty ? "(无输出)" : resolved.plainText
                        self.inlineResultBody = diagNote + body
                    }
                }
                if self.serviceMessage == nil || payloadHasNoToast(resolved.viewPayload) {
                    self.serviceMessage = resolved.execution.exitCode == 0
                        ? L10n.pick("\(updatedPlugin.displayName) 已就绪 (\(resolved.execution.durationMs) ms)", "\(updatedPlugin.displayName) ready (\(resolved.execution.durationMs) ms)")
                        : "插件返回退出码 \(resolved.execution.exitCode)"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = error.localizedDescription
                self.serviceMessage = error.localizedDescription
            }
        }
    }

    func runBackgroundPluginSync(_ plugin: PluginDescriptor, arguments: [String] = ["--sync"]) {
        guard backgroundPluginTasks[plugin.id] == nil else { return }
        let bridgeContext = makePluginBridgeContext()
        backgroundPluginTasks[plugin.id] = Task { [weak self] in
            defer { self?.backgroundPluginTasks.removeValue(forKey: plugin.id) }
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: "", arguments: arguments, hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                if resolved.execution.exitCode == 0 {
                    self.reloadPluginSearchIndex()
                    self.reloadPlugins()
                    if let note = resolved.viewPayload?.effect?.notification {
                        _ = PluginNotificationService.shared.post(note, pluginID: plugin.id, pluginName: plugin.displayName)
                    }
                }
            } catch {}
        }
    }

    private func syncBuiltinControllerState(id: String) {
        switch BuiltinPluginID(rawValue: id) {
        case .mos: mosConfig = MosConfig.load(); refreshMosStatus()
        case .systemPulse:
            let cfg = SystemMonitorConfig.load()
            SystemPulseWindowController.shared.setFloatingEnabled(cfg.floatingEnabled)
            SystemPulseWindowController.shared.setMenuBarEnabled(cfg.showInMenuBar)
        case nil: break
        }
        reloadPlugins()
    }

    private func payloadHasNoToast(_ payload: PluginViewPayload?) -> Bool {
        guard let toast = payload?.effect?.toast else { return true }
        return toast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
