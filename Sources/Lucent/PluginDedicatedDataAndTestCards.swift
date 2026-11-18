import AppKit
import LucentCore
import SwiftUI

struct PluginDedicatedDataAndContextCard: View {
    let plugin: PluginDescriptor
    @ObservedObject var state: PluginDedicatedSettingsState
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let ds = state.dataStatus
        let idxCount = ds?.searchIndexEntryCount ?? 0
        let updatedStr = (ds?.searchIndexUpdatedAt).map { FastFormatters.formatModificationDate($0) }
            ?? L10n.pick("尚未生成索引", "No index yet")
        let hasIndexOrSync = idxCount > 0 || (plugin.manifest.refreshIntervalSeconds ?? 0) > 0
            || !plugin.declaredContextKinds.isEmpty
            || plugin.manifest.searchIndexInGlobalSearch != nil
            || plugin.overrides.searchIndexGlobalOverride != nil

        if hasIndexOrSync {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        L10n.pick("跨模块联动与免前缀检索索引", "Context Hooks & Instant Search Index"),
                        systemImage: "sparkles.rectangle.stack"
                    )
                    .font(.callout.weight(.semibold))
                    Spacer()
                    Toggle(L10n.pick("索引混入全局搜索", "Index in Global Search"), isOn: Binding(
                        get: { plugin.searchIndexInGlobalSearch },
                        set: { val in
                            state.mutateOverrides(for: plugin, viewModel: viewModel) {
                                $0.searchIndexGlobalOverride = val
                            }
                        }
                    ))
                    .font(.caption2)
                    .fixedSize(horizontal: true, vertical: false)

                    if let refreshSec = plugin.manifest.refreshIntervalSeconds, refreshSec > 0 {
                        Text(L10n.pick("按需同步：\(refreshSec)s", "On-demand sync: \(refreshSec)s"))
                            .font(.caption2.monospacedDigit()).foregroundStyle(LiquidColors.accentPrimary)
                    }
                    if state.syncNeedsPluginGrant {
                        Button(L10n.pick("一键授权并同步", "Grant & Sync")) {
                            state.grantPermissionsAndSyncNow(for: plugin, ctrl: ctrl, viewModel: viewModel)
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                    } else if let permURL = state.syncPermissionActionURL {
                        Button(L10n.pick("前往授权…", "Open Privacy Settings…")) {
                            NSWorkspace.shared.open(permURL)
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                    }
                    Button {
                        state.syncSearchIndexNow(for: plugin, ctrl: ctrl, viewModel: viewModel)
                    } label: {
                        HStack(spacing: 5) {
                            if state.isSyncingIndex {
                                ProgressView().controlSize(.small)
                            }
                            Text(state.isSyncingIndex ? L10n.pick("同步中…", "Syncing…") : L10n.pick("立即同步", "Sync Now"))
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                    .disabled(state.isSyncingIndex)
                }

                if !plugin.declaredContextKinds.isEmpty {
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        Text(L10n.pick("自动挂载场景：", "Mounted in:"))
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.textSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                        ForEach(plugin.declaredContextKinds) { kind in
                            Label(kind.title, systemImage: kind.symbolName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.mint)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.mint.opacity(0.13), in: Capsule())
                        }
                    }
                }

                HStack(spacing: 10) {
                    miniStat(L10n.pick("免前缀索引词条", "Indexed Items"), "\(idxCount)", updatedStr)
                    miniStat(
                        L10n.pick("最近运行状态", "Latest Status"),
                        ds?.runtimeStatus?.badge ?? plugin.displayCategoryBadge,
                        ds?.runtimeStatus?.summary ?? L10n.pick("按需运行 · 零常驻进程", "On-demand · Zero background daemon")
                    )
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
        }
    }

    private func miniStat(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            Text(value).font(.callout.weight(.bold).monospacedDigit()).lineLimit(1)
            Text(sub).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
    }
}

struct PluginDeveloperDiagnosticsSection: View {
    let plugin: PluginDescriptor
    @ObservedObject var state: PluginDedicatedSettingsState
    @ObservedObject var ctrl: PluginCenterController
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let ds = state.dataStatus
        let bytesStr = FastFormatters.formatFileBytes(ds?.cacheBytes ?? 0)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(LiquidMotion.pressSpring) { state.showDeveloperDiagnostics.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.showDeveloperDiagnostics ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .frame(width: 12)
                    Label(
                        L10n.pick("开发者诊断、缓存治理与实时运行预览", "Developer Diagnostics, Cache & Live Runner"),
                        systemImage: "wrench.and.screwdriver"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    Spacer()
                    Text(L10n.pick("缓存 \(bytesStr)", "Cache \(bytesStr)"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(LiquidColors.textSecondary)
                    if ctrl.isRunning { ProgressView().controlSize(.small) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if state.showDeveloperDiagnostics {
                Divider().opacity(0.22)

                FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    Button(L10n.pick("访达定位插件包", "Reveal Bundle")) {
                        NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    if let dir = ds?.dataDirectoryURL, ds?.dataDirectoryExists == true {
                        Button(L10n.pick("打开数据目录", "Open Data Folder")) { NSWorkspace.shared.open(dir) }
                            .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                    Button(L10n.pick("清理缓存（保留索引）", "Clear Cache")) {
                        state.clearCache(for: plugin, preserveIndex: true, viewModel: viewModel)
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                    Button(L10n.pick("清空全部数据与索引", "Reset All Data")) {
                        state.clearCache(for: plugin, preserveIndex: false, viewModel: viewModel)
                    }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                }

                HStack(spacing: 6) {
                    GlassInputField(
                        symbol: "play.circle",
                        placeholder: L10n.pick("输入测试参数 query（回车运行预览）", "Enter test query & press Return"),
                        text: $ctrl.testQuery
                    )
                    .onSubmit { ctrl.runAsync(plugin, viewModel: viewModel) }
                    Button(L10n.pick("运行测试 ↩", "Run ↩")) { ctrl.runAsync(plugin, viewModel: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }

                if let out = ctrl.latestOutput, out.pluginID == plugin.id, let viewPayload = out.viewPayload {
                    PluginStructuredViewCard(
                        payload: viewPayload,
                        bundleDirectory: plugin.directoryURL,
                        dataDirectory: ds?.dataDirectoryURL,
                        onCopyText: { val in
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(val, forType: .string)
                            viewModel.serviceMessage = "已复制：\(val)"
                        },
                        onOpenURL: { url in viewModel.handlePluginOpenURL(url) },
                        onRunCommandArgs: { args in ctrl.runAsync(plugin, arguments: args, viewModel: viewModel) }
                    )
                } else if let out = ctrl.latestOutput, out.pluginID == plugin.id, !out.plainText.isEmpty {
                    Text(out.plainText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                }
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }
}
