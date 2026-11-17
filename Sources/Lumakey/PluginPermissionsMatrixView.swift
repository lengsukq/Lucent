import AppKit
import LumakeyCore
import SwiftUI

struct PluginPermissionsMatrixView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var ctrl: PluginCenterController

    private var entries: [AppPermissionAuditEntry] {
        let all = PluginPermissionAudit.buildAudit(plugins: viewModel.plugins)
        return ctrl.showUnusedPermissions ? all : all.filter { $0.declaredPluginCount > 0 }
    }

    private var sandboxPlugins: [PluginDescriptor] {
        PluginPermissionAudit.sandboxOnlyPlugins(in: viewModel.plugins)
    }

    var body: some View {
        let activePermissionCount = PluginPermissionAudit.buildAudit(plugins: viewModel.plugins)
            .filter { $0.declaredPluginCount > 0 }.count
        VStack(alignment: .leading, spacing: 8) {
            summaryHeader(activeCount: activePermissionCount)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        permissionCard(entry)
                    }
                    if !sandboxPlugins.isEmpty {
                        sandboxSummaryCard
                    }
                }
                .padding(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func summaryHeader(activeCount: Int) -> some View {
        HStack(spacing: 6) {
            Label("App 权限全景清单 (\(activeCount)/\(LumakeyPermission.allCases.count) 项在用)", systemImage: "checklist.checked")
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(ctrl.showUnusedPermissions ? "仅看已声明" : "显示全部") {
                ctrl.showUnusedPermissions.toggle()
            }
            .buttonStyle(GlassPillButtonStyle(prominent: ctrl.showUnusedPermissions))
        }
    }

    private func permissionCard(_ entry: AppPermissionAuditEntry) -> some View {
        let perm = entry.permission
        let catColor: Color = switch perm.category {
        case .systemTCC: .orange
        case .systemKernel: .mint
        case .hostBridge: .cyan
        case .resourceScope: .purple
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: perm.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(catColor)
                    .frame(width: 24, height: 24)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(perm.title).font(.caption.weight(.bold)).lineLimit(1)
                        Text(perm.category.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(catColor)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(LiquidColors.pillSurface, in: Capsule())
                        if perm.category == .systemTCC, let tcc = perm.tccKind {
                            let ok = PluginHostTCCBroker.status(for: tcc).isGranted
                            Text(ok ? L10n.pick("宿主已获授权", "Granted") : L10n.pick("待代申", "Pending"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ok ? .green : .orange)
                        }
                    }
                    Text(perm.summary)
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if perm.category == .systemTCC, let tcc = perm.tccKind, !PluginHostTCCBroker.status(for: tcc).isGranted {
                    Button(L10n.pick("宿主代申", "Request TCC")) {
                        _ = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(tcc, allowSystemPrompt: true)
                        viewModel.refreshMosStatus()
                        viewModel.reloadPlugins()
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }
                if let urlStr = perm.systemPreferencesURL, let url = URL(string: urlStr) {
                    Button(L10n.pick("系统设置", "System Settings")) { NSWorkspace.shared.open(url) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }

            if entry.plugins.isEmpty {
                Text("当前无已安装插件声明此权限")
                    .font(.caption2)
                    .foregroundStyle(LiquidColors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.plugins) { usage in
                        usageRow(usage)
                    }
                }
            }
        }
        .padding(9)
        .background(LiquidColors.pillSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(entry.declaredPluginCount > 0 ? catColor.opacity(0.28) : LiquidColors.pillBorder, lineWidth: 0.7)
        }
    }

    private func usageRow(_ usage: PluginPermissionUsage) -> some View {
        let dotColor: Color = !usage.isPluginEnabled ? .gray : (usage.isAuthorized ? .green : .orange)
        return Button {
            viewModel.openPluginSettings(id: usage.pluginID)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(usage.pluginName).font(.caption2.weight(.semibold)).lineLimit(1)
                Text(usage.kind == .builtin ? "BUILTIN" : "EXT")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(usage.kind == .builtin ? .mint : .cyan)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(LiquidColors.pillSurface, in: Capsule())
                Spacer(minLength: 4)
                Text(usage.roleNote)
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(LiquidColors.pillSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sandboxSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("零特权纯沙盒插件 (\(sandboxPlugins.count) 个 · capabilities: [] 且 resourceScopes: [])", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 5)], spacing: 5) {
                ForEach(sandboxPlugins) { plugin in
                    Button {
                        viewModel.openPluginSettings(id: plugin.id)
                    } label: {
                        Text(plugin.manifest.name)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LiquidColors.pillSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(9)
        .background(LiquidColors.pillSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
    }
}
