import AppKit
import CoreGraphics
import LucentCore
import SwiftUI

final class KeyableFloatingPanel: NSPanel {
    weak var searchField: NSTextField?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        focusSearchFieldIfNeeded(moveCursorToEnd: false)
    }

    @MainActor
    func focusSearchFieldIfNeeded(moveCursorToEnd: Bool) {
        guard let field = searchField, field.window === self else { return }
        let activeEditor = field.currentEditor() as? NSTextView
        if activeEditor == nil || firstResponder !== activeEditor {
            _ = makeFirstResponder(field)
        }
        guard moveCursorToEnd,
              let editor = fieldEditor(false, for: field) as? NSTextView,
              !editor.hasMarkedText() else { return }
        let len = (field.stringValue as NSString).length
        editor.setSelectedRange(NSRange(location: len, length: 0))
    }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let panelWidth: CGFloat = 880
    private let panelHeight: CGFloat = 544
    private var panel: KeyableFloatingPanel?
    private unowned let viewModel: AppViewModel
    private var idleTeardownTask: Task<Void, Never>?
    private var focusRetryTask: Task<Void, Never>?
    private var userDraggedTopCenter: NSPoint?
    private var isAdjustingFrame = false
    private var isPresenting = false
    private var isHiding = false
    private(set) var previousFrontmostApp: NSRunningApplication?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        if viewModel.generalPreferences.rememberOverlayPosition,
           let saved = viewModel.generalPreferences.savedOverlayTopCenter {
            self.userDraggedTopCenter = NSPoint(x: saved.x, y: saved.y)
        }
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppDidResignActive), name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    var isVisible: Bool { panel?.isVisible == true && !isHiding }

    func toggle(filter: OmniFilter) {
        if isVisible && viewModel.omniFilter == filter { hide(restorePreviousApp: true) } else { show(filter: filter) }
    }

    func showFromLaunchIntro(filter: OmniFilter = .all) {
        show(filter: filter, motionStyle: .launcherFromIntro)
    }

    func resolvedLaunchTargetFrame() -> NSRect {
        computedTargetFrame(width: panelWidth, height: panelHeight)
    }

    func show(filter: OmniFilter, motionStyle: WindowMotionStyle = .launcher) {
        idleTeardownTask?.cancel(); idleTeardownTask = nil
        focusRetryTask?.cancel(); focusRetryTask = nil
        let panel = ensurePanel()
        let wasActivelyVisible = panel.isVisible && !isHiding
        isHiding = false
        if !wasActivelyVisible {
            let front = NSWorkspace.shared.frontmostApplication
            if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousFrontmostApp = front
            } else {
                previousFrontmostApp = nil
            }
        }
        viewModel.prepareOverlay(filter: filter)
        if !wasActivelyVisible {
            positionPanel(panel, width: panelWidth, height: panelHeight, animated: false)
        }
        isPresenting = true
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        if !wasActivelyVisible {
            WindowMotionAnimator.present(panel, style: motionStyle, makeKey: true)
        } else {
            panel.alphaValue = 1.0
            panel.makeKeyAndOrderFront(nil)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.focusSearchFieldIfNeeded(moveCursorToEnd: true)
        isPresenting = false
        viewModel.bumpFocusToken()
        scheduleFocusReinforcement()
    }

    func hide(restorePreviousApp: Bool = true, immediately: Bool = false) {
        focusRetryTask?.cancel(); focusRetryTask = nil
        guard let panel, panel.isVisible else { return }
        if isHiding && !immediately { return }
        isHiding = true
        let targetApp = previousFrontmostApp
        previousFrontmostApp = nil
        viewModel.handleOverlayHidden()
        if restorePreviousApp, let targetApp, !targetApp.isTerminated, !targetApp.isActive {
            NSApp.yieldActivation(to: targetApp)
            targetApp.activate()
        }
        WindowMotionAnimator.dismiss(panel, style: .launcher, immediately: immediately) { [weak self] in
            guard let self else { return }
            self.isHiding = false
            self.scheduleIdlePanelTeardown()
        }
    }

    func resetPositionToCenter() {
        userDraggedTopCenter = nil
        if viewModel.generalPreferences.savedOverlayTopCenter != nil {
            viewModel.updateGeneralPreferences { $0.savedOverlayTopCenter = nil }
        }
        guard let panel, panel.isVisible else { return }
        positionPanel(panel, width: panelWidth, height: panelHeight, animated: true)
    }

    @objc private func handleAppDidResignActive() {
        guard !isPresenting, isVisible, !viewModel.isOverlayPinned, !viewModel.isCapturingScreen else { return }
        hide(restorePreviousApp: false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting, !isHiding, !viewModel.isOverlayPinned, !viewModel.isCapturingScreen else { return }
        hide(restorePreviousApp: false)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame, !isHiding, let panel, panel.isVisible else { return }
        let pt = NSPoint(x: panel.frame.midX, y: panel.frame.maxY)
        userDraggedTopCenter = pt
        if viewModel.generalPreferences.rememberOverlayPosition {
            let anchor = PersistedOverlayAnchor(x: Double(pt.x.rounded()), y: Double(pt.y.rounded()))
            if viewModel.generalPreferences.savedOverlayTopCenter != anchor {
                viewModel.updateGeneralPreferences { $0.savedOverlayTopCenter = anchor }
            }
        }
    }

    private func scheduleFocusReinforcement() {
        focusRetryTask = Task { [weak self] in
            for delayMs in [18, 75] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, let self, self.isVisible, let panel = self.panel else { return }
                self.isPresenting = true
                if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
                if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
                panel.focusSearchFieldIfNeeded(moveCursorToEnd: false)
                self.isPresenting = false
            }
        }
    }

    private func ensurePanel() -> KeyableFloatingPanel {
        if let panel { return panel }
        let created = KeyableFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        created.becomesKeyOnlyIfNeeded = false
        created.level = .floating; created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false; created.backgroundColor = .clear; created.hasShadow = true
        created.isMovableByWindowBackground = true; created.hidesOnDeactivate = false; created.delegate = self

        let glassRoot = RoundedGlassContainerView(cornerRadius: LiquidRadii.panel)
        let hosting = NSHostingView(rootView: LocalizedRootContainer { OverlayCommandView(viewModel: viewModel) })
        hosting.sizingOptions = []; hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true; hosting.layer?.backgroundColor = NSColor.clear.cgColor
        glassRoot.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glassRoot.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: glassRoot.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glassRoot.topAnchor), hosting.bottomAnchor.constraint(equalTo: glassRoot.bottomAnchor)
        ])
        created.contentView = glassRoot
        self.panel = created
        return created
    }

    private func resolveTargetScreen() -> NSScreen? {
        switch viewModel.generalPreferences.overlayScreenTarget {
        case .cursorScreen:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        case .focusedWindowScreen:
            if let pid = previousFrontmostApp?.processIdentifier,
               let winScreen = Self.screenForFrontmostWindow(pid: pid) {
                return winScreen
            }
            return NSScreen.main ?? NSScreen.screens.first
        case .primaryScreen:
            return NSScreen.screens.first ?? NSScreen.main
        }
    }

    private static func screenForFrontmostWindow(pid: pid_t) -> NSScreen? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryH = NSScreen.screens.first?.frame.height else { return nil }
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width >= 60, cgRect.height >= 60 else { continue }
            let appKitMid = NSPoint(x: cgRect.midX, y: primaryH - cgRect.midY)
            if let hit = NSScreen.screens.first(where: { $0.frame.contains(appKitMid) }) { return hit }
        }
        return nil
    }

    private func computedTargetFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = resolveTargetScreen()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let activeSaved: NSPoint? = viewModel.generalPreferences.rememberOverlayPosition
            ? (userDraggedTopCenter ?? viewModel.generalPreferences.savedOverlayTopCenter.map { NSPoint(x: $0.x, y: $0.y) })
            : nil
        let topCenter = (activeSaved.flatMap { screen?.frame.contains($0) == true ? $0 : nil })
            ?? NSPoint(x: visible.midX, y: visible.maxY - 72)
        let x = min(max(visible.minX + 16, topCenter.x - width / 2.0), visible.maxX - width - 16)
        let y = min(max(visible.minY + 24, topCenter.y - height), visible.maxY - height - 12)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat, animated: Bool) {
        let targetFrame = computedTargetFrame(width: width, height: height)
        isAdjustingFrame = true
        if animated {
            WindowMotionAnimator.animateFrame(panel, to: targetFrame, duration: 0.24) { [weak self] in
                self?.isAdjustingFrame = false
            }
        } else {
            panel.setFrame(targetFrame, display: true, animate: false)
            isAdjustingFrame = false
        }
    }

    private func scheduleIdlePanelTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, let panel = self.panel, !panel.isVisible else { return }
            panel.contentView = nil; panel.delegate = nil; self.panel = nil
            MemoryStats.reclaimFreeHeapPages()
        }
    }
}
