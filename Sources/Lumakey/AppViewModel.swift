import AppKit
import Combine
import Foundation
import LumakeyCore
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
    var isSyncingPinnedClipboardStore: Bool = false
    @Published var clipboardItems: [ClipboardEntry] = [] {
        didSet {
            guard clipboardItems != oldValue else { return }
            if isOverlayVisible { refreshDisplayedCandidates(resetSelection: false) }
            persistPinnedClipboardIfNeeded(previous: oldValue)
        }
    }
    @Published var clipboardCategory: ClipboardCategory = .all {
        didSet { if clipboardCategory != oldValue { refreshDisplayedCandidates(resetSelection: true) } }
    }
    @Published var isClipboardPaused: Bool = false
    @Published var canUndoClipboardDelete: Bool = false
    var deletedClipboardUndoStack: [(entry: ClipboardEntry, index: Int)] = [] {
        didSet { canUndoClipboardDelete = !deletedClipboardUndoStack.isEmpty }
    }
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

    @Published var mosConfig: MosConfig = MosConfig.load()
    @Published var mosTapActive: Bool = false
    @Published var mosAccessibilityTrusted: Bool = false
    @Published var lumaLinkConfig: LumaLinkConfig = LumaLinkConfig.load()
    @Published var lumaLinkStatus: LumaLinkRuntimeSnapshot = LumaLinkRuntimeSnapshot()
    @Published var lumaLinkRdpStatus: LumaLinkRdpStatus = LumaLinkRdpStatus()

    @Published var layoutMode: ExplorerLayoutMode = .single
    @Published var showWorkspacePreview: Bool = true
    @Published var activePane: PaneSide = .left
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState

    @Published var locations: [LocationItem] = []
    @Published var selectedEntry: FileEntry?
    @Published var selectedEntryIDs: Set<String> = []
    @Published var previewState: PreviewContentState = .empty
    @Published var computedSHA256: String?
    @Published var isComputingSHA256 = false

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
    var hotKeyBannerCancelAction: (() -> Void)? = nil
    var hotKeyBannerDismissTask: Task<Void, Never>? = nil
    @Published var latestCaptureURL: URL?
    @Published var ocrResultText: String = ""
    @Published var barcodeResults: [String] = []
    @Published var serviceMessage: String?
    @Published var diagnostic: UserFacingDiagnostic?

    @Published var showBatchRenameSheet = false
    @Published var renameRule = BatchRenameRule()
    @Published var workspaceClipboard: WorkspaceClipboardState?
    let workspacePrompt = WorkspacePromptController()
    var selectionAnchorID: String?
    var activeDragURLs: [URL] = []

    var isOverlayVisible: Bool = false
    var everythingIndex: EverythingIndex?
    var residentEverythingNodeCount: Int { everythingIndex?.nodes.count ?? 0 }
    var needsEverythingIndexResident: Bool {
        isOverlayVisible && (omniFilter == .files || (!overlayQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scopedPluginID == nil))
    }
    var searchTask: Task<Void, Never>?
    var everythingIndexTask: Task<Void, Never>?
    var previewTask: Task<Void, Never>?
    var hashTask: Task<Void, Never>?
    var clipboardTask: Task<Void, Never>?
    var indexUnloadTask: Task<Void, Never>?
    var queryIdleClearTask: Task<Void, Never>?
    var leftDirectoryTask: Task<Void, Never>?
    var rightDirectoryTask: Task<Void, Never>?
    var locationRefreshTask: Task<Void, Never>?
    var snapshotSaveTask: Task<Void, Never>?
    var pluginRunTask: Task<Void, Never>?
    var activePluginRunToken = UUID()
    var backgroundPluginTasks: [String: Task<Void, Never>] = [:]
    var fsEventWatcher: EverythingFSEventWatcher?
    var pluginWatcher: PluginDirectoryWatcher?
    var scriptsWatcher: PluginDirectoryWatcher?
    var scriptsInProcessObserver: NSObjectProtocol?
    var scriptsDistributedObserver: NSObjectProtocol?
    var homeLayoutObserver: NSObjectProtocol?
    var usageCancellable: AnyCancellable?
    weak var hotKeyManager: GlobalHotKeyManager?
    var directoryCache = WorkspaceDirectoryCache(maxEntries: 48)
    var volumeObservers: [NSObjectProtocol] = []
    var lastPasteboardChangeCount: Int = -1
    var hasLoadedWorkspace: Bool = false
    var lastCapturedSelection: PluginSelectionSnapshot?
    var skipNextSelectionCapture: Bool = false

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

        let home = FileManager.default.homeDirectoryForCurrentUser
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home
        let leftTab = WorkspaceTab(directoryURL: home)
        let rightTab = WorkspaceTab(directoryURL: desktop)
        self.leftPane = PaneState(tabs: [leftTab], activeTabID: leftTab.id)
        self.rightPane = PaneState(tabs: [rightTab], activeTabID: rightTab.id)
    }

    func bootstrap() {
        refreshLaunchAtLoginStatus()
        GifCaptureController.shared.options = generalPreferences.gifDefaultOptions
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

    func navigate(pane: PaneSide, to url: URL, pushHistory: Bool = true) {
        let changed = (pane == .left ? leftPane : rightPane).currentDirectory.standardizedFileURL.path != url.standardizedFileURL.path
        mutatePane(pane) { state in
            if pushHistory, state.currentDirectory != url { state.history.append(state.currentDirectory) }
            state.currentDirectory = url; state.diagnostic = nil
        }
        if changed && activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane)
    }

    func goBack(pane: PaneSide) {
        guard let previous = (pane == .left ? leftPane : rightPane).history.last else { return }
        mutatePane(pane) { $0.history.removeLast() }
        navigate(pane: pane, to: previous, pushHistory: false)
    }

    func addTab(pane: PaneSide) {
        let newTab = WorkspaceTab(directoryURL: (pane == .left ? leftPane : rightPane).currentDirectory)
        mutatePane(pane) { state in state.tabs.append(newTab); state.activeTabID = newTab.id }
        refreshDirectory(pane: pane)
    }

    func selectTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { $0.activeTabID = tabID }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane)
    }

    func closeTab(_ tabID: UUID, in pane: PaneSide) {
        mutatePane(pane) { state in
            guard state.tabs.count > 1, let idx = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            state.tabs.remove(at: idx)
            if state.activeTabID == tabID { state.activeTabID = state.tabs[max(0, idx - 1)].id }
        }
        if activePane == pane { clearWorkspaceSelection() }
        refreshDirectory(pane: pane)
    }
}
