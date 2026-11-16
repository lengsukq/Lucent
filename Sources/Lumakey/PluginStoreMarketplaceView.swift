import AppKit
import LumakeyCore
import SwiftUI

struct PluginStoreMarketplaceView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var centerCtrl: PluginCenterController
    @StateObject private var storeCtrl = PluginStoreController()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            smartAddressCard
            sourceTabsStrip
            if let activeStore = storeCtrl.selectedStore {
                customStoreHeaderBar(activeStore)
                customStorePluginList(activeStore)
            } else {
                PluginStarterGalleryListView(installedIDs: Set(viewModel.plugins.map(\.id))) { tpl in
                    centerCtrl.installStarter(tpl, viewModel: viewModel)
                }
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
                Label(
                    L10n.pick("智能入驻 / 直装地址", "Smart Store / Plugin URL"),
                    systemImage: "sparkles.rectangle.stack"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(LiquidColors.textPrimary)
                Spacer(minLength: 4)
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

                Button {
                    storeCtrl.submitSmartURL(viewModel: viewModel, centerCtrl: centerCtrl)
                } label: {
                    if storeCtrl.isResolvingURL {
                        ProgressView().controlSize(.mini).frame(width: 28)
                    } else {
                        Text(L10n.pick("识别", "Add"))
                    }
                }
                .disabled(storeCtrl.isResolvingURL)
                .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }

            if let msg = storeCtrl.bannerMessage, !msg.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: storeCtrl.isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(storeCtrl.isErrorBanner ? Color.orange : Color.cyan)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(storeCtrl.isErrorBanner ? Color.orange : LiquidColors.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 2)
                    Button { storeCtrl.bannerMessage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(LiquidColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private var sourceTabsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Button(L10n.pick("官方精选 (\(PluginStarterGallery.templates.count))", "Official (\(PluginStarterGallery.templates.count))")) {
                    storeCtrl.selectedSourceID = PluginStoreController.officialSourceID
                }
                .buttonStyle(GlassPillButtonStyle(prominent: storeCtrl.selectedSourceID == PluginStoreController.officialSourceID, compact: true))

                ForEach(storeCtrl.stores) { sub in
                    Button("\(sub.manifest.storeName) (\(sub.manifest.plugins.count))") {
                        storeCtrl.selectedSourceID = sub.id
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: storeCtrl.selectedSourceID == sub.id, compact: true))
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func customStoreHeaderBar(_ store: PluginStoreSubscription) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.manifest.storeName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)
                let meta = [store.manifest.maintainer, "\(store.manifest.plugins.count) plugins"]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                Text(meta)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                storeCtrl.refreshSelectedStore(centerCtrl: centerCtrl)
            } label: {
                if storeCtrl.isRefreshingStore {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(L10n.pick("同步", "Sync"))
                }
            }
            .disabled(storeCtrl.isRefreshingStore)
            .buttonStyle(GlassPillButtonStyle(compact: true))

            Button(L10n.pick("退订", "Remove")) {
                storeCtrl.removeSelectedStore(centerCtrl: centerCtrl)
            }
            .buttonStyle(GlassPillButtonStyle(compact: true))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(LiquidColors.pillBorder, lineWidth: 0.65)
        }
    }

    private func customStorePluginList(_ store: PluginStoreSubscription) -> some View {
        ScrollView {
            if store.manifest.plugins.isEmpty {
                ContentUnavailableView(
                    L10n.pick("商店暂无插件", "Empty Store"),
                    systemImage: "shippingbox",
                    description: Text(L10n.pick("该入驻源清单尚未收录插件。", "No plugins listed in this registry."))
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.manifest.plugins) { item in
                        storeItemRow(item, in: store)
                    }
                }
            }
        }
    }

    private func storeItemRow(_ item: PluginStoreItem, in store: PluginStoreSubscription) -> some View {
        let state = PluginStoreService.installState(for: item, installedPlugins: viewModel.plugins)
        let pair = PluginVisualPalette.colors(accentColor: item.accentColor, isBuiltin: false, mode: item.mode)
        let isBusy = storeCtrl.installingPluginID == item.id

        return HStack(alignment: .center, spacing: 10) {
            SquircleBadge(
                symbol: (item.icon?.isEmpty == false) ? (item.icon ?? "puzzlepiece.extension.fill") : "puzzlepiece.extension.fill",
                topColor: pair.top,
                bottomColor: pair.bottom,
                size: 34
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.localizedName())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    versionBadge(for: item, state: state)
                    permissionPill(for: item)
                }
                Text(item.localizedDescription())
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(2)
                Text("触发词: \(item.keywords.joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                storeCtrl.installStorePlugin(item, from: store, viewModel: viewModel, centerCtrl: centerCtrl)
            } label: {
                if isBusy {
                    ProgressView().controlSize(.mini).frame(width: 36)
                } else {
                    Text(actionButtonLabel(for: state))
                }
            }
            .disabled(isBusy)
            .buttonStyle(GlassPillButtonStyle(prominent: state != .installedUpToDate(version: item.version), compact: true))
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func versionBadge(for item: PluginStoreItem, state: PluginStoreInstallState) -> some View {
        let text: String
        let tint: Color
        switch state {
        case .updateAvailable(let installed, let available):
            text = "\(installed)→\(available)"
            tint = .orange
        default:
            text = "v\(item.version)"
            tint = .cyan
        }
        return Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(LiquidColors.pillSurface, in: Capsule())
    }

    private func permissionPill(for item: PluginStoreItem) -> some View {
        let label = item.isPureSandbox
            ? L10n.pick("纯沙盒", "Sandbox")
            : L10n.pick("\(item.declaredCapabilities.count + item.declaredResourceScopes.count) 项声明", "\(item.declaredCapabilities.count + item.declaredResourceScopes.count) perms")
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(item.isPureSandbox ? LiquidColors.textSecondary : Color.mint)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(LiquidColors.pillSurface, in: Capsule())
    }

    private func actionButtonLabel(for state: PluginStoreInstallState) -> String {
        switch state {
        case .notInstalled: return L10n.pick("一键安装", "Install")
        case .updateAvailable: return L10n.pick("更新", "Update")
        case .installedUpToDate: return L10n.pick("重装", "Reinstall")
        }
    }
}
