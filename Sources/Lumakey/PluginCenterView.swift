import AppKit
import LumakeyCore
import SwiftUI

struct PluginCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var ctrl: PluginCenterController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topNavigationBar
            PythonRuntimeAdvisorCard(viewModel: viewModel)
            switch ctrl.activeTab {
            case .gallery:
                PluginStoreMarketplaceView(viewModel: viewModel, centerCtrl: ctrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .mcp:
                PluginMCPSetupView(viewModel: viewModel, ctrl: ctrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .permissions:
                PluginPermissionsMatrixView(viewModel: viewModel, ctrl: ctrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .scaffold:
                PluginScaffoldFormView(viewModel: viewModel, ctrl: ctrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { ctrl.startWatching(syncing: viewModel) }
        .onDisappear { ctrl.stopWatching() }
    }

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(PluginCenterTab.allCases) { tab in
                    let active = ctrl.activeTab == tab
                    Button {
                        ctrl.activeTab = tab
                    } label: {
                        Text(tabTitle(tab))
                            .font(.caption.weight(active ? .semibold : .medium))
                            .foregroundStyle(active ? Color.white : LiquidColors.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background {
                                if active {
                                    Capsule(style: .continuous).fill(LiquidColors.accentGradient)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(LiquidColors.pillSurface, in: Capsule(style: .continuous))
            .overlay { Capsule(style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.8) }

            HStack(spacing: 5) {
                Circle().fill(ctrl.isWatcherOnline ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(ctrl.isWatcherOnline ? "热重载" : "离线")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(LiquidColors.pillSurface, in: Capsule())
            .help(ctrl.statusNote)

            Spacer(minLength: 8)

            Button("导入") { ctrl.importFromFinder(viewModel: viewModel) }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            Button("目录") { ctrl.openPluginsDirectoryInFinder() }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            Button("刷新") {
                viewModel.reloadPluginsAndHotKeys()
                ctrl.syncSelection(from: viewModel.plugins)
            }
            .buttonStyle(GlassPillButtonStyle(compact: true))
        }
    }

    private func tabTitle(_ tab: PluginCenterTab) -> String {
        switch tab {
        case .gallery: L10n.translate("精选市场")
        case .mcp: L10n.translate("MCP 接入")
        case .permissions: L10n.translate("权限清单")
        case .scaffold: L10n.translate("脚手架")
        }
    }
}
