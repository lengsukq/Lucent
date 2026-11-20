import AppKit
import Combine
import LucentCore
import Quartz
import SwiftUI

@MainActor
final class FileShelfPanels {
    static let shared = FileShelfPanels()
    private var panels: [String: FileShelfPanelController] = [:]

    var visibleCount: Int { panels.values.filter { $0.window?.isVisible == true }.count }

    func open(pluginID: String, urls: [URL], takeFocus: Bool, expandIfTucked: Bool = true) -> Bool {
        guard let store = FileShelfStore.local(pluginID: pluginID) else { return false }
        let panel = panels[pluginID] ?? FileShelfPanelController(pluginID: pluginID, store: store)
        panels[pluginID] = panel
        panel.open(takeFocus: takeFocus, expandIfTucked: expandIfTucked)
        if !urls.isEmpty { panel.model.add(urls) }
        FloatingWindowSessionStore.upsertFileShelf(pluginID: pluginID)
        return true
    }

    func restorePersistedShelves(plugins: [PluginDescriptor]) {
        let savedIDs = FloatingWindowSessionStore.load().fileShelfPluginIDs
        guard !savedIDs.isEmpty else { return }
        for id in savedIDs {
            guard let plugin = plugins.first(where: {
                $0.id == id && $0.isValid && ($0.isBuiltin || $0.isEnabled) && $0.isCapabilityGranted(.fileShelf)
            }) else {
                FloatingWindowSessionStore.removeFileShelf(pluginID: id)
                continue
            }
            _ = open(pluginID: plugin.id, urls: [], takeFocus: false, expandIfTucked: false)
        }
    }

    func synchronize(plugins: [PluginDescriptor]) {
        let allowed = Set(plugins.filter { $0.isEnabled && $0.isValid && $0.isCapabilityGranted(.fileShelf) }.map(\.id))
        for id in Array(panels.keys) where !allowed.contains(id) {
            panels.removeValue(forKey: id)?.dispose(clearSession: true)
        }
    }

    func closeAll(clearPersistedSession: Bool = true) {
        for panel in panels.values {
            panel.closeWindow(clearPersistedSession: clearPersistedSession)
        }
    }
}

@MainActor
final class FileShelfPanelController: NSWindowController, NSWindowDelegate, @preconcurrency QLPreviewPanelDataSource {
    let pluginID: String
    let model: FileShelfModel
    let panelState: FileShelfPanelState
    let frameName: NSWindow.FrameAutosaveName
    let settingsKey: String

    var glassView: RoundedGlassContainerView?
    var hoverContainer: FileShelfHoverTrackingView?
    var lastAppliedCornerRadius: CGFloat = 0
    var isApplyingFrame = false
    var isHovered = false
    var isDraggingIntoShelf = false
    var isSearchFocused = false
    var isModalSheetActive = false
    var isManuallyRevealed = false
    var skipSessionRemovalOnClose = false

    var hoverExitTask: Task<Void, Never>?
    var dragSettleTask: Task<Void, Never>?
    private var previewURL: URL?
    private var layoutSubscription: AnyCancellable?

