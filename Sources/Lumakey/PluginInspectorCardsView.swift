import AppKit
import LumakeyCore
import SwiftUI

struct PluginPermissionsAndSandboxSection: View {
    let plugin: PluginDescriptor
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !plugin.declaredCapabilities.isEmpty {
                PluginCapabilitiesCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
            }
            if !plugin.declaredResourceScopes.isEmpty || plugin.declaredCapabilities.isEmpty {
                PluginSandboxPermissionCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
            }
        }
    }
}

struct PluginCapabilitiesCard: View {
    let plugin: PluginDescriptor
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("宿主能力授权 (Host Bridge)", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.bold))
                Spacer()
                Text("默认最小权限")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(LiquidColors.pillSurface, in: Capsule())
            }
            Text("开启后，插件触发时仅通过本次执行有效的一过性 UDS Socket 复用宿主能力，执行结束即销毁监听。")
                .font(.caption2)
                .foregroundStyle(LiquidColors.textSecondary)

            ForEach(plugin.declaredCapabilities) { cap in
                let granted = plugin.isCapabilityGranted(cap)
                HStack(spacing: 9) {
                    Image(systemName: cap.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(granted ? .cyan : LiquidColors.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(cap.title).font(.caption.weight(.semibold))
                            Text(cap.rawValue)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(LiquidColors.textSecondary)
                        }
                        Text(cap.summary)
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Toggle("", isOn: Binding(
                        get: { granted },
                        set: { ctrl.setCapabilityGranted(plugin, capability: cap, granted: $0, viewModel: viewModel) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                        .strokeBorder(granted ? Color.cyan.opacity(0.38) : LiquidColors.pillBorder, lineWidth: 0.7)
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }
}

struct PluginSandboxPermissionCard: View {
    let plugin: PluginDescriptor
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let hasCaps = plugin.manifest.capabilities != nil
        let hasScopes = plugin.manifest.resourceScopes != nil
        let fullyDeclared = hasCaps && hasScopes
        let pure = plugin.isPureSandbox && fullyDeclared

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: pure ? "checkmark.shield.fill" : (fullyDeclared ? "network.badge.shield.half.filled" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(pure ? .mint : (fullyDeclared ? .purple : .orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        pure ? L10n.pick("系统级沙箱：零特权纯沙盒（capabilities: [] · resourceScopes: []）", "OS Sandbox: Pure Zero-Privilege Sandbox") :
                        (fullyDeclared ? L10n.pick("外部资源作用域管控 (macOS Seatbelt 沙箱)", "External Resource Scopes (macOS Seatbelt Sandbox)") : L10n.pick("未完整声明 capabilities / resourceScopes", "Missing capabilities / resourceScopes declaration"))
                    )
                    .font(.caption.weight(.semibold))
                    Text(
                        pure
                        ? L10n.pick("该插件已被 OS 沙箱封锁外网连接、用户主目录写操作与密钥库访问。", "Outbound IP, user home writes, and secret vault access are blocked by OS sandbox.")
                        : (fullyDeclared ? L10n.pick("可随时关闭下方作用域，由系统内核 Seatbelt 沙箱强制拦截对应网络、写盘或外部子进程。", "Toggle scopes below to block network, disk writes, or subprocesses at the OS kernel level.") : L10n.pick("Plugin v3.1 强校验要求在 plugin.json 显式声明 capabilities 与 resourceScopes。", "Plugin v3.1 requires explicit capabilities and resourceScopes in plugin.json."))
                    )
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if !plugin.declaredResourceScopes.isEmpty {
                ForEach(plugin.declaredResourceScopes) { scope in
                    let granted = plugin.isResourceScopeGranted(scope)
                    HStack(spacing: 9) {
                        Image(systemName: scope.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(granted ? .purple : LiquidColors.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(scope.title).font(.caption.weight(.semibold))
                                Text(scope.rawValue)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(LiquidColors.textSecondary)
                            }
                            Text(scope.summary)
                                .font(.caption2)
                                .foregroundStyle(LiquidColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Toggle("", isOn: Binding(
                            get: { granted },
                            set: { ctrl.setResourceScopeGranted(plugin, scope: scope, granted: $0, viewModel: viewModel) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                            .strokeBorder(granted ? Color.purple.opacity(0.38) : Color.orange.opacity(0.45), lineWidth: 0.7)
                    }
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }
}
