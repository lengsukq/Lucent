import AppKit
import Foundation
import LucentCore
import SwiftUI

@MainActor
final class PluginStoreController: ObservableObject {
    static let officialSourceID = "official"

    @Published var stores: [PluginStoreSubscription] = []
    @Published var selectedSourceID: String = PluginStoreController.officialSourceID
    @Published var smartURLInput: String = ""
    @Published var searchQuery: String = ""
    @Published var isResolvingURL: Bool = false
    @Published var isRefreshingStore: Bool = false
    @Published var isCheckingAllStores: Bool = false
    @Published var isUpdatingAll: Bool = false
    @Published var installingPluginID: String? = nil
    @Published var pendingSingleCandidate: SinglePluginCandidate? = nil
    @Published var pendingEscalationUpdate: PluginStoreAvailableUpdate? = nil
    @Published var showFormatGuideSheet: Bool = false
    @Published var bannerMessage: String? = nil
    @Published var isErrorBanner: Bool = false

    private var activeTask: Task<Void, Never>?

    var selectedStore: PluginStoreSubscription? {
        stores.first { $0.id == selectedSourceID }
    }

    func availableUpdates(installedPlugins: [PluginDescriptor]) -> [PluginStoreAvailableUpdate] {
        PluginStoreService.availableUpdates(in: stores, installedPlugins: installedPlugins)
    }

    func filteredItems(in store: PluginStoreSubscription) -> [PluginStoreItem] {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.manifest.plugins }
        return store.manifest.plugins.filter { item in
            item.name.lowercased().contains(needle)
                || item.localizedName().lowercased().contains(needle)
                || item.description.lowercased().contains(needle)
                || item.localizedDescription().lowercased().contains(needle)
                || item.id.lowercased().contains(needle)
                || item.keywords.contains(where: { $0.lowercased().contains(needle) })
                || (item.categoryTag?.lowercased().contains(needle) ?? false)
        }
    }

    func loadSavedStores() {
        let catalog = PluginStoreDefaults.ensureDefaultDemoStoreSeeded()
        stores = catalog.stores
        if selectedSourceID != Self.officialSourceID,
           !stores.contains(where: { $0.id == selectedSourceID }) {
            selectedSourceID = stores.first?.id ?? Self.officialSourceID
        }
    }

    func fillOfficialDemoURL(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        smartURLInput = PluginStoreDefaults.officialDemoSourceURL
        if !stores.contains(where: { $0.id == PluginStoreDefaults.officialDemoStoreID }) {
            submitSmartURL(viewModel: viewModel, centerCtrl: centerCtrl)
        } else if let existing = stores.first(where: { $0.id == PluginStoreDefaults.officialDemoStoreID }) {
            selectedSourceID = existing.id
            showBanner(L10n.pick("已填入官方示例仓库地址：\(existing.sourceURL)", "Filled demo store URL: \(existing.sourceURL)"), isError: false)
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
                if self.tryFallbackToBundledOfficialStore(input: input, centerCtrl: centerCtrl) { return }
                self.isResolvingURL = false
                let reason = (error as? LucentError)?.diagnostic.reason ?? error.localizedDescription
                self.showBanner(reason, isError: true)
                _ = viewModel
            }
        }
    }

    private func tryFallbackToBundledOfficialStore(input: String, centerCtrl: PluginCenterController?) -> Bool {
        guard (input == PluginStoreDefaults.officialDemoSourceURL || input == PluginStoreDefaults.officialDemoRegistryURL),
              let demoDir = PluginStoreDefaults.bundledDemoDirectory(),
              let data = try? Data(contentsOf: demoDir.appendingPathComponent(PluginStoreRegistryManifest.defaultFileName)),
              let manifest = try? JSONDecoder().decode(PluginStoreRegistryManifest.self, from: data),
              manifest.validate().isEmpty else { return false }
        let now = ISO8601DateFormatter().string(from: Date())
        let sub = PluginStoreSubscription(
            sourceURL: PluginStoreDefaults.officialDemoSourceURL,
            resolvedRegistryURL: PluginStoreDefaults.officialDemoRegistryURL,
            addedAtISO8601: now, lastSyncedAtISO8601: manifest.updatedAt ?? now, manifest: manifest
        )
        guard let updated = try? PluginStoreService.upsertStore(sub) else { return false }
        isResolvingURL = false
        stores = updated.stores
        selectedSourceID = sub.id
        smartURLInput = ""
        let msg = L10n.pick(
            "已入驻官方示例商店（使用随包离线索引，共 \(manifest.plugins.count) 款插件）",
            "Added official demo store (bundled offline manifest, \(manifest.plugins.count) plugins)"
        )
        showBanner(msg, isError: false)
        centerCtrl?.statusNote = msg
        return true
    }

    func confirmInstallSingleCandidate(viewModel: AppViewModel, centerCtrl: PluginCenterController) {
        guard let candidate = pendingSingleCandidate else { return }
        pendingSingleCandidate = nil
        do {
            let installed = try PluginStoreService.installSingleCandidate(candidate)
            smartURLInput = ""
            viewModel.reloadPluginsAndHotKeys()
            centerCtrl.select(installed)
            let msg = L10n.pick("已安装插件：\(installed.displayName) v\(installed.manifest.version)", "Installed plugin: \(installed.displayName) v\(installed.manifest.version)")
            showBanner(msg, isError: false)
            centerCtrl.statusNote = msg
            viewModel.serviceMessage = msg
            viewModel.openPluginSettings(id: installed.id)
        } catch {
            let reason = (error as? LucentError)?.diagnostic.reason ?? error.localizedDescription
            showBanner(reason, isError: true)
        }
    }

    func cancelSingleCandidate() {
        pendingSingleCandidate?.cleanupStagingIfNeeded()
        pendingSingleCandidate = nil
    }

    func showBanner(_ text: String, isError: Bool) {
        bannerMessage = text
        isErrorBanner = isError
    }
}
