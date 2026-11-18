import AppKit
import LucentCore
import SwiftUI

@MainActor
final class LumaLinkConsoleUIState: ObservableObject {
    @Published var showAdvancedPluginOptions = false
}

struct LumaLinkDedicatedConsoleView<CustomCard: View>: View {
    let plugin: PluginDescriptor
    @ObservedObject var state: PluginDedicatedSettingsState
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel
    let customizationCard: () -> CustomCard
    @StateObject private var uiState = LumaLinkConsoleUIState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PluginSetupReminderAndGuideSection(
                    plugin: plugin, state: state, ctrl: ctrl, viewModel: viewModel, showUsageGuide: false
                )
                LumaLinkServiceControlCard(viewModel: viewModel, companionPlugin: plugin, ctrl: ctrl)
                LumaLinkNetworkAndPairingCard(viewModel: viewModel)
                LumaLinkSafetyAndDevicesCard(viewModel: viewModel)
                advancedPluginSection
            }
            .padding(.trailing, 6).padding(.bottom, 8)
        }
        .onAppear {
            viewModel.refreshLumaLinkStatus()
            state.bindIfNeeded(plugin: plugin, ctrl: ctrl)
        }
        .onDisappear { state.stopRecordingHotKey() }
    }

    private var advancedPluginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { uiState.showAdvancedPluginOptions.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: uiState.showAdvancedPluginOptions ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .foregroundStyle(LiquidColors.accentPrimary)
                    Text(L10n.pick("高级选项：快捷台子指令、全局热键与插件管理", "Advanced: Launcher Commands, Hotkeys & Plugin Management"))
                        .font(.caption.weight(.semibold)).foregroundStyle(LiquidColors.textPrimary)
                    Spacer()
                    Text(uiState.showAdvancedPluginOptions ? L10n.pick("收起", "Hide") : L10n.pick("展开", "Expand"))
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)

            if uiState.showAdvancedPluginOptions {
                HStack(spacing: 8) {
                    Button(L10n.pick("在快捷台打开 ↩", "Open in Launcher ↩")) { viewModel.enterPluginScopedOverlay(plugin) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                    Button(L10n.pick("插件市场 →", "Plugin Store →")) {
                        viewModel.activePluginSettingsID = nil; viewModel.activeSettingsSection = .plugins
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    Button(L10n.pick("访达目录", "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    Button(L10n.pick("卸载伴侣插件", "Uninstall Plugin")) {
                        ctrl.remove(plugin, viewModel: viewModel)
                        viewModel.activePluginSettingsID = nil; viewModel.activeSettingsSection = .plugins
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    Spacer()
                }
                PluginCommandSettingsCard(plugin: plugin, viewModel: viewModel, settingsState: state)
                customizationCard()
                PluginPermissionsAndSandboxSection(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
            }
        }
    }
}

struct LumaLinkSafetyAndDevicesCard: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.pick("已配对手机 (\(viewModel.lumaLinkConfig.pairedDevices.count)) 与安全偏好", "Paired Phones (\(viewModel.lumaLinkConfig.pairedDevices.count)) & Safety"), systemImage: "iphone.badge.play")
                .font(.callout.weight(.semibold))
            if viewModel.lumaLinkConfig.pairedDevices.isEmpty {
                Text(L10n.pick("暂无已配对手机；首次扫码或输入上方 6 位配对码连接后自动加密绑定。", "No paired phones yet; scan QR or enter 6-digit PIN above to pair."))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.lumaLinkConfig.pairedDevices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone").foregroundStyle(.cyan)
                        Text(device.name).font(.caption.weight(.semibold))
                        Text(FastFormatters.formatModificationDate(Date(timeIntervalSince1970: device.pairedAt)))
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.pick("解绑", "Revoke")) { viewModel.revokeLumaLinkDevice(id: device.id) }
                            .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
            }
            Divider().opacity(0.2)
            FlowWrapLayout(horizontalSpacing: 16, verticalSpacing: 6) {
                Toggle("断开连接自动还原分辨率与关闭黑屏", isOn: configBinding(\.autoRestoreDisplayOnDisconnect))
                Toggle("隐私黑屏时静音 Mac 扬声器", isOn: configBinding(\.muteMacWhenCurtainEnabled))
                Toggle("RDP 远控时 Mac 本地同步出声", isOn: configBinding(\.rdpLocalAudioEnabled))
            }
            .font(.caption)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func configBinding<T>(_ keyPath: WritableKeyPath<LumaLinkConfig, T>) -> Binding<T> {
        Binding(
            get: { viewModel.lumaLinkConfig[keyPath: keyPath] },
            set: { val in var next = viewModel.lumaLinkConfig; next[keyPath: keyPath] = val; viewModel.applyLumaLinkConfig(next) }
        )
    }
}
