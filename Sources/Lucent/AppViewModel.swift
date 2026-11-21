import AppKit
import Combine
import Foundation
import LucentCore
import SwiftUI

struct SettingsHotKeyBanner: Equatable {
    enum Tone: Equatable { case recording, success, error, neutral }
    let id = UUID()
    let tone: Tone
    let message: String
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var omniFilter: OmniFilter = .all
    @Published var overlayQuery: String = "" {
        didSet { if overlayQuery != oldValue { handleOverlayQueryChanged() } }
    }
    @Published var overlaySelectedIndex: Int = 0
    var userMovedOverlaySelection: Bool = false
    var anchoredOverlayCandidateID: String? = nil
    @Published var isOverlayPinned: Bool = false
    @Published var showOverlayLens: Bool = false
    @Published var focusToken: Int = 0
    @Published var scopedPluginID: String? = nil {
        didSet { if scopedPluginID != oldValue, isOverlayVisible { refreshDisplayedCandidates(resetSelection: true) } }
    }
    @Published var generalPreferences: GeneralPreferences
    @Published var launchAtLoginStatus: LaunchAtLoginStatus = LaunchAtLoginService.currentStatus()
    @Published var everythingScope: EverythingScope

    let clipboard = ClipboardStore()
    let actionMenu = OverlayActionMenuState()

    @Published var inlineResultTitle: String = ""
    @Published var inlineResultBody: String?
    @Published var inlinePluginViewPayload: PluginViewPayload?
    @Published var activeInlinePlugin: PluginDescriptor?
    @Published var isRunningPlugin: Bool = false
    @Published var syncingPluginIDs: Set<String> = []
    @Published var showDockIcon: Bool
    @Published var menuBarConfig: MenuBarConfig = MenuBarConfig.load()
    @Published var homeLayoutConfig: HomeLayoutConfig = HomeLayoutConfig.loadOrBootstrap(legacyPinnedAppIDs: AppUsageService.shared.pinnedAppIDs)
    @Published var appTheme: AppThemeID = ThemeManager.shared.current
    @Published var appLanguage: AppLanguageID = LanguageManager.shared.current
    @Published var activeSettingsSection: SettingsSection = .general
    @Published var activePluginSettingsID: String? = nil
    @Published var activeScriptSettingsID: String? = nil
    @Published var appLaunchCounts: [String: Int] = [:] { didSet { updateCachedDockApps() } }
    @Published var isCapturingScreen: Bool = false

    let deviceServices = DeviceServicesStore()
    let workspace = WorkspaceStore()

