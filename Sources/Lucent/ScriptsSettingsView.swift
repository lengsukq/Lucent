import AppKit
import LucentCore
import SwiftUI

struct ScriptsSettingsView: View {
    var viewModel: AppViewModel?
    @StateObject private var ctrl = ScriptsSettingsController()

    private let colorChoices = ["cyan", "blue", "indigo", "purple", "mint", "teal", "green", "orange", "pink", "slate"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeroHeader(
                symbol: "terminal.fill", topColor: .teal, bottomColor: .indigo,
                title: L10n.pick("脚本快捷库 (Quick Scripts)", "Quick Scripts Library"),
                subtitle: L10n.pick(
                    "支持设置页直写与 Scripts 目录双向同步（Zsh / Python 3 / AppleScript / Swift / 自定义 Shebang），支持专属 SVG 矢量图标、全局快捷键与 MCP 智能创建。",
                    "Two-way synced single-file scripts (Zsh, Python 3, AppleScript, Swift & Custom Shebang) with custom SVG icons, global hotkeys, and MCP authoring."
                )
            ) {
                HStack(spacing: 7) {
                    Button(L10n.pick("新建脚本", "New Script")) { ctrl.startNew() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                    Button(L10n.pick("同步目录", "Sync")) { ctrl.reload(); viewModel?.reloadScriptsAndHotKeys() }
                        .buttonStyle(GlassPillButtonStyle())
                    Button(L10n.pick("脚本目录", "Open Folder")) {
                        try? FileManager.default.createDirectory(at: ctrl.store.scriptsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ctrl.store.scriptsDirectory)
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    Button(L10n.pick("恢复示例", "Reset Starters")) {
                        _ = try? ctrl.store.resetStarterScripts(); ctrl.reload(); viewModel?.reloadScriptsAndHotKeys()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                }
            }

            HStack(spacing: 12) {
                scriptListPane.frame(width: 266)
                editorPane.frame(minWidth: 380, maxWidth: .infinity)
            }
        }
        .onAppear {
            ctrl.reload(preferredID: viewModel?.activeScriptSettingsID)
            viewModel?.activeScriptSettingsID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .lucentScriptsDidChange)) { _ in
            ctrl.refreshFromExternalChange()
        }
        .onDisappear { ctrl.stopHotKeyRecording() }
    }

    private var scriptListPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassInputField(symbol: "magnifyingglass", placeholder: L10n.pick("搜索脚本名称或触发词…", "Filter scripts…"), text: $ctrl.filterQuery)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(ctrl.filteredScripts) { item in
                        let selected = ctrl.editingID == item.id
                        HStack(spacing: 8) {
                            PluginIconBadge(
                                symbol: item.symbolIconName,
                                customIconURL: item.customIconURL(in: ctrl.store.scriptsDirectory),
                                accentColor: item.accentColor, size: 30
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(item.displayTitle).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text(item.runtime.badgeLabel)
                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(.teal)
                                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                                        .background(LiquidColors.pillSurface, in: Capsule())
                                }
                                Text((item.keywords.first ?? item.fileName) + (item.hotKey.map { " · \($0)" } ?? ""))
                                    .font(.caption2.monospaced()).foregroundStyle(LiquidColors.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            Toggle("", isOn: Binding(
                                get: { item.isEnabled },
                                set: { ctrl.toggleEnabled(item, enabled: $0, notify: viewModel) }
                            ))
                            .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        }
                        .padding(8)
                        .background(selected ? LiquidColors.highlightGlow : LiquidColors.pillSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: LiquidRadii.row, style: .continuous)
                                .strokeBorder(selected ? Color.teal.opacity(0.5) : LiquidColors.pillBorder, lineWidth: 0.75)
                        }
                        .onTapGesture { ctrl.select(item) }
                        .contextMenu {
                            Button(L10n.pick("在访达中定位脚本", "Reveal in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([ctrl.store.scriptURL(for: item)])
                            }
                            Button(role: .destructive) { ctrl.delete(item, notify: viewModel) } label: {
                                Text(L10n.pick("删除脚本", "Delete Script"))
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
        }
    }

    private var editorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(ctrl.editingID == nil ? L10n.pick("创建快捷脚本", "Create Quick Script") : L10n.pick("编辑快捷脚本", "Edit Quick Script"))
                        .font(.callout.weight(.bold))
                    Spacer()
                    if let msg = ctrl.statusMessage { Text(msg).font(.caption2).foregroundStyle(.cyan).lineLimit(1) }
                    if let id = ctrl.editingID, let item = ctrl.scripts.first(where: { $0.id == id }) {
                        Button(L10n.pick("删除", "Delete")) { ctrl.delete(item, notify: viewModel) }
                            .buttonStyle(GlassPillButtonStyle(compact: true))
                    }
                    Button(L10n.pick("保存脚本", "Save Script")) { _ = ctrl.save(notify: viewModel) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
                }

                HStack(spacing: 8) {
                    GlassInputField(symbol: "character", placeholder: L10n.pick("中文/主名称", "Script Title"), text: $ctrl.draftTitle)
                    GlassInputField(symbol: "globe", placeholder: L10n.pick("英文名称 (可选)", "English Title (optional)"), text: $ctrl.draftEnglishTitle)
                }
                HStack(spacing: 8) {
                    GlassInputField(symbol: "bolt.fill", placeholder: L10n.pick("触发词 (!json, fmt)", "Keywords (!json, fmt)"), text: $ctrl.draftKeywords)
                    GlassInputField(symbol: "text.alignleft", placeholder: L10n.pick("一句话描述用途", "Short subtitle"), text: $ctrl.draftSubtitle)
                }

                iconAndAppearanceCard
                runtimeAndMountCard

                TextEditor(text: $ctrl.draftCode)
                    .font(.system(size: 11.5, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).frame(minHeight: 132, maxHeight: 175)
                    .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.inputFieldBorder, lineWidth: 0.9) }

                testRunnerBar
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    @ViewBuilder
    private var liveIconPreviewBadge: some View {
        if ctrl.useCustomSvgIcon,
           (try? ScriptHeaderParser.validateSafeSVG(ctrl.draftSvgMarkup)) != nil,
           let liveImg = NSImage(data: Data(ctrl.draftSvgMarkup.utf8)) {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            ZStack {
                shape.fill(LiquidColors.elevatedSurface)
                Image(nsImage: liveImg).resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            }
            .frame(width: 32, height: 32)
            .overlay { shape.strokeBorder(LiquidColors.softCardRimGradient, lineWidth: 0.85) }
        } else {
            let previewURL = (ctrl.editingID.flatMap { id in ctrl.scripts.first { $0.id == id } })
                .flatMap { ctrl.useCustomSvgIcon ? $0.customIconURL(in: ctrl.store.scriptsDirectory) : nil }
            PluginIconBadge(symbol: ctrl.draftIcon, customIconURL: previewURL, accentColor: ctrl.draftAccentColor, size: 32)
        }
    }

    private var iconAndAppearanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                liveIconPreviewBadge
                Button(L10n.pick("SF Symbol 图标", "SF Symbol")) { ctrl.useCustomSvgIcon = false }
                    .buttonStyle(GlassPillButtonStyle(prominent: !ctrl.useCustomSvgIcon, compact: true))
                Button(L10n.pick("自定义 SVG 矢量图标", "Custom SVG Icon")) { ctrl.fillSampleSvgIcon() }
                    .buttonStyle(GlassPillButtonStyle(prominent: ctrl.useCustomSvgIcon, compact: true))
                Spacer()
                ForEach(colorChoices, id: \.self) { name in
                    Circle().fill(PluginVisualPalette.tint(from: name)).frame(width: 15, height: 15)
                        .overlay { if ctrl.draftAccentColor == name { Circle().strokeBorder(Color.white, lineWidth: 1.8) } }
                        .onTapGesture { ctrl.draftAccentColor = name }
                }
            }
            if ctrl.useCustomSvgIcon {
                TextEditor(text: $ctrl.draftSvgMarkup)
                    .font(.system(size: 10.5, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(6).frame(height: 68)
                    .background(LiquidColors.inputFieldSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    GlassInputField(symbol: "sparkles", placeholder: "SF Symbol (terminal.fill / wand.and.stars)", text: $ctrl.draftIcon)
                    GlassInputField(symbol: "folder", placeholder: L10n.pick("分类 (效率/开发)", "Category"), text: $ctrl.draftCategory).frame(width: 130)
                }
            }
        }
        .padding(9).background(LiquidColors.pillSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var runtimeAndMountCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                GlassDropdownMenu(title: L10n.pick("环境：", "Runtime:"), value: ctrl.draftRuntime.title) {
                    ForEach(ScriptRuntime.allCases) { rt in Button(rt.title) { ctrl.applyRuntimeSelection(rt) } }
                }
                if ctrl.draftRuntime == .customShebang {
                    GlassInputField(symbol: "doc.badge.gearshape", placeholder: "扩展名 (mjs/ts/rb)", text: $ctrl.draftExtension).frame(width: 120)
                }
                GlassDropdownMenu(title: L10n.pick("输出：", "Output:"), value: ctrl.draftOutputMode.shortBadge) {
                    ForEach(ScriptOutputMode.allCases) { mode in Button(mode.title) { ctrl.draftOutputMode = mode } }
                }
                Spacer()
                Button { ctrl.toggleHotKeyRecording() } label: {
                    Text(ctrl.isRecordingHotKey ? L10n.pick("按键录制中…", "Press keys…") : (ctrl.draftHotKey.isEmpty ? L10n.pick("录制快捷键", "Record Hotkey") : ctrl.draftHotKey))
                }
                .buttonStyle(GlassPillButtonStyle(prominent: ctrl.isRecordingHotKey, compact: true))
            }

            FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                Toggle(L10n.pick("全局搜索", "Global Search"), isOn: $ctrl.draftIncludeInSearch).toggleStyle(.checkbox).font(.caption2)
                Toggle(L10n.pick("快捷按钮栏", "Quick Bar"), isOn: $ctrl.draftPinnedInQuickBar).toggleStyle(.checkbox).font(.caption2)
                Toggle(L10n.pick("状态栏菜单", "Menu Bar"), isOn: $ctrl.draftShowInMenuBar).toggleStyle(.checkbox).font(.caption2)
                Toggle(L10n.pick("注入剪贴板", "Clipboard"), isOn: $ctrl.draftPassClipboard).toggleStyle(.checkbox).font(.caption2)
                ForEach(PluginResourceScope.allCases, id: \.self) { scope in
                    Toggle(scope.title, isOn: Binding(
                        get: { ctrl.draftScopes.contains(scope) },
                        set: { if $0 { ctrl.draftScopes.insert(scope) } else { ctrl.draftScopes.remove(scope) } }
                    )).toggleStyle(.checkbox).font(.caption2)
                }
            }
        }
        .padding(9).background(LiquidColors.pillSurface.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var testRunnerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                GlassInputField(symbol: "play.circle", placeholder: L10n.pick("测试参数 LUCENT_QUERY（可选）", "Optional test query ($1 / LUCENT_QUERY)"), text: $ctrl.testQuery)
                Button(ctrl.isRunningTest ? L10n.pick("运行中…", "Running…") : L10n.pick("保存并试跑", "Save & Run")) { ctrl.runTest(notify: viewModel) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true)).disabled(ctrl.isRunningTest)
                if let summary = ctrl.latestRunSummary { Text(summary).font(.caption2.monospaced()).foregroundStyle(.mint) }
            }
            if !ctrl.latestRunOutput.isEmpty {
                Text(ctrl.latestRunOutput)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(5).textSelection(.enabled).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
