import AppKit
import LumakeyCore
import SwiftUI

struct PluginCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var ctrl = PluginCenterController()

    private var builtinPlugins: [PluginDescriptor] { viewModel.plugins.filter(\.isBuiltin) }
    private var externalPlugins: [PluginDescriptor] { viewModel.plugins.filter { !$0.isBuiltin } }

    private var selectedPlugin: PluginDescriptor? {
        guard let id = ctrl.selectedPluginID else { return viewModel.plugins.first }
        return viewModel.plugins.first { $0.id == id } ?? viewModel.plugins.first
    }

    var body: some View {
        HStack(spacing: 12) {
            installedPane
                .frame(minWidth: 0, maxWidth: .infinity)
            rightWorkbench
                .frame(width: 334)
        }
        .onAppear { ctrl.startWatching(syncing: viewModel) }
        .onDisappear { ctrl.stopWatching() }
    }

    private var installedPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("插件 (\(builtinPlugins.count) 内置 · \(externalPlugins.count) 扩展)")
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 4) {
                    Circle().fill(ctrl.isWatcherOnline ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(ctrl.isWatcherOnline ? "热重载" : "离线")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(LiquidColors.pillSurface, in: Capsule())
                .help(ctrl.statusNote)
                Spacer(minLength: 2)
                Button("导入") { ctrl.importFromFinder(viewModel: viewModel) }.buttonStyle(GlassPillButtonStyle(compact: true))
                Button("目录") { ctrl.openPluginsDirectoryInFinder() }.buttonStyle(GlassPillButtonStyle(compact: true))
                Button("刷新") { viewModel.reloadPluginsAndHotKeys(); ctrl.syncSelection(from: viewModel.plugins) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if !builtinPlugins.isEmpty {
                        groupHeader("内置原生插件 (BUILTIN · 复用宿主权限)", symbol: "shield.checkered")
                        ForEach(builtinPlugins) { plugin in pluginRow(plugin) }
                    }
                    groupHeader("外部扩展插件 (\(externalPlugins.count))", symbol: "puzzlepiece.extension")
                    if externalPlugins.isEmpty {
                        Text("暂无外部插件，可在右侧「精选市场」安装或用脚手架 / lumakey-mcp 生成。")
                            .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
                    } else {
                        ForEach(externalPlugins) { plugin in pluginRow(plugin) }
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }

    private func groupHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(LiquidColors.textSecondary)
            .padding(.top, 2)
    }

    private func pluginRow(_ plugin: PluginDescriptor) -> some View {
        let isSelected = selectedPlugin?.id == plugin.id
        let badgeColor = PluginVisualPalette.tint(from: plugin.manifest.accentColor, fallback: plugin.isBuiltin ? .mint : .cyan)
        let qbCount = plugin.overrides.quickButtonCommandIDs.count + (plugin.pinnedInOverlay ? 1 : 0)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                PluginIconBadge(plugin: plugin, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(plugin.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(plugin.displayCategoryBadge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(badgeColor.opacity(0.12), in: Capsule())
                        if let hk = plugin.effectiveHotKey, !hk.isEmpty {
                            Text(hk)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(LiquidColors.pillSurface, in: Capsule())
                        }
                        if qbCount > 0 {
                            Label("\(qbCount)", systemImage: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        permissionBadge(for: plugin)
                    }
                    Text(plugin.effectiveStatusSummary)
                        .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { ctrl.setEnabled(plugin, isEnabled: $0, viewModel: viewModel) }
                ))
                .toggleStyle(.switch).labelsHidden()
            }

            if !plugin.isValid {
                Text(plugin.validationIssues.joined(separator: "；")).font(.caption2).foregroundStyle(.red)
            }

            HStack(spacing: 5) {
                Button(plugin.isBuiltin ? "子功能与权限" : "配置与预览") { ctrl.select(plugin, switchTab: true) }
                    .buttonStyle(GlassPillButtonStyle(prominent: isSelected, compact: true))
                if plugin.isBuiltin {
                    Button("原生设置 →") { viewModel.openBuiltinPluginSettings(plugin) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    Spacer(minLength: 2)
                } else {
                    Button("独立设置 →") { viewModel.openPluginSettings(id: plugin.id) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL]) }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    Button("导出") { ctrl.exportToFinder(plugin) }.buttonStyle(GlassPillButtonStyle(compact: true))
                    Spacer(minLength: 2)
                    Button("删除") { ctrl.remove(plugin, viewModel: viewModel) }.buttonStyle(GlassPillButtonStyle(compact: true))
                }
            }
        }
        .padding(10)
        .background(isSelected ? LiquidColors.highlightGlow : LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                .strokeBorder(isSelected ? Color.cyan.opacity(0.45) : LiquidColors.pillBorder, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func permissionBadge(for plugin: PluginDescriptor) -> some View {
        if !plugin.declaredCapabilities.isEmpty {
            let grantedCount = plugin.declaredCapabilities.filter { plugin.isCapabilityGranted($0) }.count
            Text("\(grantedCount)/\(plugin.declaredCapabilities.count) 权限")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(grantedCount == plugin.declaredCapabilities.count ? .cyan : .orange)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(LiquidColors.pillSurface, in: Capsule())
        } else if !plugin.isBuiltin && !plugin.declaredResourceScopes.isEmpty {
            Text(plugin.declaredResourceScopes.map(\.shortLabel).joined(separator: " · "))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(LiquidColors.pillSurface, in: Capsule())
        } else if !plugin.isBuiltin && plugin.manifest.capabilities != nil && plugin.manifest.resourceScopes != nil {
            Text("纯沙盒 []")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(LiquidColors.textSecondary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(LiquidColors.pillSurface, in: Capsule())
        } else if plugin.isBuiltin {
            Text("\(plugin.declaredPermissions.count) 权限")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.mint)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6).padding(.vertical, 1.5)
                .background(LiquidColors.pillSurface, in: Capsule())
        }
    }

    private var rightWorkbench: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(PluginCenterTab.allCases) { tab in
                    Button(tab.rawValue) { ctrl.activeTab = tab }
                        .buttonStyle(GlassPillButtonStyle(prominent: ctrl.activeTab == tab, compact: true))
                }
                Spacer(minLength: 0)
            }
            switch ctrl.activeTab {
            case .gallery:
                PluginStoreMarketplaceView(viewModel: viewModel, centerCtrl: ctrl)
            case .inspector:
                inspectorTab
            case .permissions:
                PluginPermissionsMatrixView(viewModel: viewModel, ctrl: ctrl)
            case .scaffold:
                PluginScaffoldFormView(viewModel: viewModel, ctrl: ctrl)
            }
        }
    }

    @ViewBuilder
    private var inspectorTab: some View {
        if let plugin = selectedPlugin {
            let dataDir = plugin.isBuiltin ? nil : PluginDataPaths.dataDirectory(for: plugin.id, pluginsRoot: plugin.directoryURL.deletingLastPathComponent())
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if plugin.isBuiltin {
                        PluginBuiltinInspectorCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
                    } else if !plugin.declaredCapabilities.isEmpty {
                        PluginCapabilitiesCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
                    } else {
                        PluginSandboxPermissionCard(plugin: plugin)
                    }
                    PluginCommandSettingsCard(plugin: plugin, viewModel: viewModel)
                    if let fields = plugin.manifest.config, !fields.isEmpty {
                        PluginConfigFormCard(plugin: plugin, fields: fields, ctrl: ctrl, viewModel: viewModel)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("实时运行预览 · \(plugin.displayName)").font(.caption.weight(.bold))
                            Spacer()
                            if ctrl.isRunning { ProgressView().controlSize(.small) }
                        }
                        HStack(spacing: 6) {
                            GlassInputField(symbol: "play.circle", placeholder: "输入查询参数 query (可留空)", text: $ctrl.testQuery)
                            Button("运行 ↩") { ctrl.runAsync(plugin, viewModel: viewModel) }
                                .buttonStyle(GlassPillButtonStyle(prominent: true))
                        }
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)

                    if let out = ctrl.latestOutput, out.pluginID == plugin.id, let viewPayload = out.viewPayload {
                        PluginStructuredViewCard(
                            payload: viewPayload,
                            bundleDirectory: plugin.directoryURL,
                            dataDirectory: dataDir,
                            onCopyText: { val in
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(val, forType: .string)
                                viewModel.serviceMessage = "已复制：\(val)"
                            },
                            onOpenURL: { url in viewModel.handlePluginOpenURL(url) },
                            onRunCommandArgs: { args in ctrl.runAsync(plugin, arguments: args, viewModel: viewModel) }
                        )
                    } else {
                        let rawText = (ctrl.latestOutput?.pluginID == plugin.id ? ctrl.latestOutput?.plainText : nil) ?? viewModel.pluginOutputText
                        Text(rawText.isEmpty ? "点击上方「运行」查看声明式视图卡片或输出。" : rawText)
                            .font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled).padding(11).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
                    }
                }
                .padding(.top, 3).padding(.bottom, 4).padding(.horizontal, 2)
            }
        } else {
            ContentUnavailableView("未选择插件", systemImage: "slider.horizontal.3", description: Text("请先从左侧选择插件或在「精选市场」安装。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }
}
