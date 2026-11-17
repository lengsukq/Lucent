import AppKit
import Foundation
import LumakeyCore

extension PluginDedicatedSettingsState {
    func syncSearchIndexNow(for plugin: PluginDescriptor, ctrl: PluginCenterController, viewModel: AppViewModel) {
        guard !isSyncingIndex else { return }
        ctrl.flushPendingSaveIfNeeded()

        let latest = viewModel.plugins.first(where: { $0.id == plugin.id }) ?? plugin
        guard latest.isEnabled else {
            let msg = L10n.pick(
                "插件「\(latest.displayName)」当前已停用，请先开启开关后再同步。",
                "\"\(latest.displayName)\" is disabled. Turn it on before syncing."
            )
            bannerMessage = msg
            viewModel.serviceMessage = msg
            return
        }

        let missingCaps = latest.declaredCapabilities.filter { !latest.grantedCapabilities.contains($0) }
        let missingScopes = latest.revokedResourceScopes
        if !missingCaps.isEmpty || !missingScopes.isEmpty {
            syncNeedsPluginGrant = true
            syncPermissionActionURL = nil
            syncPermissionActionTitle = nil
            let msg = L10n.pick(
                "「\(latest.displayName)」缺少必要扩展权限，同步未执行。点击「一键授权并同步」即可继续。",
                "\"\(latest.displayName)\" lacks required permissions. Click Grant & Sync to proceed."
            )
            bannerMessage = msg
            viewModel.serviceMessage = msg
            return
        }

        isSyncingIndex = true
        syncNeedsPluginGrant = false
        syncPermissionActionURL = nil
        syncPermissionActionTitle = nil
        bannerMessage = L10n.pick("正在同步「\(latest.displayName)」…", "Syncing \(latest.displayName)…")
        ctrl.isRunning = true

        let bridgeContext = viewModel.makePluginBridgeContext()
        Task { @MainActor [weak self, weak viewModel, weak ctrl] in
            do {
                let resolved = try await PluginSystem.runPluginAsync(
                    latest,
                    query: "",
                    clipboardText: "",
                    arguments: ["--sync"],
                    hostContext: bridgeContext
                )
                guard let self, let viewModel else { return }
                self.isSyncingIndex = false
                ctrl?.isRunning = false
                ctrl?.latestOutput = resolved
                viewModel.reloadPluginSearchIndex()
                viewModel.reloadPlugins()
                let updated = viewModel.plugins.first(where: { $0.id == latest.id }) ?? latest
                self.refreshDataStatus(for: updated)
                self.applySyncOutcome(resolved, plugin: updated, ctrl: ctrl, viewModel: viewModel)
            } catch {
                guard let self else { return }
                self.isSyncingIndex = false
                ctrl?.isRunning = false
                let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.bannerMessage = msg
                ctrl?.statusNote = msg
                viewModel?.serviceMessage = msg
            }
        }
    }

    func grantPermissionsAndSyncNow(for plugin: PluginDescriptor, ctrl: PluginCenterController, viewModel: AppViewModel) {
        let latest = viewModel.plugins.first(where: { $0.id == plugin.id }) ?? plugin
        for cap in latest.declaredCapabilities where !latest.grantedCapabilities.contains(cap) {
            try? viewModel.setPluginCapabilityGranted(latest, capability: cap, granted: true)
        }
        for scope in latest.revokedResourceScopes {
            try? viewModel.setPluginResourceScopeGranted(latest, scope: scope, granted: true)
        }
        viewModel.reloadPlugins()
        let updated = viewModel.plugins.first(where: { $0.id == plugin.id }) ?? latest
        syncNeedsPluginGrant = false
        syncSearchIndexNow(for: updated, ctrl: ctrl, viewModel: viewModel)
    }

    private func applySyncOutcome(
        _ resolved: PluginResolvedOutput,
        plugin: PluginDescriptor,
        ctrl: PluginCenterController?,
        viewModel: AppViewModel
    ) {
        if resolved.execution.exitCode != 0 {
            let err = resolved.execution.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = err.isEmpty
                ? L10n.pick("同步失败（退出码 \(resolved.execution.exitCode)）", "Sync failed (exit \(resolved.execution.exitCode))")
                : err
            bannerMessage = msg
            ctrl?.statusNote = msg
            viewModel.serviceMessage = msg
            return
        }

        if let permItem = resolved.viewPayload?.systemPrivacyPromptItem,
           let rawURL = permItem.openURL,
           let url = URL(string: rawURL) {
            syncPermissionActionURL = url
            syncPermissionActionTitle = permItem.title
            let toast = resolved.viewPayload?.effect?.toast?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = toast.isEmpty ? permItem.title : toast
            bannerMessage = msg
            ctrl?.statusNote = msg
            viewModel.serviceMessage = msg
            return
        }

        let toast = resolved.viewPayload?.effect?.toast?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let count = dataStatus?.searchIndexEntryCount ?? 0
        let msg = toast.isEmpty
            ? L10n.pick("已同步「\(plugin.displayName)」索引（共 \(count) 条）", "Synced \(plugin.displayName) (\(count) indexed)")
            : toast
        bannerMessage = msg
        ctrl?.statusNote = msg
        viewModel.serviceMessage = msg
    }
}
