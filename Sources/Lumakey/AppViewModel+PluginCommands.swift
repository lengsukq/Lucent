import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    var externalPluginHotKeys: [ExternalPluginHotKey] {
        var bindings: [ExternalPluginHotKey] = []
        for plugin in plugins where plugin.isValid && (plugin.isBuiltin || plugin.isEnabled) {
            if !plugin.isBuiltin,
               let raw = plugin.effectiveHotKey,
               let chord = HotKeyChord.parse(raw) {
                bindings.append(ExternalPluginHotKey(pluginID: plugin.id, pluginName: plugin.displayName, chord: chord))
            }
            for spec in plugin.declaredCommands {
                if let rawCmdHK = plugin.effectiveCommandHotKey(for: spec.id),
                   let chord = HotKeyChord.parse(rawCmdHK) {
                    let cmdTitle = plugin.manifest.localizedCommandTitle(spec)
                    bindings.append(ExternalPluginHotKey(
                        pluginID: plugin.id,
                        commandID: spec.id,
                        pluginName: "\(plugin.displayName) · \(cmdTitle)",
                        chord: chord
                    ))
                }
            }
        }
        return bindings
    }

    func externalPluginHotKeyBindings() -> [ExternalHotKeyBinding] {
        externalPluginHotKeys.map { item in
            ExternalHotKeyBinding(pluginID: item.pluginID, chord: item.chord) { [weak self] in
                if let commandID = item.commandID {
                    self?.triggerPluginCommandHotKey(pluginID: item.pluginID, commandID: commandID)
                } else {
                    self?.triggerExternalPluginHotKey(pluginID: item.pluginID)
                }
            }
        }
    }

    func triggerExternalPluginHotKey(pluginID: String) {
        guard let plugin = plugins.first(where: { $0.id == pluginID && !$0.isBuiltin && $0.isValid && $0.isEnabled }) else {
            return
        }
        let captured = PluginSelectionReader.captureFrontmostSelection(allowCopyFallback: true)
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        lastCapturedSelection = captured
        skipNextSelectionCapture = true
        onShowOverlayRequest?(.plugins)
        skipNextSelectionCapture = false
        lastCapturedSelection = captured
        scopedPluginID = plugin.id
        overlayQuery = ""
        runPlugin(plugin, query: captured.text, showInline: true)
    }

    func triggerPluginCommandHotKey(pluginID: String, commandID: String) {
        guard let plugin = plugins.first(where: { $0.id == pluginID && $0.isValid && ($0.isBuiltin || $0.isEnabled) }),
              let spec = plugin.declaredCommands.first(where: { $0.id == commandID })
        else { return }
        let captured = PluginSelectionReader.captureFrontmostSelection(allowCopyFallback: false)
        lastCapturedSelection = captured
        let query = spec.passQuery == true ? captured.text : ""
        let silent = spec.silentWhenHotKeyTriggered ?? plugin.isBuiltin
        if !silent {
            skipNextSelectionCapture = true
            onShowOverlayRequest?(.plugins)
            skipNextSelectionCapture = false
            lastCapturedSelection = captured
            scopedPluginID = plugin.id
            overlayQuery = ""
        }
        runPlugin(plugin, query: query, arguments: spec.arguments, showInline: !silent)
    }

    func executePluginRegisteredCommand(_ regCmd: PluginRegisteredCommand, rawQuery: String) {
        guard let plugin = plugins.first(where: { $0.id == regCmd.pluginID }) else { return }
        let trailing = PluginCommandRegistry.extractTrailingQuery(rawQuery: rawQuery, for: regCmd)
        runPlugin(plugin, query: trailing, arguments: regCmd.command.arguments, showInline: true)
    }

    func executeQuickButton(_ item: PluginQuickButtonItem) {
        switch item.target {
        case .plugin(let pluginID):
            guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return }
            if plugin.isBuiltin {
                runPlugin(plugin, query: "", showInline: true)
            } else {
                enterPluginScopedOverlay(plugin)
            }
        case .command(let pluginID, let commandID):
            guard let plugin = plugins.first(where: { $0.id == pluginID }),
                  let spec = plugin.declaredCommands.first(where: { $0.id == commandID })
            else { return }
            runPlugin(plugin, query: "", arguments: spec.arguments, showInline: true)
        }
    }

    func togglePluginCommandQuickButton(_ regCmd: PluginRegisteredCommand) {
        setPluginCommandQuickButton(
            pluginID: regCmd.pluginID, commandID: regCmd.command.id,
            title: regCmd.localizedTitle, enabled: !regCmd.isQuickButtonEnabled
        )
    }

    func setPluginCommandQuickButton(pluginID: String, commandID: String, title: String, enabled: Bool) {
        do {
            try PluginSystem.setPluginCommandQuickButton(pluginID: pluginID, commandID: commandID, enabled: enabled)
            reloadPlugins()
            serviceMessage = enabled ? "已将「\(title)」添加到快捷按钮栏" : "已将「\(title)」从快捷按钮栏移除"
        } catch {
            serviceMessage = error.localizedDescription
        }
    }

    func setPluginCommandSearchEnabled(pluginID: String, commandID: String, title: String, enabled: Bool) {
        do {
            try PluginSystem.setPluginCommandSearchEnabled(pluginID: pluginID, commandID: commandID, enabled: enabled)
            reloadPlugins()
            serviceMessage = enabled ? "已在全局搜索启用子功能「\(title)」" : "已从全局搜索隐藏子功能「\(title)」"
        } catch {
            serviceMessage = error.localizedDescription
        }
    }

    func removeQuickButton(_ item: PluginQuickButtonItem) {
        switch item.target {
        case .plugin(let pluginID):
            guard let plugin = plugins.first(where: { $0.id == pluginID }) else { return }
            try? PluginSystem.updatePluginOverrides(id: plugin.id) { $0.pinnedInOverlay = false }
            reloadPlugins()
            serviceMessage = "已从快捷按钮移除「\(plugin.displayName)」"
        case .command(let pluginID, let commandID):
            setPluginCommandQuickButton(pluginID: pluginID, commandID: commandID, title: item.title, enabled: false)
        }
    }

    func clearAllQuickButtons(for plugin: PluginDescriptor) {
        try? PluginSystem.updatePluginOverrides(id: plugin.id) {
            $0.pinnedInOverlay = false
            $0.quickButtonCommandIDs = []
        }
        reloadPlugins()
        serviceMessage = "已关闭「\(plugin.displayName)」的全部快捷按钮"
    }
}
