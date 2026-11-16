import AppKit
import Foundation
import LumakeyCore
import SwiftUI

@MainActor
final class PluginStoreController: ObservableObject {
    static let officialSourceID = "official"

    @Published var stores: [PluginStoreSubscription] = []
    @Published var selectedSourceID: String = PluginStoreController.officialSourceID
    @Published var smartURLInput: String = ""
    @Published var isResolvingURL: Bool = false
    @Published var isRefreshingStore: Bool = false
    @Published var installingPluginID: String? = nil
    @Published var pendingSingleCandidate: SinglePluginCandidate? = nil
    @Published var showFormatGuideSheet: Bool = false
    @Published var bannerMessage: String? = nil
    @Published var isErrorBanner: Bool = false

    private var activeTask: Task<Void, Never>?

    var selectedStore: PluginStoreSubscription? {
        stores.first { $0.id == selectedSourceID }
    }

    func loadSavedStores() {
        let catalog = PluginStoreService.loadCatalog()
        stores = catalog.stores
        if selectedSourceID != Self.officialSourceID,
           !stores.contains(where: { $0.id == selectedSourceID }) {
            selectedSourceID = stores.first?.id ?? Self.officialSourceID
        }
    }

    func pasteClipboardURL() {
        guard let raw = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }
        smartURLInput = raw
    }

    func submitSmartURL(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        let input = smartURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            showBanner(L10n.pick("请先输入或粘贴商店 / 插件地址", "Paste a store or plugin URL first"), isError: true)
            return
        }
        activeTask?.cancel()
        isResolvingURL = true
        bannerMessage = nil

        activeTask = Task { [weak self, weak viewModel, weak centerCtrl] in
            do {
                let resolved = try await PluginStoreSniffer.resolveSource(from: input)
                guard !Task.isCancelled, let self else { return }
                self.isResolvingURL = false
                switch resolved {
                case .storeRegistry(let sub):
                    let updated = try PluginStoreService.upsertStore(sub)
                    self.stores = updated.stores
                    self.selectedSourceID = sub.id
                    self.smartURLInput = ""
                    let msg = L10n.pick(
                        "已识别并入驻商店「\(sub.manifest.storeName)」（\(sub.manifest.plugins.count) 款插件）",
                        "Added store '\(sub.manifest.storeName)' (\(sub.manifest.plugins.count) plugins)"
                    )
                    self.showBanner(msg, isError: false)
                    centerCtrl?.statusNote = msg
                case .singlePlugin(let candidate):
                    self.pendingSingleCandidate?.cleanupStagingIfNeeded()
                    self.pendingSingleCandidate = candidate
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isResolvingURL = false
                let reason = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.showBanner(reason, isError: true)
                _ = viewModel
            }
        }
    }

    func confirmInstallSingleCandidate(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        guard let candidate = pendingSingleCandidate else { return }
        pendingSingleCandidate = nil
        do {
            let installed = try PluginStoreService.installSingleCandidate(candidate)
            smartURLInput = ""
            viewModel.reloadPluginsAndHotKeys()
            centerCtrl.select(installed)
            let msg = L10n.pick(
                "已安装插件：\(installed.displayName) v\(installed.manifest.version)",
                "Installed plugin: \(installed.displayName) v\(installed.manifest.version)"
            )
            showBanner(msg, isError: false)
            centerCtrl.statusNote = msg
            viewModel.serviceMessage = msg
            viewModel.openPluginSettings(id: installed.id)
        } catch {
            let reason = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
            showBanner(reason, isError: true)
        }
    }

    func cancelSingleCandidate() {
        pendingSingleCandidate?.cleanupStagingIfNeeded()
        pendingSingleCandidate = nil
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
                let reason = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.showBanner(reason, isError: true)
            }
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
                let reason = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
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
        {
          "schemaVersion": 1,
          "storeId": "my-custom-store",
          "storeName": "我的自定义插件源",
          "maintainer": "Your Name",
          "updatedAt": "2026-11-15T12:00:00Z",
          "plugins": [
            {
              "id": "demo-plugin",
              "name": "示例插件",
              "version": "1.0.0",
              "description": "插件功能简介",
              "mode": "view",
              "keywords": ["demo"],
              "capabilities": [],
              "resourceScopes": [],
              "downloadURL": "./dist/demo-plugin.zip",
              "sha256": "<64位SHA256摘要>"
            }
          ]
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sample, forType: .string)
        showBanner(L10n.pick("已复制 lumakey-registry.json 模板到剪贴板", "Copied lumakey-registry.json template"), isError: false)
    }

    private func showBanner(_ text: String, isError: Bool) {
        bannerMessage = text
        isErrorBanner = isError
    }
}
