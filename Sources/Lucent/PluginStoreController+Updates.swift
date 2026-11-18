import AppKit
import Foundation
import LucentCore

extension PluginStoreController {
    func requestInstallOrUpdate(
        _ item: PluginStoreItem,
        from store: PluginStoreSubscription,
        viewModel: AppViewModel,
        centerCtrl: PluginCenterController
    ) {
        let state = PluginStoreService.installState(for: item, installedPlugins: viewModel.plugins)
        if case .updateAvailable(let installedVer, _) = state {
            let diff = PluginStoreService.permissionDiff(for: item, installedPlugins: viewModel.plugins)
            if diff.hasEscalation {
                pendingEscalationUpdate = PluginStoreAvailableUpdate(
                    store: store, item: item, installedVersion: installedVer, permissionDiff: diff
                )
                return
            }
        }
        installStorePlugin(item, from: store, viewModel: viewModel, centerCtrl: centerCtrl)
    }

    func confirmEscalationUpdate(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        guard let pending = pendingEscalationUpdate else { return }
        pendingEscalationUpdate = nil
        installStorePlugin(pending.item, from: pending.store, viewModel: viewModel, centerCtrl: centerCtrl)
    }

    func installStorePlugin(
        _ item: PluginStoreItem,
        from store: PluginStoreSubscription,
        viewModel: AppViewModel,
        centerCtrl: PluginCenterController
    ) {
        guard installingPluginID == nil else { return }
        installingPluginID = item.id
        bannerMessage = nil

        Task { [weak self, weak viewModel, weak centerCtrl] in
            do {
                let installed = try await PluginStoreService.installStoreItem(item, from: store)
                guard let self else { return }
                self.installingPluginID = nil
                viewModel?.reloadPluginsAndHotKeys()
                if let plugins = viewModel?.plugins {
                    AppUpdateCoordinator.shared.refreshCachedPluginUpdateCount(installedPlugins: plugins)
                }
                centerCtrl?.select(installed)
                let msg = L10n.pick(
                    "已安装「\(installed.displayName)」v\(installed.manifest.version)",
                    "Installed '\(installed.displayName)' v\(installed.manifest.version)"
                )
                self.showBanner(msg, isError: false)
                centerCtrl?.statusNote = msg
            } catch {
                guard let self else { return }
                self.installingPluginID = nil
                let reason = (error as? LucentError)?.diagnostic.reason ?? error.localizedDescription
                self.showBanner(reason, isError: true)
            }
        }
    }

    func checkAllStoresForUpdates(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        guard !isCheckingAllStores, !stores.isEmpty else { return }
        isCheckingAllStores = true
        Task { [weak self, weak viewModel, weak centerCtrl] in
            let outcome = await PluginStoreService.refreshAllStores()
            guard let self else { return }
            self.isCheckingAllStores = false
            self.stores = outcome.stores
            let installed = viewModel?.plugins ?? []
            AppUpdateCoordinator.shared.refreshCachedPluginUpdateCount(installedPlugins: installed)
            let count = PluginStoreService.availableUpdates(in: outcome.stores, installedPlugins: installed).count
            let msg = count > 0
                ? L10n.pick("已同步全部订阅源，发现 \(count) 款插件有新版本可更新", "Synced all stores · \(count) updates available")
                : L10n.pick("已同步全部订阅源，所有已安装插件均为最新版本", "All subscribed plugins are up to date")
            self.showBanner(msg, isError: false)
            centerCtrl?.statusNote = msg
        }
    }

    func updateAllAvailable(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        let updates = availableUpdates(installedPlugins: viewModel.plugins)
        guard !updates.isEmpty, !isUpdatingAll else { return }
        if let firstEscalating = updates.first(where: { $0.permissionDiff.hasEscalation }) {
            pendingEscalationUpdate = firstEscalating
            return
        }
        isUpdatingAll = true
        Task { [weak self, weak viewModel, weak centerCtrl] in
            var okCount = 0
            for entry in updates {
                if (try? await PluginStoreService.installStoreItem(entry.item, from: entry.store)) != nil {
                    okCount += 1
                }
            }
            guard let self else { return }
            self.isUpdatingAll = false
            viewModel?.reloadPluginsAndHotKeys()
            if let plugins = viewModel?.plugins {
                AppUpdateCoordinator.shared.refreshCachedPluginUpdateCount(installedPlugins: plugins)
            }
            let msg = L10n.pick("已完成批量升级（成功更新 \(okCount)/\(updates.count) 款插件）", "Updated \(okCount)/\(updates.count) plugins")
            self.showBanner(msg, isError: okCount < updates.count)
            centerCtrl?.statusNote = msg
        }
    }

    func refreshSelectedStore(centerCtrl: PluginCenterController) {
        guard let store = selectedStore, !isRefreshingStore else { return }
        isRefreshingStore = true
        let storeID = store.id
        Task { [weak self, weak centerCtrl] in
            do {
                let refreshed = try await PluginStoreService.refreshStore(storeID: storeID)
                guard let self else { return }
                self.isRefreshingStore = false
                self.loadSavedStores()
                let msg = L10n.pick(
                    "已同步「\(refreshed.manifest.storeName)」（\(refreshed.manifest.plugins.count) 款插件）",
                    "Synced '\(refreshed.manifest.storeName)' (\(refreshed.manifest.plugins.count) plugins)"
                )
                self.showBanner(msg, isError: false)
                centerCtrl?.statusNote = msg
            } catch {
                guard let self else { return }
                self.isRefreshingStore = false
                let reason = (error as? LucentError)?.diagnostic.reason ?? error.localizedDescription
                self.showBanner(reason, isError: true)
            }
        }
    }

    func removeSelectedStore(centerCtrl: PluginCenterController) {
        guard let store = selectedStore else { return }
        do {
            let next = try PluginStoreService.removeStore(storeID: store.id)
            stores = next.stores
            selectedSourceID = stores.first?.id ?? Self.officialSourceID
            let msg = L10n.pick("已移除商店源：\(store.manifest.storeName)", "Removed store: \(store.manifest.storeName)")
            showBanner(msg, isError: false)
            centerCtrl.statusNote = msg
        } catch {
            showBanner(error.localizedDescription, isError: true)
        }
    }

    func copyStoreRegistryTemplate() {
        let sample = """
        {"schemaVersion":1,"storeId":"my-custom-store","storeName":"我的自定义插件源","maintainer":"Your Name","plugins":[{"id":"demo-plugin","name":"示例插件","version":"1.0.0","description":"插件功能简介","mode":"view","keywords":["demo"],"capabilities":[],"resourceScopes":[],"downloadURL":"./dist/demo-plugin.zip","sha256":"<64位SHA256摘要>"}]}
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sample, forType: .string)
        showBanner(L10n.pick("已复制 lucent-registry.json 模板到剪贴板", "Copied lucent-registry.json template"), isError: false)
    }
}
