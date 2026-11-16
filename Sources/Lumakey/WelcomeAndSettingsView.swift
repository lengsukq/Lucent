import AppKit
import LumakeyCore
import SwiftUI

struct WelcomeGuideView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    private let highlights: [(symbol: String, top: Color, bottom: Color, title: String, desc: String)] = [
        ("sparkles", .cyan, .blue, "全局快捷中枢 (⌥Space)", "智能使用频次与钉应用/插件排序，内置 ts/uuid/qr/;短语 开发工具箱"),
        ("paintpalette.fill", .purple, .pink, "双内置主题即点即切", "内置「凝霜留白」与「霓彩流光」两套美学体系，全窗口实时响应"),
        ("command.square.fill", .mint, .teal, "全局热键自定义与冲突诊断", "核心与插件热键即按即录，内置应用内/系统/外部进程三层冲突检测"),
        ("externaldrive.badge.icloud", .blue, .purple, "归档备份与 WebDAV 云同步", "SHA-256 自校验 .lumakeybackup 归档，钥匙串安全同步云盘或 NAS"),
        ("camera.viewfinder", .mint, .teal, "智能截图标注与钉屏 (⌥A / ⌥O)", "窗口吸附、放大镜取色、涂鸦马赛克、悬浮钉屏与 Vision OCR"),
        ("puzzlepiece.extension.fill", .purple, .indigo, "深度融合插件系统与 MCP", "独立插件设置页、子功能全局搜索与按需快捷按钮、Host Bridge")
    ]

    var body: some View {
        let lang = languageManager.current
        SecondaryWindowScaffold(title: "欢迎使用 流光 Lumakey", subtitle: "v0.8.8 · arm64", symbol: "sparkles", pinWindowKey: "welcome") {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    SquircleBadge(symbol: "sparkles", topColor: .cyan, bottomColor: .indigo, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("流光 Lumakey").font(.title2.weight(.bold))
                        Text("为 Apple Silicon 原生打造的轻量效率中枢 · 凝霜留白 / 霓彩流光双主题随心切换")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("立即呼出快捷台 (⌥Space)") { viewModel.showOverlay(filter: .all) }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                .padding(16).liquidGlassCard(cornerRadius: LiquidRadii.bento)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(highlights, id: \.title) { item in
                        HStack(alignment: .center, spacing: 14) {
                            SquircleBadge(symbol: item.symbol, topColor: item.top, bottomColor: item.bottom, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.translate(item.title, for: lang)).font(.callout.weight(.semibold))
                                Text(L10n.translate(item.desc, for: lang)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
                    }
                }

                HStack(spacing: 8) {
                    Button("切换语言") { viewModel.cycleAppLanguage() }.buttonStyle(GlassPillButtonStyle())
                    Button("切换主题") { viewModel.cycleAppTheme() }.buttonStyle(GlassPillButtonStyle())
                    Button("GIF 动图 (⌥G)") { viewModel.startGifRecording() }.buttonStyle(GlassPillButtonStyle())
                    Button("自定义热键") { viewModel.openRoute(.settings(.shortcuts)) }.buttonStyle(GlassPillButtonStyle())
                    Button("插件与 MCP") { viewModel.openRoute(.settings(.plugins)) }.buttonStyle(GlassPillButtonStyle())
                    Spacer()
                    Text("悬浮窗、顶部读数与插件快捷按钮默认关闭")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .liquidGlassCard(cornerRadius: LiquidRadii.card)
            }
        }
        .frame(minWidth: 820, minHeight: 550)
    }
}

struct SettingsCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    private var sidebarExternalPlugins: [PluginDescriptor] {
        viewModel.plugins.filter { !$0.isBuiltin && ($0.showInSettingsSidebar || viewModel.activePluginSettingsID == $0.id) }
    }

    private var currentSubtitle: String {
        if viewModel.activeSettingsSection == .pluginDetail,
           let id = viewModel.activePluginSettingsID,
           let p = viewModel.plugins.first(where: { $0.id == id }) {
            return L10n.pick("插件设置 · \(p.displayName)", "Plugin Settings · \(p.displayName)")
        }
        return viewModel.activeSettingsSection.title
    }

    var body: some View {
        let _ = languageManager.current
        SecondaryWindowScaffold(title: "流光设置与扩展中心", subtitle: currentSubtitle, symbol: "slider.horizontal.3", pinWindowKey: "settings") {
            HStack(spacing: 12) {
                sidebar
                detailPane
            }
        }
        .frame(minWidth: 960, idealWidth: 980, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2.5) {
                sidebarGroupHeader("核心设置")
                ForEach(SettingsSection.coreSidebarSections) { section in sectionButton(section) }
                Divider().opacity(0.25).padding(.vertical, 5)
                sidebarGroupHeader("插件独立设置")
                ForEach(SettingsSection.builtinPluginSections) { section in
                    sectionButton(section, dotActive: isBuiltinActive(section))
                }
                ForEach(sidebarExternalPlugins) { plugin in externalPluginSidebarButton(plugin) }
            }
        }
        .padding(8).frame(width: 214).frame(maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private func sidebarGroupHeader(_ text: String) -> some View {
        Text(L10n.translate(text)).font(.caption.weight(.bold)).foregroundStyle(LiquidColors.textSecondary)
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 2)
    }

    private func isBuiltinActive(_ section: SettingsSection) -> Bool {
        switch section {
        case .mos: viewModel.mosConfig.enabled
        case .lumaLink: viewModel.lumaLinkConfig.enabled
        case .monitor: SystemPulseWindowController.shared.state.config.floatingEnabled || SystemPulseWindowController.shared.state.config.showInMenuBar
        default: false
        }
    }

    private func sectionButton(_ section: SettingsSection, dotActive: Bool? = nil) -> some View {
        let active = viewModel.activeSettingsSection == section
        return Button {
            viewModel.activePluginSettingsID = nil
            viewModel.activeSettingsSection = section
        } label: {
            HStack(alignment: .center, spacing: 9) {
                SquircleBadge(symbol: section.symbolName, topColor: section.badgeColors.top, bottomColor: section.badgeColors.bottom, size: 24)
                Text(section.title).font(.system(size: 12.5, weight: active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let dotActive {
                    Circle().fill(dotActive ? Color.mint : LiquidColors.textSecondary.opacity(0.35)).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(active ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func externalPluginSidebarButton(_ plugin: PluginDescriptor) -> some View {
        let active = viewModel.activeSettingsSection == .pluginDetail && viewModel.activePluginSettingsID == plugin.id
        return Button {
            viewModel.activePluginSettingsID = plugin.id
            viewModel.activeSettingsSection = .pluginDetail
        } label: {
            HStack(alignment: .center, spacing: 9) {
                PluginIconBadge(plugin: plugin, size: 24)
                Text(plugin.displayName).font(.system(size: 12.5, weight: active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                Circle()
                    .fill(plugin.isEnabled && plugin.isValid ? LiquidColors.accentPrimary : LiquidColors.textSecondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(active ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.activeSettingsSection {
            case .general: generalSection
            case .monitor: TelemetrySettingsView()
            case .network: NetworkMonitorCoreView(embeddedInSettings: true) { viewModel.openRoute(.networkMonitor) }
            case .cache: ScrollView { AppCacheSettingsView(viewModel: viewModel).padding(.trailing, 4) }
            case .mos: MosPluginSettingsView(viewModel: viewModel)
            case .lumaLink: LumaLinkSettingsView(viewModel: viewModel)
            case .snippets: SnippetsSettingsView(viewModel: viewModel)
            case .pluginDetail: PluginDedicatedSettingsView(viewModel: viewModel)
            case .shortcuts:
                HotKeySettingsView(
                    hotKeyManager: viewModel.hotKeyManager ?? GlobalHotKeyManager.activeInstance,
                    pluginHotKeys: viewModel.externalPluginHotKeys,
                    externalPlugins: viewModel.plugins.filter { !$0.isBuiltin },
                    onOpenPluginSettings: { id in viewModel.openPluginSettings(id: id) }
                )
            case .backup: BackupSettingsView(viewModel: viewModel)
            default: SettingsDetailSectionsView(viewModel: viewModel, section: viewModel.activeSettingsSection)
            }
        }
        .padding(16)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private var generalSection: some View {
        let memMB = String(format: "%.1f MB", MemoryStats.currentPhysicalFootprintMB())
        let pulseState = SystemPulseWindowController.shared.state
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "slider.horizontal.3", topColor: .blue, bottomColor: .indigo,
                    title: "主题外观、通用驻留与内存自洁",
                    subtitle: "内置「凝霜留白」与「霓彩流光」双视觉主题；悬浮窗、菜单栏读数、Dock 图标与快捷按钮默认关闭。"
                ) {
                    Button("立即释放空闲内存") { viewModel.reclaimAllIdleMemoryNow() }
                        .buttonStyle(GlassPillButtonStyle(prominent: true))
                }
                LanguageSettingsCardView(viewModel: viewModel)
                ThemeSettingsCardView(viewModel: viewModel)
                SettingsToggleCardRow(
                    symbol: "macwindow", topColor: .blue, bottomColor: .indigo,
                    title: "关闭全部窗口后仍在程序坞 (Dock) 常驻图标", subtitle: "打开文件工作台、影院播放、阅读或设置窗口时会自动显示 Dock 图标；仅全部关闭后按此开关收起",
                    isOn: Binding(get: { viewModel.showDockIcon }, set: { viewModel.setDockIconVisible($0) })
                )
                SettingsToggleCardRow(
                    symbol: "waveform.path.ecg", topColor: .mint, bottomColor: .cyan,
                    title: "系统脉搏桌面监控悬浮窗 (快捷键 ⌥M)", subtitle: "默认关闭 · 支持顶部精简胶囊、点击展开趋势与贴边自动隐藏",
                    isOn: Binding(get: { pulseState.config.floatingEnabled }, set: { SystemPulseWindowController.shared.setFloatingEnabled($0) })
                )
                SettingsToggleCardRow(
                    symbol: "menubar.rectangle", topColor: .teal, bottomColor: .blue,
                    title: "在顶部菜单栏显示实时系统状态", subtitle: "默认关闭 · 可进入“系统脉搏监控”自定义 CPU / 频率 / 内存 / 功耗 / 网速",
                    isOn: Binding(get: { pulseState.config.showInMenuBar }, set: { SystemPulseWindowController.shared.setMenuBarEnabled($0) })
                )
                SettingsToggleCardRow(
                    symbol: "computermouse.fill", topColor: .cyan, bottomColor: .indigo,
                    title: "物理鼠标平滑滚动与方向反转", subtitle: "默认关闭 · 仅作用于外接鼠标滚轮，完全保留触控板自然滚动",
                    isOn: Binding(
                        get: { viewModel.mosConfig.enabled },
                        set: { enabled in var next = viewModel.mosConfig; next.enabled = enabled; viewModel.applyMosConfig(next) }
                    )
                )
                HStack(spacing: 10) {
                    metricBox("当前物理内存占用", value: memMB, hint: "隐藏 30s 自动销毁主面板视图")
                    metricBox("全盘文件索引", value: L10n.pick("\(viewModel.everythingNodeCount) 节点", "\(viewModel.everythingNodeCount) nodes"), hint: "按需加载 · 空闲 90s 卸载（保留快照）")
                    metricBox("受控子进程", value: L10n.pick("\(viewModel.activeProcessCount) 个", "\(viewModel.activeProcessCount)"), hint: "8s 超时强杀与退出清理")
                }
                signingStatusCard
                HStack(spacing: 8) {
                    Button("自定义监控指标…") { viewModel.activeSettingsSection = .monitor }.buttonStyle(GlassPillButtonStyle())
                    Button("鼠标滚轮参数…") { viewModel.activeSettingsSection = .mos }.buttonStyle(GlassPillButtonStyle())
                    Button("关闭所有屏幕钉图") { PinWindowController.shared.closeAll() }.buttonStyle(GlassPillButtonStyle())
                    Spacer(minLength: 6)
                    let readyWord = L10n.pick("就绪", "Ready")
                    let missingWord = L10n.pick("未安装", "Missing")
                    Text("ntfs-3g: \(viewModel.toolingStatus.ntfs3gPath != nil ? readyWord : missingWord) · ffmpeg: \(viewModel.toolingStatus.ffmpegPath != nil ? readyWord : missingWord)")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.trailing, 4)
        }
    }

    private var signingStatusCard: some View {
        let sign = CodeSigningInspector.inspect()
        return HStack(spacing: 12) {
            SquircleBadge(
                symbol: sign.isReadyForPublicDistribution ? "checkmark.seal.fill" : (sign.isStableForTCC ? "lock.shield.fill" : "shield.lefthalf.filled"),
                topColor: sign.isStableForTCC ? .green : .blue,
                bottomColor: sign.isStableForTCC ? .teal : .indigo,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(sign.badgeTitle).font(.callout.weight(.semibold))
                Text(sign.explanation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !sign.isStableForTCC {
                Button("隐私与安全性…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(GlassPillButtonStyle())
            }
        }
        .padding(12).liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }

    private func metricBox(_ label: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.translate(label)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.bold).monospacedDigit())
            Text(L10n.translate(hint)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
    }
}
