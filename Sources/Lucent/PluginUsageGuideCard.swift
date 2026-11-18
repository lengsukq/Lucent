import AppKit
import LucentCore
import SwiftUI

@MainActor
private final class PluginGuideUIState: ObservableObject {
    @Published var trustRefreshTick: Int = 0
}

struct PluginSetupReminderAndGuideSection: View {
    let plugin: PluginDescriptor
    @ObservedObject var state: PluginDedicatedSettingsState
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel
    var showUsageGuide: Bool = true
    @StateObject private var ui = PluginGuideUIState()

    private var readiness: PluginSetupReadiness {
        _ = ui.trustRefreshTick
        return PluginSetupReadiness.analyze(
            plugin: plugin,
            dataStatus: state.dataStatus,
            selectionQuickBarEnabled: viewModel.generalPreferences.enableSelectionQuickBar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !plugin.isBuiltin {
                PythonRuntimeAdvisorCard(viewModel: viewModel, targetPlugin: plugin)
            }
            if !plugin.isEnabled || readiness.hasBlockingIssues {
                readinessBanner
            }
            if showUsageGuide && !readiness.usageTips.isEmpty {
                usageGuideCard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            ui.trustRefreshTick += 1
        }
    }

    private var readinessBanner: some View {
        let missingPermCount = readiness.missingPermissionCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(
                    missingPermCount > 0
                    ? L10n.pick("待开启权限与配置（\(missingPermCount) 项）", "Setup & Permissions Needed (\(missingPermCount))")
                    : L10n.pick("使用前请先完成以下准备", "Setup Needed Before Use")
                )
                .font(.callout.weight(.semibold))
                Spacer()
                if !plugin.isEnabled {
                    Button(L10n.pick("启用插件", "Enable")) {
                        ctrl.setEnabled(plugin, isEnabled: true, viewModel: viewModel)
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: !readiness.hasMissingPermissions, compact: true))
                }
                if !readiness.ungrantedCapabilities.isEmpty || !readiness.disabledScopes.isEmpty {
                    Button(L10n.pick("一键开启全部插件权限", "Enable All Permissions")) {
                        for cap in readiness.ungrantedCapabilities {
                            try? viewModel.setPluginCapabilityGranted(plugin, capability: cap, granted: true)
                        }
                        for scope in readiness.disabledScopes {
                            try? viewModel.setPluginResourceScopeGranted(plugin, scope: scope, granted: true)
                        }
                        state.bannerMessage = L10n.pick("已开启「\(plugin.displayName)」全部所需权限", "Enabled all required permissions for \(plugin.displayName)")
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if !plugin.isEnabled {
                    reminderRow(
                        icon: "power",
                        text: L10n.pick("插件当前处于停用状态，点击右侧「启用插件」或右上角开关后才能运行。", "Plugin is currently disabled. Enable it to use commands.")
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
                ForEach(readiness.ungrantedCapabilities) { cap in
                    HStack(spacing: 8) {
                        Image(systemName: cap.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.pick("缺少功能权限：\(cap.title)", "Missing capability: \(cap.title)"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiquidColors.textPrimary)
                            Text(cap.summary)
                                .font(.system(size: 10.5))
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Toggle("", isOn: Binding(
                            get: { plugin.isCapabilityGranted(cap) },
                            set: { ctrl.setCapabilityGranted(plugin, capability: cap, granted: $0, viewModel: viewModel) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
                ForEach(readiness.disabledScopes) { scope in
                    HStack(spacing: 8) {
                        Image(systemName: scope.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.pick("缺少外部访问权限：\(scope.title)", "Blocked external access: \(scope.title)"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiquidColors.textPrimary)
                            Text(scope.summary)
                                .font(.system(size: 10.5))
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Toggle("", isOn: Binding(
                            get: { plugin.isResourceScopeGranted(scope) },
                            set: { ctrl.setResourceScopeGranted(plugin, scope: scope, granted: $0, viewModel: viewModel) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
                ForEach(readiness.missingTCCPermissions, id: \.self) { tcc in
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(L10n.pick(
                            "需要在 macOS 系统设置中为 Lucent 勾选「\(tcc.title)」",
                            "Enable '\(tcc.title)' for Lucent in macOS System Settings"
                        ))
                        .font(.caption2.weight(.medium))
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
                ForEach(readiness.systemPrivacyRequirements) { req in
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(L10n.pick("需要在系统设置中开启 \(req.title)", "Enable \(req.title) in macOS System Settings"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(LiquidColors.textPrimary)
                        Spacer(minLength: 4)
                        Button(L10n.pick("去授权…", "Authorize…")) {
                            if let url = URL(string: req.settingsURL) { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
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
