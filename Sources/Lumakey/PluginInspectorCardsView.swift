import AppKit
import LumakeyCore
import SwiftUI

struct PluginBuiltinInspectorCard: View {
    let plugin: PluginDescriptor
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let meta = plugin.builtinMetadata
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SquircleBadge(symbol: plugin.manifest.icon ?? "sparkles", topColor: .cyan, bottomColor: .indigo, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plugin.manifest.name).font(.callout.weight(.bold)).lineLimit(1)
                        Text("BUILTIN")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.mint)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                    Text(meta?.statusSummary ?? plugin.manifest.description)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { ctrl.setEnabled(plugin, isEnabled: $0, viewModel: viewModel) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if let tcc = meta?.requiredTCCPermissions, !tcc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("复用 Lumakey 宿主权限（免重复授权与重签名）")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                        ForEach(tcc, id: \.self) { perm in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill").font(.system(size: 10)).foregroundStyle(.mint)
                                Text(perm).font(.caption2).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LiquidColors.pillSurface, in: Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Button("打开完整原生设置 →") { viewModel.openBuiltinPluginSettings(plugin) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true))
                Button(ctrl.showEmbeddedBuiltinSettings ? "收起内嵌视图" : "内嵌设置视图") {
                    ctrl.showEmbeddedBuiltinSettings.toggle()
                }
                .buttonStyle(GlassPillButtonStyle())
            }

            if ctrl.showEmbeddedBuiltinSettings {
                Divider().opacity(0.25)
                embeddedNativeView
                    .frame(maxHeight: 360)
            }
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    @ViewBuilder
    private var embeddedNativeView: some View {
        switch BuiltinPluginID(rawValue: plugin.id) {
        case .mos:
            MosPluginSettingsView(viewModel: viewModel)
        case .lumaLink:
            LumaLinkSettingsView(viewModel: viewModel)
        case .systemPulse:
            TelemetrySettingsView()
        case nil:
            EmptyView()
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
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}

struct PluginSandboxPermissionCard: View {
    let hasDeclaredField: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hasDeclaredField ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(hasDeclaredField ? .mint : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasDeclaredField ? "注册权限声明：capabilities: []（纯沙盒）" : "未声明 capabilities 权限字段")
                    .font(.caption.weight(.semibold))
                Text(hasDeclaredField
                     ? "该插件明确声明不需要宿主 TCC 或 Host Bridge 能力，仅读取 stdin 传入数据。"
                     : "Plugin v3 要求每个插件在 plugin.json 中显式声明 capabilities（无需求请填 []）。")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}
