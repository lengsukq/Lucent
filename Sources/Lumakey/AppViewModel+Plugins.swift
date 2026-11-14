import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    var externalPluginHotKeys: [ExternalPluginHotKey] {
        plugins.compactMap { plugin in
            guard !plugin.isBuiltin, plugin.isValid, plugin.isEnabled,
                  let raw = plugin.manifest.hotkey,
                  let chord = HotKeyChord.parse(raw) else { return nil }
            return ExternalPluginHotKey(pluginID: plugin.id, pluginName: plugin.manifest.name, chord: chord)
        }
    }

    func externalPluginHotKeyBindings() -> [ExternalHotKeyBinding] {
        externalPluginHotKeys.map { item in
            ExternalHotKeyBinding(pluginID: item.pluginID, chord: item.chord) { [weak self] in
                self?.triggerExternalPluginHotKey(pluginID: item.pluginID)
            }
        }
    }

    func triggerExternalPluginHotKey(pluginID: String) {
        guard let plugin = plugins.first(where: { $0.id == pluginID && !$0.isBuiltin && $0.isValid && $0.isEnabled }) else {
            return
        }
        let captured = PluginSelectionReader.captureFrontmostSelection()
        onShowOverlayRequest?(.plugins)
        lastCapturedSelection = captured
        overlayQuery = ""
        if let idx = displayedCandidates.firstIndex(where: {
            if case .plugin(let desc) = $0.kind { return desc.id == pluginID }
            return false
        }) {
            overlaySelectedIndex = idx
        }
        runPlugin(plugin, query: captured.text, showInline: true)
    }

    func reloadPlugins() {
        plugins = PluginSystem.listPlugins(includeBuiltin: true)
        pluginSearchEntries = PluginSearchIndex.loadEntries(for: plugins)
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
        PluginBridgeHostContext(everythingIndex: everythingIndex, preCapturedSelection: lastCapturedSelection)
    }

    func setPluginEnabled(_ plugin: PluginDescriptor, isEnabled: Bool) throws {
        if let builtin = BuiltinPluginID(rawValue: plugin.id) {
            switch builtin {
            case .mos:
                var next = mosConfig
                next.enabled = isEnabled
                applyMosConfig(next)
            case .lumaLink:
                var next = lumaLinkConfig
                next.enabled = isEnabled
                applyLumaLinkConfig(next)
            case .systemPulse:
                SystemPulseWindowController.shared.setFloatingEnabled(isEnabled)
                if !isEnabled { SystemPulseWindowController.shared.setMenuBarEnabled(false) }
                reloadPlugins()
            }
            return
        }
        try PluginSystem.setPluginEnabled(id: plugin.id, isEnabled: isEnabled)
        reloadPluginsAndHotKeys()
    }

    func setPluginCapabilityGranted(_ plugin: PluginDescriptor, capability: PluginCapability, granted: Bool) throws {
        try PluginSystem.setPluginCapabilityGranted(id: plugin.id, capability: capability, granted: granted)
        reloadPlugins()
    }

    func openBuiltinPluginSettings(_ plugin: PluginDescriptor) {
        switch plugin.builtinMetadata?.settingsTarget {
        case "mos": openRoute(.settings(.mos))
        case "lumaLink": openRoute(.settings(.lumaLink))
        case "monitor": openRoute(.settings(.monitor))
        default: openRoute(.settings(.plugins))
        }
    }

    func handlePluginOpenURL(_ url: URL) {
        if url.scheme == "lumakey", url.host == "settings" {
            let target = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch target {
            case "mos": openRoute(.settings(.mos))
            case "lumaLink": openRoute(.settings(.lumaLink))
            case "monitor": openRoute(.settings(.monitor))
            case "plugins": openRoute(.settings(.plugins))
            default: openRoute(.settings(.general))
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    func runPlugin(_ plugin: PluginDescriptor, query: String, arguments: [String] = [], showInline: Bool = false) {
        pluginRunTask?.cancel()
        let clipText = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        let bridgeContext = makePluginBridgeContext()
        serviceMessage = "正在运行插件：\(plugin.manifest.name)…"
        pluginRunTask = Task { [weak self] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: query, clipboardText: clipText,
                    arguments: arguments, hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = resolved.plainText
                if resolved.execution.exitCode == 0 {
                    self.pluginSearchEntries = PluginSearchIndex.loadEntries(for: self.plugins)
                }
                if showInline {
                    if let payload = resolved.viewPayload {
                        self.activeInlinePlugin = plugin
                        self.inlinePluginViewPayload = payload
                        self.inlineResultBody = nil
                        if let effect = payload.effect {
                            if effect.reloadSearchIndex == true {
                                self.reloadPluginSearchIndex()
                            }
                            if effect.closeOverlay == true {
                                self.onHideOverlayRequest?()
                            }
                            if let toast = effect.toast, !toast.isEmpty {
                                self.serviceMessage = toast
                            }
                        }
                    } else {
                        self.inlinePluginViewPayload = nil
                        self.inlineResultTitle = "插件：\(plugin.manifest.name)"
                        let diagNote = resolved.viewParseDiagnostic.map { "\($0)\n\n" } ?? ""
                        let body = resolved.plainText.isEmpty ? "(无输出)" : resolved.plainText
                        self.inlineResultBody = diagNote + body
                    }
                }
                if self.serviceMessage == nil || payloadHasNoToast(resolved.viewPayload) {
                    self.serviceMessage = resolved.execution.exitCode == 0
                        ? "插件 \(plugin.manifest.name) 完成 (\(resolved.execution.durationMs) ms)"
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
        backgroundPluginTasks[plugin.id]?.cancel()
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
                }
            } catch {}
        }
    }

    private func payloadHasNoToast(_ payload: PluginViewPayload?) -> Bool {
        guard let toast = payload?.effect?.toast else { return true }
        return toast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
