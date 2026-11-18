import AppKit
import LucentCore
import SwiftUI

struct PluginStoreMarketplaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var centerCtrl: PluginCenterController
    @StateObject private var storeCtrl = PluginStoreController()

    var body: some View {
        let updates = storeCtrl.availableUpdates(installedPlugins: viewModel.plugins)
        VStack(alignment: .leading, spacing: 8) {
            smartAddressCard
            sourceTabsAndUpdatesBar(updates: updates)
            if let activeStore = storeCtrl.selectedStore {
                customStoreHeaderBar(activeStore)
                customStorePluginList(activeStore)
            } else {
                PluginStarterGalleryListView(
                    installedIDs: Set(viewModel.plugins.map(\.id)),
                    onInstall: { tpl in centerCtrl.installStarter(tpl, viewModel: viewModel) },
                    onOpenSettings: { id in viewModel.openPluginSettings(id: id) }
                )
            }
        }
        .onAppear { storeCtrl.loadSavedStores() }
        .sheet(item: $storeCtrl.pendingSingleCandidate) { candidate in
            SinglePluginConfirmSheet(
                candidate: candidate,
                onCancel: { storeCtrl.cancelSingleCandidate() },
                onConfirm: { storeCtrl.confirmInstallSingleCandidate(viewModel: viewModel, centerCtrl: centerCtrl) }
            )
        }
        .sheet(item: $storeCtrl.pendingEscalationUpdate) { pending in
            PluginUpdateEscalationSheet(
                update: pending,
                onCancel: { storeCtrl.pendingEscalationUpdate = nil },
                onConfirm: { storeCtrl.confirmEscalationUpdate(viewModel: viewModel, centerCtrl: centerCtrl) }
            )
        }
        .sheet(isPresented: $storeCtrl.showFormatGuideSheet) {
            PluginStoreSpecGuideSheet(
                onCopyTemplate: { storeCtrl.copyStoreRegistryTemplate() },
                onClose: { storeCtrl.showFormatGuideSheet = false }
            )
        }
    }

    private var smartAddressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(L10n.pick("智能入驻 / 直装地址", "Smart Store / Plugin URL"), systemImage: "sparkles.rectangle.stack")
                    .font(.caption.weight(.bold)).foregroundStyle(LiquidColors.textPrimary)
                Spacer(minLength: 4)
                if !storeCtrl.stores.isEmpty {
                    Button { storeCtrl.checkAllStoresForUpdates(viewModel: viewModel, centerCtrl: centerCtrl) } label: {
                        if storeCtrl.isCheckingAllStores { ProgressView().controlSize(.mini) }
                        else { Text(L10n.pick("检查全部更新", "Check Updates")) }
                    }
                    .disabled(storeCtrl.isCheckingAllStores).buttonStyle(GlassPillButtonStyle(compact: true))
                }
                Button(L10n.pick("示例仓库", "Demo Repo")) { storeCtrl.fillOfficialDemoURL(viewModel: viewModel, centerCtrl: centerCtrl) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button(L10n.pick("粘贴", "Paste")) { storeCtrl.pasteClipboardURL() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button(L10n.pick("入驻规范", "Spec")) { storeCtrl.showFormatGuideSheet = true }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            HStack(spacing: 6) {
                GlassInputField(
                    symbol: "link.badge.plus",
                    placeholder: L10n.pick("粘贴商店或单插件地址 (自动识别)", "Paste store or plugin URL"),
                    text: $storeCtrl.smartURLInput
                )
                .onSubmit { storeCtrl.submitSmartURL(viewModel: viewModel, centerCtrl: centerCtrl) }

                Button { storeCtrl.submitSmartURL(viewModel: viewModel, centerCtrl: centerCtrl) } label: {
                    if storeCtrl.isResolvingURL { ProgressView().controlSize(.mini).frame(width: 28) }
                    else { Text(L10n.pick("识别", "Add")) }
                }
                .disabled(storeCtrl.isResolvingURL).buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }

            if let msg = storeCtrl.bannerMessage, !msg.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: storeCtrl.isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(storeCtrl.isErrorBanner ? Color.orange : Color.cyan)
                    Text(msg).font(.caption2).foregroundStyle(storeCtrl.isErrorBanner ? Color.orange : LiquidColors.textSecondary).lineLimit(2)
                    Spacer(minLength: 2)
                    Button { storeCtrl.bannerMessage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(LiquidColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func sourceTabsAndUpdatesBar(updates: [PluginStoreAvailableUpdate]) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button(L10n.pick("官方精选 (\(PluginStarterGallery.templates.count))", "Official (\(PluginStarterGallery.templates.count))")) {
                        storeCtrl.selectedSourceID = PluginStoreController.officialSourceID
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: storeCtrl.selectedSourceID == PluginStoreController.officialSourceID, compact: true))

                    ForEach(storeCtrl.stores) { sub in
                        let subUpdates = updates.filter { $0.store.id == sub.id }.count
                        let badgeSuffix = subUpdates > 0 ? " · ↑\(subUpdates)" : ""
                        Button("\(sub.manifest.storeName) (\(sub.manifest.plugins.count)\(badgeSuffix))") {
                            storeCtrl.selectedSourceID = sub.id
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: storeCtrl.selectedSourceID == sub.id, compact: true))
                    }
                }
                .padding(.vertical, 1)
            }
            if !updates.isEmpty {
                Button { storeCtrl.updateAllAvailable(viewModel: viewModel, centerCtrl: centerCtrl) } label: {
                    if storeCtrl.isUpdatingAll { ProgressView().controlSize(.mini) }
                    else { Text(L10n.pick("一键更新 (\(updates.count))", "Update All (\(updates.count))")) }
                }
                .disabled(storeCtrl.isUpdatingAll).buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }
        }
    }

    private func customStoreHeaderBar(_ store: PluginStoreSubscription) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.manifest.storeName).font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                let meta = [store.manifest.maintainer, "\(store.manifest.plugins.count) plugins"]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                Text(meta).font(.system(size: 10)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            GlassInputField(symbol: "magnifyingglass", placeholder: L10n.pick("筛选商店插件…", "Filter plugins…"), text: $storeCtrl.searchQuery)
                .frame(width: 170)

            Button { storeCtrl.refreshSelectedStore(centerCtrl: centerCtrl) } label: {
                if storeCtrl.isRefreshingStore { ProgressView().controlSize(.mini) }
                else { Text(L10n.pick("同步", "Sync")) }
            }
            .disabled(storeCtrl.isRefreshingStore).buttonStyle(GlassPillButtonStyle(compact: true))

            Button(L10n.pick("退订", "Remove")) { storeCtrl.removeSelectedStore(centerCtrl: centerCtrl) }
                .buttonStyle(GlassPillButtonStyle(compact: true))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65) }
    }

    private func customStorePluginList(_ store: PluginStoreSubscription) -> some View {
        let items = storeCtrl.filteredItems(in: store)
        return ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    store.manifest.plugins.isEmpty ? L10n.pick("商店暂无插件", "Empty Store") : L10n.pick("无匹配插件", "No Matches"),
                    systemImage: "shippingbox",
                    description: Text(store.manifest.plugins.isEmpty ? L10n.pick("该入驻源清单尚未收录插件。", "No plugins listed in this registry.") : L10n.pick("请尝试更换筛选关键词。", "Try another filter keyword."))
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 8) { ForEach(items) { item in storeItemRow(item, in: store) } }
            }
        }
    }

    private func storeItemRow(_ item: PluginStoreItem, in store: PluginStoreSubscription) -> some View {
        let state = PluginStoreService.installState(for: item, installedPlugins: viewModel.plugins)
        let installedMatch = viewModel.plugins.first(where: { !$0.isBuiltin && $0.id == item.id })
        let isBusy = storeCtrl.installingPluginID == item.id
        let sym = (item.icon?.isEmpty == false && !PluginIconResolver.looksLikeRelativeFilePath(item.icon))
            ? (item.icon ?? "puzzlepiece.extension.fill") : "puzzlepiece.extension.fill"

        return HStack(alignment: .center, spacing: 10) {
            PluginIconBadge(
                symbol: sym, customIconURL: installedMatch?.customIconURL,
                accentColor: item.accentColor, isBuiltin: false, mode: item.mode, size: 34
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.localizedName()).font(.caption.weight(.bold)).foregroundStyle(LiquidColors.textPrimary).lineLimit(1)
                    versionBadge(for: item, state: state)
                    permissionPill(for: item)
                }
                Text(item.localizedDescription()).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
                if let log = item.changelog?.trimmingCharacters(in: .whitespacesAndNewlines), !log.isEmpty, case .updateAvailable = state {
                    Text(L10n.pick("更新：\(log)", "Update: \(log)")).font(.system(size: 10, weight: .medium)).foregroundStyle(.orange).lineLimit(1)
                } else {
                    Text("触发词: \(item.keywords.joined(separator: ", "))").font(.system(size: 10, design: .monospaced)).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if state != .notInstalled {
                Button(L10n.pick("打开设置 →", "Settings →")) { viewModel.openPluginSettings(id: item.id) }
                    .buttonStyle(GlassPillButtonStyle(prominent: state == .installedUpToDate(version: item.version), compact: true))
            }
            Button { storeCtrl.requestInstallOrUpdate(item, from: store, viewModel: viewModel, centerCtrl: centerCtrl) } label: {
                if isBusy { ProgressView().controlSize(.mini).frame(width: 36) }
                else { Text(actionButtonLabel(for: state)) }
            }
            .disabled(isBusy).buttonStyle(GlassPillButtonStyle(prominent: state != .installedUpToDate(version: item.version), compact: true))
        }
        .padding(10).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func versionBadge(for item: PluginStoreItem, state: PluginStoreInstallState) -> some View {
        let (text, tint): (String, Color) = switch state {
        case .updateAvailable(let installed, let available): ("\(installed)→\(available)", .orange)
        default: ("v\(item.version)", .cyan)
        }
        return Text(text).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1.5).background(LiquidColors.pillSurface, in: Capsule())
    }

    private func permissionPill(for item: PluginStoreItem) -> some View {
        let label = item.isPureSandbox
            ? L10n.pick("纯沙盒", "Sandbox")
            : L10n.pick("\(item.declaredCapabilities.count + item.declaredResourceScopes.count) 项声明", "\(item.declaredCapabilities.count + item.declaredResourceScopes.count) perms")
        return Text(label).font(.system(size: 9, weight: .semibold))
            .foregroundStyle(item.isPureSandbox ? LiquidColors.textSecondary : Color.mint)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5).padding(.vertical, 1.5).background(LiquidColors.pillSurface, in: Capsule())
    }

    private func actionButtonLabel(for state: PluginStoreInstallState) -> String {
        switch state {
        case .notInstalled: L10n.pick("一键安装", "Install")
        case .updateAvailable: L10n.pick("更新", "Update")
        case .installedUpToDate: L10n.pick("重装", "Reinstall")
        }
    }
}