    init(pluginID: String, store: FileShelfStore) {
        self.pluginID = pluginID
        self.model = FileShelfModel(store: store)
        self.frameName = "FileShelf-\(pluginID)"
        self.settingsKey = "FileShelfSettings-\(pluginID)"
        let savedSettings = Self.loadSettings(forKey: settingsKey)
        let initialMode = FileShelfEdgeGeometry.resolveMode(
            settings: savedSettings, isHovered: false, isDraggingIntoShelf: false, isModalOrInputActive: false
        )
        self.panelState = FileShelfPanelState(settings: savedSettings, mode: initialMode)

        let panel = PluginHUDCanvasPanel(
            contentRect: NSRect(origin: .zero, size: FileShelfEdgeGeometry.expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = L10n.pick("文件中转站", "File Shelf")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self

        if !panel.setFrameUsingName(frameName) {
            let visible = activeVisibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - FileShelfEdgeGeometry.expandedSize.width - FileShelfEdgeGeometry.screenInset,
                y: visible.midY - FileShelfEdgeGeometry.expandedSize.height / 2
            ))
        }

        layoutSubscription = model.$rows.map(\.isEmpty).removeDuplicates().dropFirst().sink { [weak self] _ in
            guard let self, self.panelState.mode == .expanded, self.window?.isVisible == true else { return }
            self.reconcilePresentation(animate: true)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage), name: .lucentLanguageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshThemeCorner), name: .lucentThemeDidChange, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            workspace.addObserver(self, selector: #selector(refreshVolumes), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    func open(takeFocus: Bool, expandIfTucked: Bool = true) {
        guard let window else { return }
        if glassView == nil || window.contentView !== glassView { mountGlassContent() }
        hoverExitTask?.cancel(); hoverExitTask = nil
        if expandIfTucked {
            isManuallyRevealed = true
            panelState.settings.collapsedCapsule = false
            let cursorVis = activeVisibleFrame
            if !cursorVis.intersects(window.frame) {
                panelState.settings.anchorMidY = Double(cursorVis.midY)
            }
            saveSettings()
        } else {
            isManuallyRevealed = false
        }
        let wasVisible = window.isVisible
        reconcilePresentation(animate: wasVisible, preferCursorScreen: expandIfTucked)
        model.refresh()
        if !wasVisible {
            WindowMotionAnimator.present(window, style: .pulseCapsule, makeKey: false)
            if takeFocus { window.makeKeyAndOrderFront(nil) }
        } else {
            window.orderFrontRegardless()
            if takeFocus { window.makeKeyAndOrderFront(nil) }
        }
    }

    func closeWindow(clearPersistedSession: Bool) {
        skipSessionRemovalOnClose = !clearPersistedSession
        window?.close()
        skipSessionRemovalOnClose = false
    }

    func dispose(clearSession: Bool) {
        cancelTimers()
        model.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        closeWindow(clearPersistedSession: clearSession)
    }

    func windowDidBecomeKey(_ notification: Notification) { model.refresh() }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, (notification.object as? NSWindow) === window else { return }
        dragSettleTask?.cancel()
        dragSettleTask = Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons == 0 {
                    self?.handleDragFinished()
                    return
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        cancelTimers()
        window?.saveFrame(usingName: frameName)
        if !skipSessionRemovalOnClose {
            FloatingWindowSessionStore.removeFileShelf(pluginID: pluginID)
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.dataSource === self {
            preview.orderOut(nil)
            preview.dataSource = nil
        }
        previewURL = nil
        model.cancelRefresh()
        window?.contentView = nil
        glassView = nil
        hoverContainer = nil
        lastAppliedCornerRadius = 0
        MemoryStats.reclaimFreeHeapPages()
    }

    func preview(_ row: FileShelfRowState) {
        guard let url = model.validatedURLs(for: [row]).first, let panel = QLPreviewPanel.shared() else { return }
        previewURL = url
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURL.map { $0 as NSURL } }

    func locate(_ row: FileShelfRowState) {
        guard let window else { return }
        isModalSheetActive = true
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.prompt = L10n.pick("重新关联", "Relink")
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isModalSheetActive = false
            if response == .OK, let url = picker.url { self.model.relink(row.item, to: url) }
            self.scheduleAutoCollapseIfPointerOutside()
        }
    }

    func confirmClear() {
        guard let window else { return }
        isModalSheetActive = true
        let alert = NSAlert()
        alert.messageText = L10n.pick("清空中转站？", "Clear the shelf?")
        alert.informativeText = L10n.pick("所有暂放条目都会移除。原文件保留在磁盘上。",
                                          "All shelf entries will be removed. The original files stay on disk.")
        alert.addButton(withTitle: L10n.pick("取消", "Cancel"))
        alert.addButton(withTitle: L10n.pick("清空", "Clear"))
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            self.isModalSheetActive = false
            if result == .alertSecondButtonReturn { self.model.clear() }
            self.scheduleAutoCollapseIfPointerOutside()
        }
    }

    var activeVisibleFrame: NSRect {
        ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    @objc private func refreshLanguage(_ notification: Notification) {
        window?.title = L10n.pick("文件中转站", "File Shelf")
        model.refreshLabels()
    }

    @objc private func refreshThemeCorner(_ notification: Notification) {
        glassView?.updateCornerRadius(currentShellCornerRadius, force: true)
    }

    @objc private func refreshVolumes(_ notification: Notification) {
        if window?.isVisible == true { model.refresh() }
    }
}
