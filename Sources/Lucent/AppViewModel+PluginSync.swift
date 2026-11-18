import AppKit
import Foundation
import LucentCore

extension AppViewModel {
    func runBackgroundPluginSync(_ plugin: PluginDescriptor, arguments: [String] = ["--sync"]) {
        guard runtime.backgroundPluginTasks[plugin.id] == nil else { return }
        let missingCaps = plugin.declaredCapabilities.filter { !plugin.grantedCapabilities.contains($0) }
        if !missingCaps.isEmpty || !plugin.revokedResourceScopes.isEmpty {
            activeInlinePlugin = plugin
            inlinePluginViewPayload = PluginViewPayload(
                title: plugin.displayName,
                subtitle: L10n.pick("需要授权扩展权限后才能执行同步", "Permissions required before syncing"),
                badge: L10n.pick("需要权限", "PERMISSION"),
                items: []
            )
            serviceMessage = L10n.pick("「\(plugin.displayName)」缺少必要权限，请在右侧点击一键授权", "\"\(plugin.displayName)\" lacks required permissions")
            return
        }
        syncingPluginIDs.insert(plugin.id)
        serviceMessage = L10n.pick("正在同步「\(plugin.displayName)」索引…", "Syncing \(plugin.displayName)…")
        let bridgeContext = makePluginBridgeContext()
        runtime.backgroundPluginTasks[plugin.id] = Task { [weak self] in
            defer {
                self?.runtime.backgroundPluginTasks.removeValue(forKey: plugin.id)
                self?.syncingPluginIDs.remove(plugin.id)
            }
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    plugin, query: "", arguments: arguments, hostContext: bridgeContext
                )
                guard !Task.isCancelled, let self else { return }
                self.reloadPluginSearchIndex()
                self.reloadPlugins()
                let updated = self.plugins.first(where: { $0.id == plugin.id }) ?? plugin
                if resolved.execution.exitCode != 0 {
                    let err = resolved.execution.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.serviceMessage = err.isEmpty ? "同步失败 (exit \(resolved.execution.exitCode))" : err
                    return
                }
                if let permItem = resolved.viewPayload?.systemPrivacyPromptItem {
                    self.activeInlinePlugin = updated
                    self.inlinePluginViewPayload = resolved.viewPayload
                    self.serviceMessage = resolved.viewPayload?.effect?.toast ?? permItem.title
                } else if let toast = resolved.viewPayload?.effect?.toast, !toast.isEmpty {
                    self.serviceMessage = toast
                } else {
                    self.serviceMessage = L10n.pick("已同步「\(updated.displayName)」索引", "Synced \(updated.displayName)")
                }
                if let note = resolved.viewPayload?.effect?.notification {
                    _ = PluginNotificationService.shared.post(note, pluginID: updated.id, pluginName: updated.displayName)
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.serviceMessage = error.localizedDescription
            }
        }
    }
}

extension PluginViewPayload {
    var systemPrivacyPromptItem: PluginViewItem? {
        items?.first(where: { $0.openURL?.hasPrefix("x-apple.systempreferences:") == true })
    }
}
