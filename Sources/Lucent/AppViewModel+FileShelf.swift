import AppKit
import LucentCore

extension AppViewModel {
    func authorizeFileShelfIfNeeded(_ plugin: PluginDescriptor) -> PluginDescriptor? {
        guard plugin.isEnabled, plugin.isValid, plugin.declaredCapabilities.contains(.fileShelf),
              !plugin.isCapabilityGranted(.fileShelf) else { return plugin }
        let alert = NSAlert()
        alert.messageText = L10n.pick("允许「\(plugin.displayName)」使用文件中转站？",
                                     "Allow “\(plugin.displayName)” to use File Shelf?")
        alert.informativeText = PluginCapability.fileShelf.summary
        alert.addButton(withTitle: L10n.pick("允许", "Allow"))
        alert.addButton(withTitle: L10n.pick("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            serviceMessage = L10n.pick("尚未允许使用文件中转站。", "File Shelf access was not granted.")
            return nil
        }
        do {
            try setPluginCapabilityGranted(plugin, capability: .fileShelf, granted: true)
            return plugins.first { $0.id == plugin.id }
        } catch {
            serviceMessage = error.localizedDescription
            return nil
        }
    }

    func openFileShelfDirectly(_ plugin: PluginDescriptor) {
        guard let authorized = authorizeFileShelfIfNeeded(plugin) else { return }
        PluginSystem.recordPluginUsage(id: authorized.id)
        if !FileShelfPanels.shared.open(pluginID: authorized.id, urls: [], takeFocus: true, expandIfTucked: true) {
            serviceMessage = L10n.pick("无法打开文件中转站。", "Unable to open File Shelf.")
        }
    }
}


extension PluginDescriptor {
    var fileContextActionTitle: String {
        declaredCapabilities.contains(.fileShelf)
            ? L10n.pick("放入\(displayName)", "Add to \(displayName)")
            : displayName
    }
}
