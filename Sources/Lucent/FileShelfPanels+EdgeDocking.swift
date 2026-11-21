import AppKit
import LucentCore
import QuartzCore
import SwiftUI

@MainActor
extension FileShelfPanelController {
    var currentShellCornerRadius: CGFloat {
        switch panelState.mode {
        case .edgeTucked(.top): 14
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
            onDragWillStart: { [weak self] in self?.handleDragWillStart() },
            onDragMoved: { [weak self] frame, visible in self?.handleDragMoved(frame: frame, visibleFrame: visible) },
            onDragEnded: { [weak self] visible in self?.handleDragFinished(explicitVisibleFrame: visible) },
            onSearchFocusChanged: { [weak self] focused in self?.setSearchFocused(focused) },
            onDraggedOut: { [weak self] ids in self?.handleDraggedOut(ids: ids) },
            close: { [weak self] in self?.closeWindow(clearPersistedSession: true) },
            preview: { [weak self] row in self?.preview(row) },
            locate: { [weak self] row in self?.locate(row) },
            clear: { [weak self] in self?.confirmClear() },
            matchingPlugins: { [weak self] rows in
                guard let self else { return [] }
                return FileShelfPanels.shared.matchingPlugins(for: rows.compactMap(\.url), excludingPluginID: self.pluginID)
            },
            sendToPlugin: { plugin, ctx in FileShelfPanels.shared.onRouteToPlugin?(plugin, ctx) }
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
            tracker.leadingAnchor.constraint(equalTo: glass.leadingAnchor), tracker.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            tracker.topAnchor.constraint(equalTo: glass.topAnchor), tracker.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: tracker.leadingAnchor), hosting.trailingAnchor.constraint(equalTo: tracker.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: tracker.topAnchor), hosting.bottomAnchor.constraint(equalTo: tracker.bottomAnchor)
        ])
        hoverContainer = tracker
        window.contentView = glass
    }

    func reconcilePresentation(animate: Bool, preferCursorScreen: Bool = false, explicitVisibleFrame: CGRect? = nil) {
        guard let window else { return }
        let nextMode = FileShelfEdgeGeometry.resolveMode(
            settings: panelState.settings, isHovered: isHovered, isDraggingIntoShelf: isDraggingIntoShelf,
            isModalOrInputActive: isSearchFocused || isModalSheetActive, isManuallyRevealed: isManuallyRevealed
        )
        if panelState.mode != nextMode { panelState.mode = nextMode }
        let targetScreen = preferCursorScreen
            ? (ScreenTopologyAndWindowMatcher.activeCursorScreen() ?? NSScreen.main)
            : (window.screen ?? ScreenTopologyAndWindowMatcher.activeCursorScreen() ?? NSScreen.main)
        let visible = explicitVisibleFrame ?? targetScreen?.visibleFrame ?? activeVisibleFrame
        let size = FileShelfEdgeGeometry.targetSize(for: nextMode, isEmpty: model.rows.isEmpty, visibleFrame: visible)
        let targetFrame = FileShelfEdgeGeometry.frame(
            for: nextMode, dockEdge: panelState.settings.dockEdge, size: size,
            currentFrame: window.frame,
            anchorMidX: panelState.settings.anchorMidX.map { CGFloat($0) },
            anchorMidY: panelState.settings.anchorMidY.map { CGFloat($0) },
            visibleFrame: visible
        )
        let radius = currentShellCornerRadius
        if abs(radius - lastAppliedCornerRadius) > 0.1 {
            lastAppliedCornerRadius = radius
            glassView?.updateCornerRadius(radius, force: true)
        }
        guard !NSEqualRects(window.frame, targetFrame) else { return }
        let movingAcrossDisplays = explicitVisibleFrame == nil && window.screen != nil && targetScreen != nil && window.screen !== targetScreen
        isApplyingFrame = true
        let allowAnimate = animate && !movingAcrossDisplays && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if allowAnimate {
            let duration: TimeInterval = nextMode == .expanded ? 0.18 : 0.20
            WindowMotionAnimator.animateFrame(window, to: targetFrame, duration: duration) { [weak self] in
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

    func handleDragWillStart() {
        isUserDragging = true
        cancelHoverTimers()
        dragSettleTask?.cancel(); dragSettleTask = nil
    }

    func handleDragMoved(frame: CGRect, visibleFrame: CGRect) {
        let near = FileShelfEdgeGeometry.detectSnapEdge(frame: frame, visibleFrame: visibleFrame)
        if panelState.nearDockEdge != near { panelState.nearDockEdge = near }
    }

    func handleDragFinished(explicitVisibleFrame: CGRect? = nil) {
        isUserDragging = false
        if panelState.nearDockEdge != .none { panelState.nearDockEdge = .none }
        dragSettleTask?.cancel(); dragSettleTask = nil
        guard let window else { return }
        let visible = explicitVisibleFrame
            ?? ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? window.screen?.visibleFrame ?? activeVisibleFrame
        let snapped = FileShelfEdgeGeometry.detectSnapEdge(frame: window.frame, visibleFrame: visible)
        panelState.settings.dockEdge = snapped
        panelState.settings.anchorMidX = Double(window.frame.midX)
        panelState.settings.anchorMidY = Double(window.frame.midY)
        isManuallyRevealed = false
        if snapped != .none {
            panelState.settings.collapsedCapsule = false
            if panelState.settings.edgeAutoHide && !panelState.settings.pinnedExpanded {
                isHovered = false
                ignoreHoverUntil = CACurrentMediaTime() + 0.32
            } else {
                isHovered = window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
            }
        } else {
            isHovered = false
        }
        saveSettings()
        reconcilePresentation(animate: true, explicitVisibleFrame: visible)
    }

    func setHovered(_ hovered: Bool) {
        guard !isUserDragging else { return }
        cancelHoverTimers()
        if hovered {
            guard NSEvent.pressedMouseButtons == 0 else { return }
            if panelState.mode != .expanded && CACurrentMediaTime() < ignoreHoverUntil { return }
            isManuallyRevealed = false
            guard !isHovered else { return }
            if panelState.mode != .expanded && !isDraggingIntoShelf {
                hoverEnterTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(110))
                    guard !Task.isCancelled, let self, !self.isUserDragging, NSEvent.pressedMouseButtons == 0 else { return }
                    self.isHovered = true
                    self.reconcilePresentation(animate: true)
                }
            } else {
                isHovered = true
                reconcilePresentation(animate: true)
            }
            return
        }
        isManuallyRevealed = false
        scheduleAutoCollapseIfPointerOutside()
    }

    func scheduleAutoCollapseIfPointerOutside() {
        hoverExitTask?.cancel()
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self, !self.isUserDragging, NSEvent.pressedMouseButtons == 0 else { return }
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
                ignoreHoverUntil = CACurrentMediaTime() + 0.32
            } else {
                ignoreHoverUntil = 0
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
            panelState.settings.anchorMidX = Double(window?.frame.midX ?? activeVisibleFrame.midX)
            panelState.settings.anchorMidY = Double(window?.frame.midY ?? activeVisibleFrame.midY)
            if panelState.settings.edgeAutoHide && !panelState.settings.pinnedExpanded {
                isHovered = false
                isManuallyRevealed = false
                ignoreHoverUntil = CACurrentMediaTime() + 0.32
            }
        } else {
            ignoreHoverUntil = 0
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

    func cancelHoverTimers() {
        hoverEnterTask?.cancel(); hoverEnterTask = nil
        hoverExitTask?.cancel(); hoverExitTask = nil
    }

    func cancelTimers() {
        cancelHoverTimers()
        dragSettleTask?.cancel(); dragSettleTask = nil
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(panelState.settings) { UserDefaults.standard.set(data, forKey: settingsKey) }
    }

    static func loadSettings(forKey key: String) -> FileShelfWindowSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FileShelfWindowSettings.self, from: data) else { return FileShelfWindowSettings() }
        return decoded
    }
}
