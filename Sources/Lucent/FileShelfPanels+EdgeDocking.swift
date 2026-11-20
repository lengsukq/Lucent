import AppKit
import LucentCore
import SwiftUI

@MainActor
final class FileShelfPanelState: ObservableObject {
    @Published var settings: FileShelfWindowSettings
    @Published var mode: FileShelfPresentationMode

    init(settings: FileShelfWindowSettings, mode: FileShelfPresentationMode) {
        self.settings = settings
        self.mode = mode
    }
}

@MainActor
final class FileShelfHoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

private final class UnconstrainedFileShelfHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

@MainActor
extension FileShelfPanelController {
    var currentShellCornerRadius: CGFloat {
        switch panelState.mode {
        case .edgeTucked: 12
        case .capsule: 22
        case .expanded: LiquidRadii.windowPanel
        }
    }

    func mountGlassContent() {
        guard let window else { return }
        let radius = currentShellCornerRadius
        let glass = RoundedGlassContainerView(cornerRadius: radius)
        lastAppliedCornerRadius = radius
        glassView = glass

        let actions = FileShelfActions(
            togglePinOrAutoHide: { [weak self] in self?.togglePinExpanded() },
            toggleCollapseOrTuck: { [weak self] in self?.toggleCollapseOrTuck() },
            dockToEdge: { [weak self] edge in self?.dockToEdge(edge) },
            toggleEdgeAutoHide: { [weak self] in self?.toggleEdgeAutoHide() },
            toggleRemoveAfterDragOut: { [weak self] in self?.toggleRemoveAfterDragOut() },
            onDragTargetedChanged: { [weak self] targeted in self?.setDraggingIntoShelf(targeted) },
            onSearchFocusChanged: { [weak self] focused in self?.setSearchFocused(focused) },
            onDraggedOut: { [weak self] ids in self?.handleDraggedOut(ids: ids) },
            close: { [weak self] in self?.closeWindow(clearPersistedSession: true) },
            preview: { [weak self] row in self?.preview(row) },
            locate: { [weak self] row in self?.locate(row) },
            clear: { [weak self] in self?.confirmClear() }
        )
        let root = FileShelfView(model: model, panelState: panelState, actions: actions)
        let hosting = UnconstrainedFileShelfHostingView(rootView: LocalizedRootContainer { root })
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let tracker = FileShelfHoverTrackingView()
        tracker.translatesAutoresizingMaskIntoConstraints = false
        tracker.onHoverChanged = { [weak self] hovered in self?.setHovered(hovered) }
        tracker.addSubview(hosting)
        glass.addSubview(tracker)
        NSLayoutConstraint.activate([
            tracker.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            tracker.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            tracker.topAnchor.constraint(equalTo: glass.topAnchor),
            tracker.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: tracker.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: tracker.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: tracker.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: tracker.bottomAnchor)
        ])
        hoverContainer = tracker
        window.contentView = glass
    }

    func reconcilePresentation(animate: Bool, preferCursorScreen: Bool = false) {
        guard let window else { return }
        let nextMode = FileShelfEdgeGeometry.resolveMode(
            settings: panelState.settings,
            isHovered: isHovered,
            isDraggingIntoShelf: isDraggingIntoShelf,
            isModalOrInputActive: isSearchFocused || isModalSheetActive,
            isManuallyRevealed: isManuallyRevealed
        )
        if panelState.mode != nextMode {
            panelState.mode = nextMode
        }
        let targetScreen = preferCursorScreen
            ? (ScreenTopologyAndWindowMatcher.activeCursorScreen() ?? NSScreen.main)
            : (window.screen ?? ScreenTopologyAndWindowMatcher.activeCursorScreen() ?? NSScreen.main)
        let visible = targetScreen?.visibleFrame ?? activeVisibleFrame
        let size = FileShelfEdgeGeometry.targetSize(for: nextMode, isEmpty: model.rows.isEmpty, visibleFrame: visible)
        let anchorY = panelState.settings.anchorMidY.map { CGFloat($0) }
        let targetFrame = FileShelfEdgeGeometry.frame(
            for: nextMode,
            dockEdge: panelState.settings.dockEdge,
            size: size,
            currentFrame: window.frame,
            anchorMidY: anchorY,
            visibleFrame: visible
        )
        let radius = currentShellCornerRadius
        if abs(radius - lastAppliedCornerRadius) > 0.1 {
            lastAppliedCornerRadius = radius
            glassView?.updateCornerRadius(radius, force: true)
        }
        guard !NSEqualRects(window.frame, targetFrame) else { return }
        let movingAcrossDisplays = window.screen != nil && targetScreen != nil && window.screen !== targetScreen
        isApplyingFrame = true
        let allowAnimate = animate && !movingAcrossDisplays && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if allowAnimate {
            WindowMotionAnimator.animateFrame(window, to: targetFrame, duration: 0.20) { [weak self] in
                self?.isApplyingFrame = false
                self?.window?.saveFrame(usingName: self?.frameName ?? "")
            }
        } else {
            window.setFrame(targetFrame, display: true, animate: false)
            window.invalidateShadow()
            isApplyingFrame = false
            window.saveFrame(usingName: frameName)
        }
    }

    func handleDragFinished() {
        dragSettleTask?.cancel(); dragSettleTask = nil
        guard let window else { return }
        let visible = window.screen?.visibleFrame ?? activeVisibleFrame
        let snapped = FileShelfEdgeGeometry.detectSnapEdge(frame: window.frame, visibleFrame: visible)
        panelState.settings.dockEdge = snapped
        panelState.settings.anchorMidY = Double(window.frame.midY)
        isManuallyRevealed = false
        if snapped != .none {
            panelState.settings.collapsedCapsule = false
            isHovered = window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        }
        saveSettings()
        reconcilePresentation(animate: true)
        if snapped != .none && !isHovered {
            scheduleAutoCollapseIfPointerOutside()
        }
    }

    func setHovered(_ hovered: Bool) {
        hoverExitTask?.cancel(); hoverExitTask = nil
        if hovered {
            isManuallyRevealed = false
            guard !isHovered else { return }
            isHovered = true
            reconcilePresentation(animate: true)
            return
        }
        isManuallyRevealed = false
        scheduleAutoCollapseIfPointerOutside()
    }

    func scheduleAutoCollapseIfPointerOutside() {
        hoverExitTask?.cancel()
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled, let self else { return }
            if let win = self.window, win.isVisible,
               win.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                return
            }
            if self.isHovered || self.isManuallyRevealed {
                self.isHovered = false
                self.isManuallyRevealed = false
                self.reconcilePresentation(animate: true)
            }
        }
    }

    func setDraggingIntoShelf(_ targeted: Bool) {
        guard isDraggingIntoShelf != targeted else { return }
        isDraggingIntoShelf = targeted
        if targeted {
            hoverExitTask?.cancel(); hoverExitTask = nil
            reconcilePresentation(animate: true)
        } else {
            scheduleAutoCollapseIfPointerOutside()
        }
    }

    func setSearchFocused(_ focused: Bool) {
        guard isSearchFocused != focused else { return }
        isSearchFocused = focused
        if !focused { scheduleAutoCollapseIfPointerOutside() }
    }

    func togglePinExpanded() {
        if !panelState.settings.edgeAutoHide {
            panelState.settings.edgeAutoHide = true
            panelState.settings.pinnedExpanded = false
        } else {
            panelState.settings.pinnedExpanded.toggle()
        }
        saveSettings()
        reconcilePresentation(animate: true)
    }

    func toggleCollapseOrTuck() {
        if panelState.settings.dockEdge != .none {
            if panelState.mode == .expanded {
                panelState.settings.edgeAutoHide = true
                panelState.settings.pinnedExpanded = false
                isHovered = false
                isManuallyRevealed = false
            } else {
                isManuallyRevealed = true
                isHovered = true
            }
        } else {
            isManuallyRevealed = false
            panelState.settings.collapsedCapsule.toggle()
        }
        saveSettings()
        reconcilePresentation(animate: true)
    }

    func dockToEdge(_ edge: FileShelfDockEdge) {
        panelState.settings.dockEdge = edge
        if edge != .none {
            panelState.settings.collapsedCapsule = false
            panelState.settings.anchorMidY = Double(window?.frame.midY ?? activeVisibleFrame.midY)
        }
        saveSettings()
        reconcilePresentation(animate: true)
    }

    func toggleEdgeAutoHide() {
        panelState.settings.edgeAutoHide.toggle()
        if panelState.settings.edgeAutoHide {
            panelState.settings.pinnedExpanded = false
        }
        saveSettings()
        reconcilePresentation(animate: true)
    }

    func toggleRemoveAfterDragOut() {
        panelState.settings.removeAfterDragOut.toggle()
        saveSettings()
    }

    func handleDraggedOut(ids: Set<UUID>) {
        guard panelState.settings.removeAfterDragOut, !ids.isEmpty else { return }
        model.remove(ids: ids)
    }

    func cancelTimers() {
        hoverExitTask?.cancel(); hoverExitTask = nil
        dragSettleTask?.cancel(); dragSettleTask = nil
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(panelState.settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    static func loadSettings(forKey key: String) -> FileShelfWindowSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FileShelfWindowSettings.self, from: data) else {
            return FileShelfWindowSettings()
        }
        return decoded
    }
}
