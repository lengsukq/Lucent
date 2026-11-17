import AppKit
import LumakeyCore
import SwiftUI

struct PluginSetupReminderAndGuideSection: View {
    let plugin: PluginDescriptor
    @ObservedObject var state: PluginDedicatedSettingsState
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    private var readiness: PluginSetupReadiness {
        PluginSetupReadiness.analyze(
            plugin: plugin,
            dataStatus: state.dataStatus,
            selectionQuickBarEnabled: viewModel.generalPreferences.enableSelectionQuickBar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plugin.isEnabled || readiness.hasBlockingIssues || !readiness.disabledScopes.isEmpty {
                readinessBanner
            }
            if !readiness.usageTips.isEmpty {
                usageGuideCard
            }
        }
    }

    private var readinessBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(L10n.pick("使用前请先完成以下准备", "Setup Needed Before Use"))
                    .font(.callout.weight(.semibold))
                Spacer()
                if !plugin.isEnabled {
                    Button(L10n.pick("启用插件", "Enable")) {
                        ctrl.setEnabled(plugin, isEnabled: true, viewModel: viewModel)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                } else if !readiness.ungrantedCapabilities.isEmpty {
                    Button(L10n.pick("一键开启所需权限", "Grant Required Permissions")) {
                        for cap in readiness.ungrantedCapabilities {
                            try? viewModel.setPluginCapabilityGranted(plugin, capability: cap, granted: true)
                        }
                        state.bannerMessage = L10n.pick("已开启「\(plugin.displayName)」所需插件权限", "Granted permissions for \(plugin.displayName)")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                if !plugin.isEnabled {
                    reminderRow(
                        icon: "power",
                        text: L10n.pick("插件当前处于停用状态，开启右上角开关后才能唤起或运行。", "Plugin is currently disabled. Turn it on at top right to use it.")
                    )
                }
                if !readiness.missingRequiredSecrets.isEmpty {
                    reminderRow(
                        icon: "key.fill",
                        text: L10n.pick(
                            "请在下方「参数配置」填入必填密钥：\(readiness.missingRequiredSecrets.joined(separator: "、"))",
                            "Enter required key(s) below: \(readiness.missingRequiredSecrets.joined(separator: ", "))"
                        )
                    )
                }
                if !readiness.ungrantedCapabilities.isEmpty {
                    reminderRow(
                        icon: "lock.open.fill",
                        text: L10n.pick(
                            "尚未开启插件能力：\(readiness.ungrantedCapabilities.map(\.title).joined(separator: "、"))",
                            "Disabled capabilities: \(readiness.ungrantedCapabilities.map(\.title).joined(separator: ", "))"
                        )
                    )
                }
                if !readiness.disabledScopes.isEmpty {
                    reminderRow(
                        icon: "network.slash",
                        text: L10n.pick(
                            "以下外部访问已关闭（可能影响部分功能）：\(readiness.disabledScopes.map(\.title).joined(separator: "、"))",
                            "External access turned off: \(readiness.disabledScopes.map(\.title).joined(separator: ", "))"
                        )
                    )
                }
                ForEach(readiness.missingTCCPermissions, id: \.self) { tcc in
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(L10n.pick(
                            "需要在 macOS 系统设置中为 Lumakey 勾选「\(tcc.title)」",
                            "Enable '\(tcc.title)' for Lumakey in macOS System Settings"
                        ))
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textPrimary)
                        Spacer(minLength: 4)
                        Button(L10n.pick("去授权…", "Authorize…")) {
                            _ = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(tcc, allowSystemPrompt: true)
                            if let url = URL(string: tcc.systemSettingsURLString) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.bento, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.32), lineWidth: 0.8)
        }
    }

    private func reminderRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            Text(text)
                .font(.caption2)
                .foregroundStyle(LiquidColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usageGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.pick("怎么用 · 快速上手", "How to Use"), systemImage: "book.pages.fill")
                    .font(.callout.weight(.semibold))
                Spacer()
                if readiness.supportsSelection {
                    Toggle(
                        L10n.pick("鼠标划词悬浮按钮", "Selection Quick Bar"),
                        isOn: Binding(
                            get: { viewModel.generalPreferences.enableSelectionQuickBar },
                            set: { val in viewModel.updateGeneralPreferences { $0.enableSelectionQuickBar = val } }
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .tint(.purple)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(readiness.usageTips) { tip in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LiquidColors.accentPrimary)
                            .frame(width: 24, height: 24)
                            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(tip.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LiquidColors.textPrimary)
                            Text(tip.detail)
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }
}
