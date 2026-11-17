import AppKit
import LumakeyCore
import SwiftUI

@MainActor
private final class SettingsSidebarCollapseState: ObservableObject {
    @Published var showHiddenPlugins: Bool = false
}

struct SettingsCenterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var updater = AppUpdateCoordinator.shared
    @StateObject private var collapseState = SettingsSidebarCollapseState()

    private var allExternalPlugins: [PluginDescriptor] { viewModel.plugins.filter { !$0.isBuiltin } }
    private var visibleExternalPlugins: [PluginDescriptor] {
        allExternalPlugins.filter { $0.showInSettingsSidebar || $0.id == viewModel.activePluginSettingsID }
    }
    private var hiddenExternalPlugins: [PluginDescriptor] {
        allExternalPlugins.filter { !$0.showInSettingsSidebar && $0.id != viewModel.activePluginSettingsID }
    }
    private var detailIdentity: String {
        "\(viewModel.activeSettingsSection.canonicalSection.rawValue):\(viewModel.activePluginSettingsID ?? "core")"
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
            HStack(spacing: 12) { sidebar; detailPane }
        }
        .frame(minWidth: 960, idealWidth: 980, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2.5) {
                sidebarGroupHeader("核心设置")
                ForEach(SettingsSection.coreSidebarSections) { section in
                    sectionButton(section, dotActive: coreSectionBadge(section))
                }
                Divider().opacity(0.25).padding(.vertical, 5)
                sidebarGroupHeader("插件独立设置")
                ForEach(SettingsSection.builtinPluginSections) { section in
                    sectionButton(section, dotActive: isBuiltinActive(section))
                }
                if !allExternalPlugins.contains(where: { $0.id == LumaLinkServer.companionPluginID }) {
                    sectionButton(.lumaLink, dotActive: viewModel.lumaLinkConfig.enabled)
                }
                ForEach(visibleExternalPlugins) { plugin in externalPluginSidebarButton(plugin) }
                if !hiddenExternalPlugins.isEmpty {
                    Button {
                        withAnimation(LiquidMotion.snappySpring) { collapseState.showHiddenPlugins.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: collapseState.showHiddenPlugins ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                            Text(L10n.pick("已隐藏插件 (\(hiddenExternalPlugins.count))", "Hidden (\(hiddenExternalPlugins.count))"))
                                .font(.caption2.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(LiquidColors.textSecondary).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    if collapseState.showHiddenPlugins {
                        ForEach(hiddenExternalPlugins) { plugin in externalPluginSidebarButton(plugin) }
                    }
                }
            }
        }
        .padding(8).frame(width: 214).frame(maxHeight: .infinity, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: LiquidRadii.bento)
    }

    private func coreSectionBadge(_ section: SettingsSection) -> Bool? {
        switch section {
        case .plugins: updater.pendingPluginUpdates.isEmpty ? nil : true
        case .about: updater.hasAnyPendingUpdate ? true : nil
        default: nil
        }
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
            withAnimation(LiquidMotion.snappySpring) {
                viewModel.activePluginSettingsID = nil; viewModel.activeSettingsSection = section
            }
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
            .liquidHoverRow(active: active, cornerRadius: 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 10))
    }

    private func externalPluginSidebarButton(_ plugin: PluginDescriptor) -> some View {
        let active = viewModel.activeSettingsSection == .pluginDetail && viewModel.activePluginSettingsID == plugin.id
        return Button {
            withAnimation(LiquidMotion.snappySpring) {
                viewModel.activePluginSettingsID = plugin.id; viewModel.activeSettingsSection = .pluginDetail
            }
        } label: {
            HStack(alignment: .center, spacing: 9) {
                PluginIconBadge(plugin: plugin, size: 24)
                Text(plugin.displayName).font(.system(size: 12.5, weight: active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                let needsPerm = !plugin.isBuiltin && PluginSetupReadiness.analyze(plugin: plugin).hasMissingPermissions
                Circle()
                    .fill(
                        (!plugin.isEnabled || !plugin.isValid)
                            ? LiquidColors.textSecondary.opacity(0.35)
                            : (needsPerm ? Color.orange : LiquidColors.accentPrimary)
                    )
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(active ? LiquidColors.highlightGlow : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .liquidHoverRow(active: active, cornerRadius: 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(LiquidBentoTileStyle(cornerRadius: 10))
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch viewModel.activeSettingsSection.canonicalSection {
                case .general: generalSection
                case .homeLayout: HomeCustomizationSettingsView(viewModel: viewModel)
                case .monitor: TelemetrySettingsView(viewModel: viewModel)
                case .cache: ScrollView { AppCacheSettingsView(viewModel: viewModel).padding(.trailing, 4) }
                case .mos: MosPluginSettingsView(viewModel: viewModel)
                case .lumaLink: LumaLinkSettingsView(viewModel: viewModel)
                case .snippets: SnippetsSettingsView(viewModel: viewModel)
                case .pluginDetail: PluginDedicatedSettingsView(viewModel: viewModel)
                case .shortcuts:
                    HotKeySettingsView(
                        hotKeyManager: viewModel.hotKeyManager ?? GlobalHotKeyManager.activeInstance,
                        pluginHotKeys: viewModel.externalPluginHotKeys, plugins: viewModel.plugins,
                        onOpenPluginSettings: { id in viewModel.openPluginSettings(id: id) }
                    )
                case .backup: BackupSettingsView(viewModel: viewModel)
                default: SettingsDetailSectionsView(viewModel: viewModel, section: viewModel.activeSettingsSection.canonicalSection)
                }
            }
            .id(detailIdentity).transition(LiquidMotion.lensTransition)
        }
        .animation(LiquidMotion.snappySpring, value: detailIdentity)
        .padding(16)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped().liquidGlassCard(cornerRadius: LiquidRadii.bento)
        .overlay(alignment: .top) {
            if let banner = viewModel.hotKeyBanner {
                hotKeyBannerOverlay(banner)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(LiquidMotion.snappySpring, value: viewModel.hotKeyBanner?.id)
    }

    private func hotKeyBannerOverlay(_ banner: SettingsHotKeyBanner) -> some View {
        let accentColor: Color = switch banner.tone {
        case .recording: .cyan
        case .success: .mint
        case .error: .orange
        case .neutral: .secondary
        }
        let iconName: String = switch banner.tone {
        case .recording: "keyboard.badge.ellipsis"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .neutral: "xmark.circle.fill"
        }
        return HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accentColor)
            Text(banner.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if banner.tone == .recording, let cancelAction = viewModel.hotKeyBannerCancelAction {
                Button(L10n.pick("取消录制", "Cancel")) {
                    cancelAction()
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            } else {
                Button {
                    viewModel.dismissHotKeyBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: LiquidRadii.control, solidReadable: true)
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadii.control, style: .continuous)
                .strokeBorder(accentColor.opacity(0.55), lineWidth: 1.0)
        }
    }

    private var generalSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeroHeader(
                    symbol: "slider.horizontal.3", topColor: .blue, bottomColor: .indigo,
                    title: L10n.pick("通用启动、版本更新与检索范围", "General Startup, Updates & Search Scope"),
                    subtitle: L10n.pick(
                        "统一配置开机自启、静默驻留、应用与插件自动更新、状态栏菜单、多屏唤起及索引范围。",
                        "Configure Launch at Login, silent residence, app & plugin updates, status bar menu, launcher behavior, and search scope."
                    )
                ) {
                    Button("关闭所有屏幕钉图") { PinWindowController.shared.closeAll() }
                        .buttonStyle(GlassPillButtonStyle())
                }
                if !CodeSigningInspector.inspect().isStableForTCC {
                    GeneralSigningStatusCardView(viewModel: viewModel)
                }
                StartupAndResidenceCardView(viewModel: viewModel)
                SoftwareAndPluginUpdateCardView(viewModel: viewModel)
                LanguageSettingsCardView(viewModel: viewModel)
                ThemeSettingsCardView(viewModel: viewModel)
                MenuBarCustomizationCardView(viewModel: viewModel)
                LauncherAndCaptureDefaultsCardView(viewModel: viewModel)
                GeneralSearchScopeCardView(viewModel: viewModel)
                if CodeSigningInspector.inspect().isStableForTCC {
                    GeneralSigningStatusCardView(viewModel: viewModel)
                }
            }
            .padding(.trailing, 4)
        }
    }
}
