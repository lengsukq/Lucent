import AppKit
import Carbon
import LumakeyCore

extension MenuBarAndWindowCoordinator {
    func appendPinnedPluginsAndScripts(to menu: NSMenu) {
        let pinnedPlugins = PluginCommandRegistry.enabledMenuBarItems(for: viewModel.plugins)
        let pinnedScripts = viewModel.scripts.filter { $0.isEnabled && $0.showInMenuBar }
        guard !pinnedPlugins.isEmpty || !pinnedScripts.isEmpty else { return }

        if !menu.items.isEmpty { menu.addItem(.separator()) }
        for pItem in pinnedPlugins {
            menu.addItem(makePinnedPluginMenuItem(pItem))
        }
        for script in pinnedScripts {
            menu.addItem(makePinnedScriptMenuItem(script))
        }
    }

    private func makePinnedPluginMenuItem(_ pinned: PluginQuickButtonItem) -> NSMenuItem {
        let label = switch pinned.target {
        case .plugin: pinned.title
        case .command: "\(pinned.pluginName) · \(pinned.title)"
        }
        let item = makeCallbackMenuItem(title: label) { [weak self] in
            self?.viewModel.executeMenuBarPluginItem(pinned)
        }
        if let iconURL = pinned.customIconURL,
           let img = IconCache.shared.pluginIcon(for: iconURL, pointSize: 15) {
            item.image = img
        } else {
            item.image = NSImage(systemSymbolName: pinned.symbolName, accessibilityDescription: nil)
        }
        if let plug = viewModel.plugins.first(where: { $0.id == pinned.pluginID }) {
            let rawHK: String? = switch pinned.target {
            case .plugin: plug.effectiveHotKey
            case .command(_, let cmdID): plug.effectiveCommandHotKey(for: cmdID)
            }
            if let rawHK, let chord = HotKeyChord.parse(rawHK) {
                applyMenuShortcut(chord: chord, to: item)
            }
        }
        return item
    }

    private func makePinnedScriptMenuItem(_ script: ScriptRecord) -> NSMenuItem {
        let item = makeCallbackMenuItem(title: script.displayTitle) { [weak self] in
            self?.viewModel.runScript(script)
        }
        if let iconURL = script.customIconURL(in: ScriptLibraryStore.shared.scriptsDirectory),
           let img = IconCache.shared.pluginIcon(for: iconURL, pointSize: 15) {
            item.image = img
        } else {
            item.image = NSImage(systemSymbolName: script.symbolIconName, accessibilityDescription: nil)
        }
        if let rawHK = script.hotKey, let chord = HotKeyChord.parse(rawHK) {
            applyMenuShortcut(chord: chord, to: item)
        }
        return item
    }
}
