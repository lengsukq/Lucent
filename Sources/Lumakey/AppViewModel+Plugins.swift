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

    func reloadPlugins() {
        plugins = PluginSystem.listPlugins(includeBuiltin: true)
    }

    func reloadAppsAndPlugins() {
        reloadPlugins()
        _ = (hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.reapplyConfig(HotKeyBindingConfig.load(), persist: false)
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
        PluginBridgeHostContext(everythingIndex: everythingIndex)
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
        reloadAppsAndPlugins()
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
                if showInline {
                    if let payload = resolved.viewPayload {
                        self.activeInlinePlugin = plugin
                        self.inlinePluginViewPayload = payload
                        self.inlineResultBody = nil
                    } else {
                        self.inlinePluginViewPayload = nil
                        self.inlineResultTitle = "插件：\(plugin.manifest.name)"
                        self.inlineResultBody = resolved.plainText.isEmpty ? "(无输出)" : resolved.plainText
                    }
                }
                self.serviceMessage = resolved.execution.exitCode == 0
                    ? "插件 \(plugin.manifest.name) 完成 (\(resolved.execution.durationMs) ms)"
                    : "插件返回退出码 \(resolved.execution.exitCode)"
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.pluginOutputText = error.localizedDescription
                self.serviceMessage = error.localizedDescription
            }
        }
    }
}
