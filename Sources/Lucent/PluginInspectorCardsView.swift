import AppKit
import LucentCore
import SwiftUI

@MainActor
private final class PluginPermUIState: ObservableObject {
    @Published var showTechDetails: Bool = false
}

struct PluginPermissionsAndSandboxSection: View {
    let plugin: PluginDescriptor
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var ui = PluginPermUIState()

    private var declaredCaps: [PluginCapability] { plugin.declaredCapabilities }
    private var declaredScopes: [PluginResourceScope] { plugin.declaredResourceScopes }
    private var totalCount: Int { declaredCaps.count + declaredScopes.count }
    private var grantedCount: Int {
        declaredCaps.filter { plugin.isCapabilityGranted($0) }.count
            + declaredScopes.filter { plugin.isResourceScopeGranted($0) }.count
    }

    var body: some View {
        let fullyDeclared = plugin.manifest.capabilities != nil && plugin.manifest.resourceScopes != nil
        let pure = plugin.isPureSandbox && fullyDeclared

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(
                    L10n.pick("权限与安全控制", "Permissions & Safety"),
                    systemImage: pure ? "checkmark.shield.fill" : "lock.shield.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(pure ? .mint : LiquidColors.textPrimary)

                Text(
                    pure
                    ? L10n.pick("纯沙盒 · 零额外权限", "Pure Sandbox")
                    : L10n.pick("已开启 \(grantedCount)/\(totalCount)", "\(grantedCount)/\(totalCount) Enabled")
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pure ? .mint : .cyan)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(LiquidColors.pillSurface, in: Capsule())

                Spacer()

                if totalCount > 0 && grantedCount < totalCount {
                    Button(L10n.pick("开启全部所需权限", "Enable All")) {
                        for cap in declaredCaps {
                            try? viewModel.setPluginCapabilityGranted(plugin, capability: cap, granted: true)
                        }
                        for scope in declaredScopes {
                            try? viewModel.setPluginResourceScopeGranted(plugin, scope: scope, granted: true)
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }

                if totalCount > 0 {
                    Button(ui.showTechDetails ? L10n.pick("隐藏技术标识", "Hide IDs") : L10n.pick("技术标识", "Tech IDs")) {
                        withAnimation(LiquidMotion.pressSpring) { ui.showTechDetails.toggle() }
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            Text(
                pure
                ? L10n.pick("该插件不访问网络、外部文件或系统隐私能力，在独立沙盒内运行。", "This plugin runs in an isolated sandbox without network, file, or privacy access.")
                : (fullyDeclared
                    ? L10n.pick("插件只能使用你主动开启的能力；需要 macOS 系统授权的项目会由 Lucent 统一引导。", "Plugins can only use toggles you turn on. macOS privacy permissions are handled centrally by Lucent.")
                    : L10n.pick("插件 manifest 未完整声明 capabilities / resourceScopes，部分权限可能受限。", "Manifest is missing capabilities or resourceScopes declarations."))
            )
            .font(.caption2)
            .foregroundStyle(LiquidColors.textSecondary)

            if !declaredCaps.isEmpty {
                groupTitle(L10n.pick("功能权限（点击即用）", "Feature Permissions"))
                ForEach(declaredCaps) { cap in capabilityRow(cap) }
            }

            if !declaredScopes.isEmpty {
                groupTitle(L10n.pick("系统与外部访问", "Network, Files & CLI"))
                ForEach(declaredScopes) { scope in scopeRow(scope) }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(LiquidColors.textSecondary)
            .padding(.top, 2)
    }

    private func capabilityRow(_ cap: PluginCapability) -> some View {
        let granted = plugin.isCapabilityGranted(cap)
        let tccKind = PluginHostTCCBroker.requiredTCC(for: cap)
        let tccOK = tccKind.map { PluginHostTCCBroker.status(for: $0).isGranted } ?? true

        return permissionRowShell(
            symbol: cap.symbolName,
            tint: granted ? .cyan : LiquidColors.textSecondary,
            activeBorder: granted ? Color.cyan.opacity(0.35) : LiquidColors.pillBorder,
            title: cap.title,
            techID: ui.showTechDetails ? cap.rawValue : nil,
            summary: cap.summary,
            badgeText: tccKind != nil ? (tccOK ? L10n.pick("系统已允许", "System OK") : L10n.pick("需系统授权", "Needs System Auth")) : nil,
            badgeColor: tccOK ? .mint : .orange,
            actionButton: (!tccOK && tccKind != nil) ? (L10n.pick("去授权", "Authorize"), {
                guard let kind = tccKind else { return }
                _ = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(kind, allowSystemPrompt: true)
                if let url = URL(string: kind.systemSettingsURLString) { NSWorkspace.shared.open(url) }
            }) : nil,
            isOn: Binding(
                get: { granted },
                set: { ctrl.setCapabilityGranted(plugin, capability: cap, granted: $0, viewModel: viewModel) }
            )
        )
    }

    private func scopeRow(_ scope: PluginResourceScope) -> some View {
        let granted = plugin.isResourceScopeGranted(scope)
        return permissionRowShell(
            symbol: scope.symbolName,
            tint: granted ? .purple : LiquidColors.textSecondary,
            activeBorder: granted ? Color.purple.opacity(0.35) : Color.orange.opacity(0.45),
            title: scope.title,
            techID: ui.showTechDetails ? scope.rawValue : nil,
            summary: scope.summary,
            badgeText: granted ? nil : L10n.pick("已拦截", "Blocked"),
            badgeColor: .orange,
            actionButton: nil,
            isOn: Binding(
                get: { granted },
                set: { ctrl.setResourceScopeGranted(plugin, scope: scope, granted: $0, viewModel: viewModel) }
            )
        )
    }

    private func permissionRowShell(
        symbol: String, tint: Color, activeBorder: Color,
        title: String, techID: String?, summary: String,
        badgeText: String?, badgeColor: Color,
        actionButton: (String, () -> Void)?,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.caption.weight(.semibold))
                    if let techID {
                        Text(techID)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(LiquidColors.textSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(badgeColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let actionButton {
                Button(actionButton.0, action: actionButton.1)
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(activeBorder, lineWidth: 0.7)
        }
    }
}
