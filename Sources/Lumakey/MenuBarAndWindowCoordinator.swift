import AppKit
import LumakeyCore
import SwiftUI

@MainActor
final class MenuBarAndWindowCoordinator: NSObject, NSWindowDelegate {
    let viewModel: AppViewModel
    let panelController: FloatingPanelController
    let hotKeyManager = GlobalHotKeyManager()
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:]
    var windowBaseTitles: [String: String] = [:]
    var pluginPanelControllers: [String: PluginFloatingPanelController] = [:]
    private var docWindowOrder: [String] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.panelController = FloatingPanelController(viewModel: viewModel)
        super.init()
        wireCallbacks()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleLanguageChanged), name: .lumakeyLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleMenuBarConfigChanged), name: .lumakeyMenuBarConfigDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleGeneralPreferencesChanged), name: .lumakeyGeneralPreferencesDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleApplicationDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func handleLanguageChanged() { refreshLocalizedChrome() }

    @objc private func handleApplicationDidBecomeActive() {
        viewModel.handleAccessibilityTrustOrMosChanged()
    }

    @objc private func handleMenuBarConfigChanged() {
        viewModel.menuBarConfig = MenuBarConfig.load()
        if let menu = statusItem?.menu { populateStatusMenu(menu) }
    }

    @objc private func handleGeneralPreferencesChanged() {
        refreshStatusBarIcon()
        syncDockPolicy()
        SelectionQuickBarController.shared.syncMonitoring(
            enabled: viewModel.generalPreferences.enableSelectionQuickBar,
            plugins: viewModel.plugins,
            viewModel: viewModel
        )
    }

    func start() {
        setupStatusItem()
        registerHotKeys()
        installMemoryPressureMonitor()
        viewModel.bootstrap()
        syncDockPolicy()
        SelectionQuickBarController.shared.syncMonitoring(
            enabled: viewModel.generalPreferences.enableSelectionQuickBar,
            plugins: viewModel.plugins,
            viewModel: viewModel
        )
        SystemPulseWindowController.shared.start(
            onPurgeMemory: { [weak self] in self?.viewModel.reclaimAllIdleMemoryNow() },
            onMenuBarUpdate: { [weak self] text in self?.statusItem?.button?.title = text.map { " " + $0 } ?? "" },
            onOpenNetworkMonitor: { [weak self] in self?.open(route: .networkMonitor) }
        )
        performInitialLaunchPresentation()
    }

    func showLauncher(filter: OmniFilter = .all) { panelController.show(filter: filter) }

    func shutdown() {
        LaunchIntroController.shared.cancelImmediately()
        hotKeyManager.unregisterAll(); viewModel.shutdownAllServicesAndTasks()
        SelectionQuickBarController.shared.stopAll()
        for (_, ctrl) in pluginPanelControllers { ctrl.stop() }
        pluginPanelControllers.removeAll()
        PluginCustomWebWindowController.shared.closeAll()
        AppUsageTrackerController.shared.flushNow(); AppUsageTrackerController.shared.stopMonitoring()
        if GifCaptureController.shared.isActive { GifCaptureController.shared.cancelCapture() }
        else { GifCaptureController.shared.dismissCompletedHUD(immediately: true) }
        MosEngine.shared.stopTapAndReleaseAll(); LumaLinkServer.shared.stopAll(waitUntilFinished: true)
        SystemPulseWindowController.shared.shutdown()
        ProcessSupervisor.shared.terminateAll(waitGracePeriodSeconds: 0.25)
        PinWindowController.shared.closeAll(animated: false); VideoPlaybackCompat.cleanupTempDirectory()
        for (_, win) in windows { win.delegate = nil; win.contentView = nil; win.close() }
        windows.removeAll(); windowBaseTitles.removeAll()
        memoryPressureSource?.cancel(); memoryPressureSource = nil
    }

    private func wireCallbacks() {
        viewModel.hotKeyManager = hotKeyManager
        viewModel.onRouteRequest = { [weak self] route in self?.open(route: route) }
        viewModel.onHideOverlayRequest = { [weak self] in
            guard let self else { return }
            self.panelController.hide(restorePreviousApp: true, immediately: self.viewModel.isCapturingScreen)
        }
        viewModel.resolveOverlayTargetApp = { [weak self] in self?.panelController.previousFrontmostApp }
        viewModel.onShowOverlayRequest = { [weak self] filter in self?.panelController.show(filter: filter) }
        viewModel.onRecenterFloatingPanel = { [weak self] in self?.panelController.resetPositionToCenter() }
        viewModel.onDockVisibilityChanged = { [weak self] _ in self?.syncDockPolicy() }
        viewModel.onReplayLaunchIntro = { [weak self] in self?.replayLaunchIntroSequence() }
        OCRResultWindowController.shared.onVisibilityChanged = { [weak self] in self?.syncDockPolicy() }
        PluginCustomWebWindowController.shared.onWindowVisibilityChanged = { [weak self] in self?.syncDockPolicy() }
        OCRResultWindowController.shared.onRouteToPlugin = { [weak self] plugin, ctx in
            self?.viewModel.runPluginWithContext(plugin, context: ctx)
        }
    }

    func syncDockPolicy() {
        let hasOpenWindows = !windows.isEmpty
            || OCRResultWindowController.shared.isWindowVisible
            || PluginCustomWebWindowController.shared.hasStandardWindows
        let target: NSApplication.ActivationPolicy = (viewModel.showDockIcon || hasOpenWindows) ? .regular : .accessory
        if NSApp.activationPolicy() != target { NSApp.setActivationPolicy(target) }
    }

    func handleDockReopen() {
        if !windows.isEmpty {
            for win in windows.values where win.isMiniaturized { win.deminiaturize(nil) }
            let preferred = windows["workspace"] ?? windows["videoPlayer"] ?? windows.values.first
            preferred?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        if OCRResultWindowController.shared.bringToFrontIfVisible() {
            NSApp.activate(ignoringOtherApps: true); return
        }
        showLauncher(filter: .all)
    }

    private func registerHotKeys() {
        let handlers: [HotKeyActionID: () -> Void] = [
            .launcher: { [weak self] in self?.panelController.toggle(filter: .all) },
            .files: { [weak self] in self?.panelController.toggle(filter: .files) },
            .clipboard: { [weak self] in self?.panelController.toggle(filter: .clipboard) },
            .screenshotPin: { [weak self] in self?.viewModel.captureAndPinScreenshot() },
            .screenshotOCR: { [weak self] in self?.viewModel.captureAndAnalyzeOCR() },
            .gifRecord: { [weak self] in self?.viewModel.startGifRecording() },
            .workspace: { [weak self] in self?.open(route: .workspace) },
            .systemPulse: { SystemPulseWindowController.shared.toggleFloatingWidget() },
            .networkMonitor: { [weak self] in self?.open(route: .networkMonitor) },
            .quickBackup: { [weak self] in if let vm = self?.viewModel { BackupCoordinator.triggerQuickBackup(viewModel: vm) } }
        ]
        _ = hotKeyManager.applyConfig(HotKeyBindingConfig.load(), handlers: handlers, externalBindings: viewModel.allExternalHotKeyBindings())
    }

    private func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in self?.viewModel.reclaimAllIdleMemoryNow() }
        source.resume(); memoryPressureSource = source
    }

    func openLumaLinkConsole() {
        let hasPlugin = viewModel.plugins.contains { $0.id == LumaLinkServer.companionPluginID }
        open(route: hasPlugin ? .pluginSettings(LumaLinkServer.companionPluginID) : .settings(.lumaLink))
    }

    func open(route: WindowRoute) {
        if case .workspace = route {} else { PreviewPlaybackRegistry.shared.pauseAll() }
        panelController.hide(restorePreviousApp: false); NSApp.activate(ignoringOtherApps: true)
        switch route {
        case .workspace:
            viewModel.ensureWorkspaceLoaded()
            presentWindow(key: "workspace", title: "文件与外置磁盘工作台 · 附加", size: NSSize(width: 1360, height: 780)) { WorkspaceHostView(viewModel: viewModel) }
        case .networkMonitor:
            presentWindow(key: "networkMonitor", title: "本机网络流量与去向监控", size: NSSize(width: 1020, height: 660)) { NetworkMonitorWindowView() }
        case .settings(let section):
            if section == .network {
                presentWindow(key: "networkMonitor", title: "本机网络流量与去向监控", size: NSSize(width: 1020, height: 660)) { NetworkMonitorWindowView() }
                return
            }
            viewModel.activePluginSettingsID = nil; viewModel.activeSettingsSection = section.canonicalSection; presentSettingsWindow()
        case .pluginSettings(let pluginID):
            viewModel.activePluginSettingsID = pluginID; viewModel.activeSettingsSection = .pluginDetail; presentSettingsWindow()
        case .pluginPanel(let req, let seedPayload):
            let key = "pluginPanel:\(req.pluginID)"
            let ctrl: PluginFloatingPanelController
            if let existingCtrl = pluginPanelControllers[key] {
                existingCtrl.applyUpdatedRequest(req, seedPayload: seedPayload)
                ctrl = existingCtrl
            } else {
                let created = PluginFloatingPanelController(request: req, viewModel: viewModel, seedPayload: seedPayload)
                pluginPanelControllers[key] = created
                ctrl = created
            }
            let plugName = viewModel.plugins.first(where: { $0.id == req.pluginID })?.displayName ?? req.pluginID
            presentWindow(
                key: key, title: "\(plugName) · 悬浮面板",
                size: NSSize(width: 520, height: 600), minSize: NSSize(width: 420, height: 360),
                pinOnTop: req.pinOnTop
            ) {
                PluginFloatingPanelWindowView(controller: ctrl, windowKey: key)
            }
        case .documentReader(let url, let siblings):
            let key = "doc:\(url.standardizedFileURL.path)"
            presentWindow(key: key, title: "文档阅读 · \(url.lastPathComponent)", size: NSSize(width: 920, height: 660), isDocumentSlot: true) {
                DocumentReaderWindowView(initialURL: url, siblingURLs: siblings, windowKey: key) { [weak self] in self?.closeAnimated(key: key) }
            }
        case .imageViewer(let url, let siblings, let pinOnTop):
            let key = "img:\(url.standardizedFileURL.path)"
            presentWindow(key: key, title: "只读看图 · \(url.lastPathComponent)", size: NSSize(width: 880, height: 640), isDocumentSlot: true, pinOnTop: pinOnTop) {
                ReadOnlyImageViewerSheet(initialURL: url, siblingURLs: siblings, windowKey: key) { [weak self] in self?.closeAnimated(key: key) }
            }
        case .videoPlayer(let url, let siblings, let pinOnTop):
            presentWindow(key: "videoPlayer", title: "影院播片 · \(url.lastPathComponent)", size: NSSize(width: 1080, height: 660), darkCinema: true, pinOnTop: pinOnTop) {
                CinemaVideoPlayerSheet(initialURL: url, siblingURLs: siblings, windowKey: "videoPlayer") { [weak self] in self?.closeAnimated(key: "videoPlayer") }
            }
        }
    }

    private func closeAnimated(key: String) {
        if let win = windows[key] { WindowMotionAnimator.closeWindowAnimated(win) }
    }

    private func presentSettingsWindow() {
        viewModel.refreshLaunchAtLoginStatus()
        presentWindow(
            key: "settings", title: "流光 Lumakey 设置与插件",
            size: NSSize(width: 980, height: 640), minSize: NSSize(width: 960, height: 620)
        ) { SettingsCenterView(viewModel: viewModel) }
    }

    private func presentWindow<Content: View>(
        key: String, title: String, size: NSSize, minSize: NSSize? = nil,
        isDocumentSlot: Bool = false, darkCinema: Bool = false, pinOnTop: Bool = false, @ViewBuilder content: () -> Content
    ) {
        let hosting = NSHostingView(rootView: LocalizedRootContainer { content() })
        windowBaseTitles[key] = title
        let localizedTitle = L10n.translate(title)
        if minSize != nil { hosting.sizingOptions = [] }
        if let existing = windows[key] {
            existing.title = localizedTitle; if let minSize { existing.minSize = minSize }
            applyAppearance(to: existing, darkCinema: darkCinema); existing.contentView = hosting
            WindowLevelStore.shared.attach(window: existing, key: key, initialPinned: pinOnTop)
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            syncDockPolicy()
            if !existing.isVisible { WindowMotionAnimator.present(existing, style: .standardWindow, makeKey: true) }
            else { existing.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true); return
        }
        if isDocumentSlot {
            docWindowOrder.append(key)
            while docWindowOrder.count > 6 { windows[docWindowOrder.removeFirst()]?.close() }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = localizedTitle; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.minSize = minSize ?? (darkCinema ? NSSize(width: 460, height: 260) : NSSize(width: 680, height: 460))
        applyAppearance(to: window, darkCinema: darkCinema)
        window.isReleasedWhenClosed = false; window.delegate = self
        if let vis = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame {
            let x = vis.midX - size.width / 2
            let y = vis.midY - size.height / 2
            window.setFrameOrigin(NSPoint(
                x: max(vis.minX + 12, min(x, vis.maxX - size.width - 12)),
                y: max(vis.minY + 12, min(y, vis.maxY - size.height - 12))
            ))
        } else {
            window.center()
        }
        window.contentView = hosting; windows[key] = window
        WindowLevelStore.shared.attach(window: window, key: key, initialPinned: pinOnTop)
        syncDockPolicy(); WindowMotionAnimator.present(window, style: .standardWindow, makeKey: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyAppearance(to window: NSWindow, darkCinema: Bool) {
        if darkCinema {
            window.appearance = NSAppearance(named: .darkAqua); window.isOpaque = true
            window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.06, alpha: 1.0)
        } else {
            window.appearance = nil; window.isOpaque = false; window.backgroundColor = .clear
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow,
              let key = windows.first(where: { $0.value === closedWindow })?.key else { return }
        if let panelCtrl = pluginPanelControllers.removeValue(forKey: key) {
            panelCtrl.stop()
        }
        windows.removeValue(forKey: key); windowBaseTitles.removeValue(forKey: key)
        docWindowOrder.removeAll { $0 == key }
        WindowLevelStore.shared.detach(key: key)
        closedWindow.delegate = nil; closedWindow.contentView = nil
        if key == "workspace" { viewModel.releaseWorkspaceMemory() }
        syncDockPolicy(); MemoryStats.reclaimFreeHeapPages()
    }
}
