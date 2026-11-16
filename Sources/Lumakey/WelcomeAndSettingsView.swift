import AppKit
import LumakeyCore
import SwiftUI

struct SettingsCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    private var sidebarExternalPlugins: [PluginDescriptor] {
        viewModel.plugins.filter { !$0.isBuiltin }
    }

    private var currentSubtitle: String {
        if viewModel.activeSettingsSection == .pluginDetail,
           let id = viewModel.activePluginSettingsID,
           let p = viewModel.plugins.first(where: { $0.id == id }) {
            return L10n.pick("插件设置 · \(p.displayName)", "Plugin Settings · \(p.displayName)")
        }
        return viewModel.activeSettingsSection.canonicalSection.title
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
        let active = viewModel.activeSettingsSection.canonicalSection == section
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
            switch viewModel.activeSettingsSection.canonicalSection {
            case .general: generalSection
            case .monitor: TelemetrySettingsView(viewModel: viewModel)
            case .cache: ScrollView { AppCacheSettingsView(viewModel: viewModel).padding(.trailing, 4) }
            case .mos: MosPluginSettingsView(viewModel: viewModel)
            case .lumaLink: LumaLinkSettingsView(viewModel: viewModel)
            case .snippets: SnippetsSettingsView(viewModel: viewModel)
            case .pluginDetail: PluginDedicatedSettingsView(viewModel: viewModel)
            case .shortcuts:
                HotKeySettingsView(
                    hotKeyManager: viewModel.hotKeyManager ?? GlobalHotKeyManager.activeInstance,
                    pluginHotKeys: viewModel.externalPluginHotKeys,
                    plugins: viewModel.plugins,
                    onOpenPluginSettings: { id in viewModel.openPluginSettings(id: id) }
                )
            case .backup: BackupSettingsView(viewModel: viewModel)
            default: SettingsDetailSectionsView(viewModel: viewModel, section: viewModel.activeSettingsSection.canonicalSection)
            }
        }
        .padding(16)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private var generalSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "slider.horizontal.3", topColor: .blue, bottomColor: .indigo,
                    title: "通用外观与全盘检索范围",
                    subtitle: "语言、双视觉主题、程序坞驻留策略与默认磁盘检索范围设置；插件独立配置请直接点击左侧列表。"
                ) {
                    Button("关闭所有屏幕钉图") { PinWindowController.shared.closeAll() }
                        .buttonStyle(GlassPillButtonStyle())
                }
                LanguageSettingsCardView(viewModel: viewModel)
                ThemeSettingsCardView(viewModel: viewModel)
                SettingsToggleCardRow(
                    symbol: "macwindow", topColor: .blue, bottomColor: .indigo,
                    title: "关闭全部窗口后仍在程序坞 (Dock) 常驻图标",
                    subtitle: "打开文件工作台、影院播放、阅读或设置窗口时会自动显示 Dock 图标；仅全部关闭后按此开关收起",
                    isOn: Binding(get: { viewModel.showDockIcon }, set: { viewModel.setDockIconVisible($0) })
                )
                searchScopeCard
                signingStatusCard
            }
            .padding(.trailing, 4)
        }
    }

    private var searchScopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("默认文件检索作用域", systemImage: "magnifyingglass.circle.fill")
                    .font(.callout.weight(.semibold))
                Text(viewModel.isIndexingEverything ? L10n.pick("索引中…", "Indexing…") : L10n.pick("\(viewModel.everythingNodeCount) 节点", "\(viewModel.everythingNodeCount) nodes"))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LiquidColors.accentPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(LiquidColors.pillSurface, in: Capsule())
                Spacer()
                Button("重建磁盘缓存") { viewModel.forceRebuildEverythingIndex() }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
                Button("立即呼出搜文件 (⌥F)") { viewModel.showOverlay(filter: .files) }
                    .buttonStyle(GlassPillButtonStyle(prominent: true, compact: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 8)], spacing: 8) {
                ForEach(viewModel.availableEverythingScopes) { scope in
                    let active = viewModel.everythingScope == scope
                    Button { viewModel.rebuildEverythingIndex(scope: scope) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: scopeIcon(scope))
                                .foregroundStyle(active ? Color.white : LiquidColors.accentPrimary)
                            Text(scope.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .foregroundStyle(active ? Color.white : LiquidColors.textPrimary)
                        .background(active ? Color.accentColor : LiquidColors.pillSurface, in: RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: LiquidRadii.card, solidReadable: true)
    }

    private func scopeIcon(_ scope: EverythingScope) -> String {
        switch scope {
        case .allVolumes: "externaldrive.fill.badge.checkmark"
        case .quickUserFolders: "folder.fill"
        case .home: "house.fill"
        case .volume: "externaldrive.fill"
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
}
