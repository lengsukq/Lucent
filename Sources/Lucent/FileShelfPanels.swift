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

    func open(pluginID: String, urls: [URL], takeFocus: Bool) -> Bool {
        guard let store = FileShelfStore.local(pluginID: pluginID) else { return false }
        let panel = panels[pluginID] ?? FileShelfPanelController(pluginID: pluginID, store: store)
        panels[pluginID] = panel
        panel.open(takeFocus: takeFocus)
        if !urls.isEmpty { panel.model.add(urls) }
        return true
    }

    func synchronize(plugins: [PluginDescriptor]) {
        let allowed = Set(plugins.filter { $0.isEnabled && $0.isValid && $0.isCapabilityGranted(.fileShelf) }.map(\.id))
        for id in Array(panels.keys) where !allowed.contains(id) {
            panels.removeValue(forKey: id)?.dispose()
        }
    }

    func closeAll() {
        for panel in panels.values { panel.window?.close() }
    }
}

@MainActor
final class FileShelfPanelController: NSWindowController, NSWindowDelegate, @preconcurrency QLPreviewPanelDataSource {
    private enum Metrics {
        static let expanded = NSSize(width: 320, height: 408)
        static let empty = NSSize(width: 320, height: 248)
        static let compact = NSSize(width: 86, height: 46)
        static let inset: CGFloat = 12
    }

    let model: FileShelfModel
    private let frameName: NSWindow.FrameAutosaveName
    private var collapsed = false
    private var previewURL: URL?
    private var layoutSubscription: AnyCancellable?

    init(pluginID: String, store: FileShelfStore) {
        model = FileShelfModel(store: store)
        frameName = "FileShelf-\(pluginID)"
        let panel = PluginHUDCanvasPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.expanded),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = L10n.pick("文件中转站", "File Shelf")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.delegate = self
        if !panel.setFrameUsingName(frameName) {
            let visible = activeVisibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - Metrics.expanded.width - 18,
                                        y: visible.midY - Metrics.expanded.height / 2))
        }
        setCompact(UserDefaults.standard.bool(forKey: "\(frameName)-compact"), animate: false)
        layoutSubscription = model.$rows.map(\.isEmpty).removeDuplicates().dropFirst().sink { [weak self] empty in
            guard let self, !self.collapsed, self.window?.isVisible == true else { return }
            self.position(empty ? Metrics.empty : Metrics.expanded,
                          animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage),
                                               name: .lucentLanguageDidChange, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            workspace.addObserver(self, selector: #selector(refreshVolumes), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { nil }

    func open(takeFocus: Bool) {
        guard let window else { return }
        if window.contentView == nil { renderContent() }
        position(targetSize, animated: false)
        model.refresh()
        if takeFocus { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
    }

    func dispose() {
        model.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        window?.close()
    }

    func windowDidBecomeKey(_ notification: Notification) { model.refresh() }

    func windowDidMove(_ notification: Notification) { window?.saveFrame(usingName: frameName) }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: frameName)
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.dataSource === self {
            preview.orderOut(nil)
            preview.dataSource = nil
        }
        previewURL = nil
        model.cancelRefresh()
        window?.contentView = nil
    }

    func toggleCompact() { setCompact(!collapsed, animate: true) }

    func preview(_ row: FileShelfRowState) {
        guard let url = model.validatedURLs(for: [row]).first, let panel = QLPreviewPanel.shared() else { return }
        previewURL = url
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL.map { $0 as NSURL }
    }

    func locate(_ row: FileShelfRowState) {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.prompt = L10n.pick("重新关联", "Relink")
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = picker.url { self?.model.relink(row.item, to: url) }
        }
    }

    func confirmClear() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.pick("清空中转站？", "Clear the shelf?")
        alert.informativeText = L10n.pick("所有暂放条目都会移除。原文件保留在磁盘上。",
                                          "All shelf entries will be removed. The original files stay on disk.")
        alert.addButton(withTitle: L10n.pick("取消", "Cancel"))
        alert.addButton(withTitle: L10n.pick("清空", "Clear"))
        alert.beginSheetModal(for: window) { [weak self] result in
            if result == .alertSecondButtonReturn { self?.model.clear() }
        }
    }

    private func setCompact(_ next: Bool, animate: Bool) {
        collapsed = next
        UserDefaults.standard.set(next, forKey: "\(frameName)-compact")
        renderContent()
        position(targetSize,
                 animated: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        window?.saveFrame(usingName: frameName)
    }

    private func renderContent() {
        let view = FileShelfView(model: model, compact: collapsed, toggle: { [weak self] in self?.toggleCompact() },
                                 close: { [weak self] in self?.window?.close() },
                                 preview: { [weak self] in self?.preview($0) },
                                 locate: { [weak self] in self?.locate($0) },
                                 clear: { [weak self] in self?.confirmClear() })
        let hosting = NSHostingView(rootView: LocalizedRootContainer { view })
        hosting.sizingOptions = []
        window?.contentView = hosting
    }

    private var targetSize: NSSize {
        if collapsed { return Metrics.compact }
        return model.rows.isEmpty ? Metrics.empty : Metrics.expanded
    }

    private var activeVisibleFrame: NSRect {
        ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 960, height: 720)
    }

    private func position(_ size: NSSize, animated: Bool) {
        guard let window else { return }
        let visible = window.screen?.visibleFrame ?? activeVisibleFrame
        let height = min(size.height, visible.height - Metrics.inset * 2)
        let x = max(visible.minX + Metrics.inset, min(window.frame.maxX - size.width, visible.maxX - size.width - Metrics.inset))
        let y = max(visible.minY + Metrics.inset, min(window.frame.maxY - height, visible.maxY - height - Metrics.inset))
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: height), display: true, animate: animated)
    }

    @objc private func refreshLanguage(_ notification: Notification) {
        window?.title = L10n.pick("文件中转站", "File Shelf")
        model.refreshLabels()
    }

    @objc private func refreshVolumes(_ notification: Notification) {
        if window?.isVisible == true { model.refresh() }
    }
}
