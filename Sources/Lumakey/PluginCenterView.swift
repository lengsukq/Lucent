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
            rightWorkbench
                .frame(width: 364)
        }
        .onAppear { ctrl.startWatching(syncing: viewModel) }
        .onDisappear { ctrl.stopWatching() }
    }

    private var installedPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("插件 (\(builtinPlugins.count) 内置 · \(externalPlugins.count) 扩展)")
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 4) {
                    Circle().fill(ctrl.isWatcherOnline ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(ctrl.isWatcherOnline ? "热重载" : "离线")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(LiquidColors.pillSurface, in: Capsule())
                .help(ctrl.statusNote)
                Spacer(minLength: 4)
                Button("导入") { ctrl.importFromFinder(viewModel: viewModel) }.buttonStyle(GlassPillButtonStyle())
                Button("目录") { ctrl.openPluginsDirectoryInFinder() }.buttonStyle(GlassPillButtonStyle())
                Button("刷新") { viewModel.reloadAppsAndPlugins(); ctrl.syncSelection(from: viewModel.plugins) }
                    .buttonStyle(GlassPillButtonStyle())
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
        let symbol = plugin.manifest.icon ?? (plugin.manifest.mode == .view ? "rectangle.3.group.bubble.fill" : "terminal.fill")
        let badgeText = plugin.isBuiltin ? "BUILTIN" : plugin.manifest.mode.rawValue.uppercased()
        let badgeColor: Color = plugin.isBuiltin ? .mint : (plugin.manifest.mode == .view ? .cyan : .purple)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                SquircleBadge(
                    symbol: symbol,
                    topColor: plugin.isBuiltin ? .cyan : (plugin.manifest.mode == .view ? .cyan : .purple),
                    bottomColor: plugin.isBuiltin ? .blue : (plugin.manifest.mode == .view ? .blue : .indigo),
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(plugin.manifest.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(badgeText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeColor)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                        if !plugin.declaredCapabilities.isEmpty {
                            let grantedCount = plugin.declaredCapabilities.filter { plugin.isCapabilityGranted($0) }.count
                            Text("\(grantedCount)/\(plugin.declaredCapabilities.count) 权限")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(grantedCount == plugin.declaredCapabilities.count ? .cyan : .orange)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(LiquidColors.pillSurface, in: Capsule())
                        } else if !plugin.isBuiltin && plugin.manifest.capabilities != nil {
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
                    if let meta = plugin.builtinMetadata {
                        Text(meta.statusSummary).font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    } else {
                        Text("ID: \(plugin.id) · 触发词: \(plugin.manifest.keywords.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                    }
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

            HStack(spacing: 6) {
                Button(plugin.isBuiltin ? "详情与权限" : "配置与预览") { ctrl.select(plugin, switchTab: true) }
                    .buttonStyle(GlassPillButtonStyle(prominent: isSelected))
                if plugin.isBuiltin {
                    Button("原生设置") { viewModel.openBuiltinPluginSettings(plugin) }
                        .buttonStyle(GlassPillButtonStyle())
                    Spacer()
                } else {
                    Button("访达") { NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL]) }.buttonStyle(GlassPillButtonStyle())
                    Button("导出") { ctrl.exportToFinder(plugin) }.buttonStyle(GlassPillButtonStyle())
                    Spacer()
                    Button("删除") { ctrl.remove(plugin, viewModel: viewModel) }.buttonStyle(GlassPillButtonStyle())
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

    private var rightWorkbench: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(PluginCenterTab.allCases) { tab in
                    Button(tab.rawValue) { ctrl.activeTab = tab }
                        .buttonStyle(GlassPillButtonStyle(prominent: ctrl.activeTab == tab))
                }
                Spacer(minLength: 0)
            }
            switch ctrl.activeTab {
            case .gallery:
                PluginStarterGalleryListView(installedIDs: Set(viewModel.plugins.map(\.id))) { tpl in
                    ctrl.installStarter(tpl, viewModel: viewModel)
                }
            case .inspector:
                inspectorTab
            case .permissions:
                PluginPermissionsMatrixView(viewModel: viewModel, ctrl: ctrl)
            case .scaffold:
                scaffoldTab
            }
        }
    }

    @ViewBuilder
    private var inspectorTab: some View {
        if let plugin = selectedPlugin {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if plugin.isBuiltin {
                        PluginBuiltinInspectorCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
                    } else if !plugin.declaredCapabilities.isEmpty {
                        PluginCapabilitiesCard(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
                    } else {
                        PluginSandboxPermissionCard(hasDeclaredField: plugin.manifest.capabilities != nil)
                    }
                    if let fields = plugin.manifest.config, !fields.isEmpty {
                        PluginConfigFormCard(plugin: plugin, fields: fields, ctrl: ctrl, viewModel: viewModel)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("实时运行测试 · \(plugin.manifest.name)").font(.caption.weight(.bold))
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
                            onCopyText: { val in
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(val, forType: .string)
                                viewModel.serviceMessage = "已复制：\(val)"
                            },
                            onOpenURL: { url in viewModel.handlePluginOpenURL(url) },
                            onRunCommandArgs: { args in ctrl.runAsync(plugin, arguments: args, viewModel: viewModel) }
                        )
                    } else {
                        let rawText = (ctrl.latestOutput?.pluginID == plugin.id ? ctrl.latestOutput?.plainText : nil) ?? viewModel.pluginOutputText
                        Text(rawText.isEmpty ? "点击上方「运行」查看声明式 view 卡片或脚本输出。" : rawText)
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

    private var scaffoldTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("脚手架创建自定义插件 (v3)").font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text("插件唯一 ID").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                GlassInputField(symbol: "number", placeholder: "小写字母 / 数字 / 连字符", text: $ctrl.newID)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("插件显示名称").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                GlassInputField(symbol: "tag", placeholder: "显示名称", text: $ctrl.newName)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("触发关键词（逗号分隔）").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                GlassInputField(symbol: "text.magnifyingglass", placeholder: "触发关键词", text: $ctrl.newKeywords)
            }
            HStack(spacing: 8) {
                Text("输出协议:").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                ForEach(PluginMode.allCases, id: \.rawValue) { mode in
                    Button(mode.rawValue.uppercased()) { ctrl.newMode = mode }
                        .buttonStyle(GlassPillButtonStyle(prominent: ctrl.newMode == mode))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("注册声明权限（必选字段，不选即声明 [] 纯沙盒）").font(.caption2.weight(.medium)).foregroundStyle(LiquidColors.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
                    ForEach(PluginCapability.allCases) { cap in
                        let selected = ctrl.newCapabilities.contains(cap)
                        Button(cap.title) {
                            if selected { ctrl.newCapabilities.remove(cap) } else { ctrl.newCapabilities.insert(cap) }
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: selected))
                    }
                }
            }
            Button("生成并运行测试") { ctrl.scaffoldCustom(viewModel: viewModel) }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            Text("也可将 lumakey-mcp 接入 AI 客户端，读取 lumakey://specs/plugin-v3 自动生成。")
                .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }
}
