import AppKit
import LumakeyCore
import SwiftUI

struct PluginDedicatedSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var state = PluginDedicatedSettingsState()
    @StateObject private var ctrl = PluginCenterController()

    private var activePlugin: PluginDescriptor? {
        if let targetID = viewModel.activePluginSettingsID,
           let matched = viewModel.plugins.first(where: { $0.id == targetID }) {
            return matched
        }
        return viewModel.plugins.first(where: { !$0.isBuiltin }) ?? viewModel.plugins.first
    }

    var body: some View {
        if let plugin = activePlugin {
            if plugin.id == LumaLinkServer.companionPluginID {
                LumaLinkDedicatedConsoleView(
                    plugin: plugin, state: state, ctrl: ctrl, viewModel: viewModel,
                    customizationCard: { customizationCard(for: plugin) }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        heroHeader(for: plugin)
                        if let banner = state.bannerMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles").foregroundStyle(LiquidColors.accentPrimary)
                                Text(banner).font(.caption).foregroundStyle(LiquidColors.textPrimary)
                                Spacer()
                                Button { state.bannerMessage = nil } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(LiquidColors.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .liquidGlassCard(cornerRadius: LiquidRadii.row, solidReadable: true)
                        }
                        if let fields = plugin.manifest.config, !fields.isEmpty {
                            PluginConfigFormCard(plugin: plugin, fields: fields, ctrl: ctrl, viewModel: viewModel)
                        }
                        PluginCommandSettingsCard(plugin: plugin, viewModel: viewModel, settingsState: state)
                        customizationCard(for: plugin)
                        if !plugin.isBuiltin {
                            PluginPermissionsAndSandboxSection(plugin: plugin, ctrl: ctrl, viewModel: viewModel)
                            PluginDedicatedDataAndContextCard(plugin: plugin, state: state, ctrl: ctrl, viewModel: viewModel)
                            PluginDeveloperDiagnosticsSection(plugin: plugin, state: state, ctrl: ctrl, viewModel: viewModel)
                        }
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 8)
                }
                .onAppear { state.bindIfNeeded(plugin: plugin, ctrl: ctrl) }
                .onChange(of: plugin.id) { _, _ in state.bindIfNeeded(plugin: plugin, ctrl: ctrl) }
                .onDisappear { state.stopRecordingHotKey() }
            }
        } else {
            ContentUnavailableView(
                L10n.pick("未找到已安装插件", "No Plugins Found"),
                systemImage: "puzzlepiece.extension",
                description: Text(L10n.pick("请前往「插件管理与 MCP」安装精选插件或导入扩展目录。", "Install a curated plugin or import an extension folder in Plugin Center."))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func heroHeader(for plugin: PluginDescriptor) -> some View {
        let missingSecrets = state.dataStatus?.missingRequiredSecretKeys ?? []
        let tint = PluginVisualPalette.tint(from: plugin.manifest.accentColor, fallback: plugin.isBuiltin ? .mint : LiquidColors.accentPrimary)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PluginIconBadge(plugin: plugin, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plugin.displayName).font(.title3.weight(.bold)).lineLimit(1)
                        Text("v\(plugin.manifest.version)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(LiquidColors.textSecondary)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LiquidColors.pillSurface, in: Capsule())
                        Text(plugin.displayCategoryBadge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    Text(plugin.effectiveStatusSummary)
                        .font(.caption).foregroundStyle(LiquidColors.textSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { ctrl.setEnabled(plugin, isEnabled: $0, viewModel: viewModel) }
                ))
                .toggleStyle(.switch).labelsHidden()
            }

            if !missingSecrets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "key.slash.fill").foregroundStyle(.orange)
                    Text(L10n.pick(
                        "待填写必填密钥：\(missingSecrets.joined(separator: ", "))",
                        "Missing required secret: \(missingSecrets.joined(separator: ", "))"
                    ))
                    .font(.caption2.weight(.medium)).foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
            }

            HStack(spacing: 8) {
                FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    Button(L10n.pick("在快捷台打开 ↩", "Open in Launcher ↩")) { viewModel.enterPluginScopedOverlay(plugin) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                        .disabled(!plugin.isEnabled || !plugin.isValid)
                    Button(L10n.pick("插件市场 →", "Plugin Store →")) {
                        viewModel.activePluginSettingsID = nil
                        viewModel.activeSettingsSection = .plugins
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    if !plugin.isBuiltin {
                        Button(L10n.pick("访达目录", "Show in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([plugin.directoryURL])
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        Button(L10n.pick("导出插件包", "Export Plugin")) {
                            ctrl.exportToFinder(plugin)
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        Button(L10n.pick("卸载插件", "Uninstall")) {
                            ctrl.remove(plugin, viewModel: viewModel)
                            viewModel.activePluginSettingsID = nil
                            viewModel.activeSettingsSection = .plugins
                        }
                        .buttonStyle(GlassPillButtonStyle())
                    }
                    if plugin.overrides.hasCustomizations {
                        Button(L10n.pick("重置个性化项", "Reset Customizations")) { state.resetAllOverrides(for: plugin, viewModel: viewModel) }
                            .buttonStyle(GlassPillButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func customizationCard(for plugin: PluginDescriptor) -> some View {
        let boostPresets: [(label: String, val: Int)] = [
            (L10n.pick("降权", "Low"), -100),
            (L10n.pick("默认", "Normal"), 0),
            (L10n.pick("优先", "High"), 100),
            (L10n.pick("置顶", "Top"), 250)
        ]
        let draftTrimmed = state.keywordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(L10n.pick("触发词、快捷键与展示位置", "Triggers, Hotkeys & Visibility"), systemImage: "wand.and.stars")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(L10n.pick("已调用 \(plugin.overrides.launchCount) 次", "\(plugin.overrides.launchCount) runs"))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(L10n.pick("触发关键词与自定义别名（升级插件不丢失）", "Trigger Keywords & Aliases"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if plugin.overrides.customKeywords != nil {
                        Button(L10n.pick("恢复默认触发词", "Restore Defaults")) {
                            state.restoreDefaultKeywords(for: plugin, viewModel: viewModel)
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                }

                if !plugin.effectiveKeywords.isEmpty {
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(plugin.effectiveKeywords, id: \.self) { kw in
                            HStack(spacing: 4) {
                                Text(kw)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(LiquidColors.accentPrimary)
                                    .lineLimit(1)
                                Button { state.removeKeyword(kw, for: plugin, viewModel: viewModel) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(LiquidColors.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10).padding(.vertical, 4.5)
                            .background(LiquidColors.pillSurface, in: Capsule())
                            .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.75) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    GlassInputField(
                        symbol: "plus.circle",
                        placeholder: L10n.pick("添加顺手触发别名（回车添加）", "Add trigger alias & press Return"),
                        text: $state.keywordDraft
                    )
                    .frame(minWidth: 220, maxWidth: 340)
                    .onSubmit { state.addKeyword(for: plugin, viewModel: viewModel) }
                    Button(L10n.pick("添加", "Add")) { state.addKeyword(for: plugin, viewModel: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: !draftTrimmed.isEmpty, compact: true))
                        .disabled(draftTrimmed.isEmpty)
                    Spacer(minLength: 0)
                }
            }

            if !plugin.isBuiltin {
                hotKeyRow(for: plugin)
            }

            Divider().opacity(0.22)

            FlowWrapLayout(horizontalSpacing: 18, verticalSpacing: 8) {
                Toggle(L10n.pick("主入口快捷按钮", "Pin to Quick Buttons"), isOn: Binding(
                    get: { plugin.pinnedInOverlay },
                    set: { val in state.mutateOverrides(for: plugin, viewModel: viewModel) { $0.pinnedInOverlay = val } }
                ))
                .fixedSize(horizontal: true, vertical: false)

                Toggle(L10n.pick("主入口混入全局搜索", "Main Entry in Global Search"), isOn: Binding(
                    get: { plugin.includeInGlobalSearch },
                    set: { val in state.mutateOverrides(for: plugin, viewModel: viewModel) { $0.includeInGlobalSearchOverride = val } }
                ))
                .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)

            HStack(spacing: 8) {
                Text(L10n.pick("搜索排序权重：", "Search Priority:")).font(.caption2.weight(.semibold)).foregroundStyle(LiquidColors.textSecondary)
                ForEach(boostPresets, id: \.val) { item in
                    Button(item.label) {
                        state.mutateOverrides(for: plugin, viewModel: viewModel) { $0.priorityBoost = item.val }
                    }
                    .buttonStyle(GlassPillButtonStyle(prominent: plugin.overrides.priorityBoost == item.val, compact: true))
                }
                Spacer()
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento, solidReadable: true)
    }

    private func hotKeyRow(for plugin: PluginDescriptor) -> some View {
        let recordingMain = state.isRecordingHotKey && state.recordingCommandID == nil
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.pick("插件主入口全局快捷键", "Plugin Global Hotkey")).font(.caption.weight(.medium))
                Text(L10n.pick("捕获前台选中文本后直达该插件 · 按 ⌫ 解除绑定", "Captures selected text and opens plugin · ⌫ to clear"))
                    .font(.caption2).foregroundStyle(LiquidColors.textSecondary)
            }
            Spacer()
            if plugin.overrides.customHotKey != nil {
                Button(L10n.pick("恢复默认", "Default")) { state.restoreDefaultHotKey(for: plugin, viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            if plugin.effectiveHotKey != nil {
                Button(L10n.pick("清空", "Clear")) { state.clearHotKey(for: plugin, viewModel: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            Button { state.toggleHotKeyRecording(for: plugin, viewModel: viewModel) } label: {
                Text(recordingMain ? L10n.pick("按下组合键…", "Press shortcut…") : (plugin.effectiveHotKey ?? L10n.pick("点击录制热键", "Record Hotkey")))
                    .font(.system(size: 12, weight: .bold, design: recordingMain ? .rounded : .monospaced))
                    .foregroundStyle(recordingMain ? .white : LiquidColors.textPrimary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(recordingMain ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(LiquidColors.pillSurface), in: Capsule())
                    .overlay { Capsule().strokeBorder(LiquidColors.pillBorder, lineWidth: 0.9) }
            }
            .buttonStyle(.plain)
        }
    }
}