    @Published var installedApps: [InstalledAppItem] = [] {
        didSet {
            guard installedApps != oldValue else { return }
            updateCachedDockApps()
            if isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) }
        }
    }
    @Published var plugins: [PluginDescriptor] = [] {
        didSet { if plugins != oldValue, isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) } }
    }
    @Published var pluginCommands: [PluginRegisteredCommand] = [] {
        didSet { if pluginCommands != oldValue, isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) } }
    }
    @Published var enabledQuickButtons: [PluginQuickButtonItem] = []
    @Published var pluginSearchEntries: [PluginSearchEntry] = [] {
        didSet { if pluginSearchEntries != oldValue, isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) } }
    }
    @Published var scripts: [ScriptRecord] = [] {
        didSet { if scripts != oldValue, isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) } }
    }
    @Published var pluginOutputText: String = ""

    @Published var displayedCandidates: [LauncherCandidate] = []
    @Published var cachedVolumes: [VolumeSummary] = []
    @Published var cachedDockApps: [InstalledAppItem] = []
    @Published var everythingNodeCount: Int = 0
    @Published var isIndexingEverything = false

    @Published var toolingStatus = HostToolingStatus()
    @Published var hotKeyBanner: SettingsHotKeyBanner? = nil
    @Published var latestCaptureURL: URL?
    @Published var ocrResultText: String = ""
    @Published var barcodeResults: [String] = []
    @Published var serviceMessage: String?
    @Published var diagnostic: UserFacingDiagnostic?

    let workspacePrompt = WorkspacePromptController()

    let clipboardRuntime = ClipboardRuntimeState()
    let workspaceRuntime = WorkspaceRuntimeState()
    let runtime = OverlayAndIndexRuntimeState()

    var isOverlayVisible: Bool = false
    var everythingIndex: EverythingIndex?
    var lastCapturedSelection: PluginSelectionSnapshot?
    var skipNextSelectionCapture: Bool = false
    weak var hotKeyManager: GlobalHotKeyManager?

    var selectionAnchorID: String? {
        get { workspaceRuntime.selectionAnchorID }
        set { workspaceRuntime.selectionAnchorID = newValue }
    }
    var activeDragURLs: [URL] {
        get { workspaceRuntime.activeDragURLs }
        set { workspaceRuntime.activeDragURLs = newValue }
    }
    var hasLoadedWorkspace: Bool {
        get { workspaceRuntime.hasLoadedWorkspace }
        set { workspaceRuntime.hasLoadedWorkspace = newValue }
    }
    var directoryCache: WorkspaceDirectoryCache { workspaceRuntime.directoryCache }
    var lastPasteboardChangeCount: Int {
        get { clipboardRuntime.lastPasteboardChangeCount }
        set { clipboardRuntime.lastPasteboardChangeCount = newValue }
    }
    var hotKeyBannerCancelAction: (() -> Void)? {
        get { runtime.hotKeyBannerCancelAction }
        set { runtime.hotKeyBannerCancelAction = newValue }
    }

    var residentEverythingNodeCount: Int { everythingIndex?.nodes.count ?? 0 }
    var needsEverythingIndexResident: Bool {
        isOverlayVisible && LauncherEngine.shouldWakeEverythingIndex(
            for: overlayQuery, filter: omniFilter, scopedPluginID: scopedPluginID
        )
    }

    var onRouteRequest: ((WindowRoute) -> Void)?
    var onHideOverlayRequest: (() -> Void)?
    var resolveOverlayTargetApp: (() -> NSRunningApplication?)?
    var onShowOverlayRequest: ((OmniFilter) -> Void)?
    var onRecenterFloatingPanel: (() -> Void)?
    var onDockVisibilityChanged: ((Bool) -> Void)?
    var onReplayLaunchIntro: (() -> Void)?

    init() {
        let initialPrefs = GeneralPreferences.load()
        self.generalPreferences = initialPrefs
        self.showDockIcon = initialPrefs.showDockIcon
        self.everythingScope = EverythingScope(persisted: initialPrefs.defaultEverythingScope)
    }

    func bootstrap() {
        refreshLaunchAtLoginStatus()
        GifCaptureController.shared.options = generalPreferences.gifDefaultOptions
        GifCaptureController.shared.videoOptions = generalPreferences.videoDefaultOptions
        performStartupOrphanCleanup(); refreshCachedVolumes(); installVolumeObservers()
        configureLifecycleIntegrations(); reloadAppsAndPlugins()
        primeEverythingIndexOnStartup(scope: everythingScope)
        MosEngine.shared.onStatusChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.handleAccessibilityTrustOrMosChanged() }
        }
        MosEngine.shared.apply(config: mosConfig, persist: false); refreshMosStatus()
        LumaLinkServer.shared.onStatusChanged = { [weak self] in self?.refreshLumaLinkStatus(refreshPermissions: false) }
        LumaLinkRdpSidecarService.shared.onStatusChanged = { [weak self] in self?.refreshLumaLinkStatus(refreshPermissions: false) }
        let hasCompanion = plugins.contains { $0.id == LumaLinkServer.companionPluginID && $0.isEnabled && $0.isValid }
        if hasCompanion && lumaLinkConfig.enabled {
            LumaLinkServer.shared.apply(config: lumaLinkConfig, persist: false)
            refreshLumaLinkStatus(refreshPermissions: lumaLinkConfig.rdpEnabled)
        } else if lumaLinkConfig.enabled {
            lumaLinkConfig.enabled = false; LumaLinkServer.shared.stopAll()
        }
        loadPersistedPinnedClipboard(); startClipboardMonitor()
        BackupCoordinator.triggerAutoBackupOnLaunchIfNeeded(viewModel: self)
        AppUpdateCoordinator.shared.refreshCachedPluginUpdateCount(installedPlugins: plugins)
        AppUpdateCoordinator.shared.performScheduledCheckOnStartupIfNeeded(viewModel: self)
        Task { [weak self] in
            let detected = await Task.detached(priority: .utility) { HostToolingStatus.detect() }.value
            self?.toolingStatus = detected
        }
    }

    var effectiveLensVisible: Bool {
        omniFilter == .files || omniFilter == .clipboard || scopedPluginID != nil
            || showOverlayLens || inlineResultBody != nil || inlinePluginViewPayload != nil
    }

    var activeScopedPlugin: PluginDescriptor? {
        guard let id = scopedPluginID else { return nil }
        return plugins.first { $0.id == id && $0.isValid && ($0.isBuiltin || $0.isEnabled) }
    }

    var activePaneState: PaneState { activePane == .left ? leftPane : rightPane }
    func mutatePane(_ pane: PaneSide, _ transform: (inout PaneState) -> Void) {
        if pane == .left { transform(&leftPane) } else { transform(&rightPane) }
    }

    var selectedCandidate: LauncherCandidate? {
        guard overlaySelectedIndex >= 0, overlaySelectedIndex < displayedCandidates.count else { return nil }
        return displayedCandidates[overlaySelectedIndex]
    }

    var clipboardHistoryCount: Int { clipboardItems.count }
    var activeProcessCount: Int { ProcessSupervisor.shared.activeCount }
    func updateCachedDockApps() { cachedDockApps = Array(AppUsageService.shared.rankApps(installedApps).prefix(8)) }

    var availableEverythingScopes: [EverythingScope] {
        var list: [EverythingScope] = [.allVolumes, .quickUserFolders, .home]
        for vol in cachedVolumes where vol.mountPath != "/" { list.append(.volume(name: vol.name, mountPath: vol.mountPath)) }
        return list
    }
}
