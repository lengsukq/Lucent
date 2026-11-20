import AppKit
import LucentCore
import SwiftUI

private final class KeyableIntroPanel: NSPanel {
    var onUserInterrupt: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        onUserInterrupt?()
    }

    override func cancelOperation(_ sender: Any?) {
        onUserInterrupt?()
    }
}

@MainActor
final class LaunchIntroController {
    static let shared = LaunchIntroController()

    private var panel: KeyableIntroPanel?
    private var animState: LaunchIntroAnimationState?
    private var sequenceTask: Task<Void, Never>?
    private var pendingLauncherCallback: (@MainActor () -> Void)?
    private var hasTriggeredLauncher = false
    private var shouldOpenLauncherOnFinish = true

    private init() {}

    var isPlaying: Bool { panel != nil }

    func play(
        targetFrame: NSRect,
        openLauncherOnFinish: Bool = true,
        onTriggerLauncher: (@MainActor () -> Void)? = nil
    ) {
        cancelImmediately()

        guard !SystemDisplayPreferences.shared.reduceMotion,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            if openLauncherOnFinish { onTriggerLauncher?() }
            return
        }

        let state = LaunchIntroAnimationState()
        self.animState = state
        self.shouldOpenLauncherOnFinish = openLauncherOnFinish
        self.pendingLauncherCallback = nil
        if openLauncherOnFinish {
            self.pendingLauncherCallback = onTriggerLauncher
        }
        self.hasTriggeredLauncher = false

        let introPanel = KeyableIntroPanel(
            contentRect: targetFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        introPanel.becomesKeyOnlyIfNeeded = false
        introPanel.level = .popUpMenu
        introPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        introPanel.isOpaque = false
        introPanel.backgroundColor = .clear
        introPanel.hasShadow = false
        introPanel.hidesOnDeactivate = false
        introPanel.onUserInterrupt = { [weak self] in
            Task { @MainActor [weak self] in
                self?.skipAndOpenLauncherNow()
            }
        }

        let hosting = NSHostingView(
            rootView: LocalizedRootContainer {
                LaunchIntroOverlayView(state: state) { [weak self] in
                    self?.skipAndOpenLauncherNow()
                }
            }
        )
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        introPanel.contentView = hosting
        introPanel.setFrame(targetFrame, display: true)
        hosting.layoutSubtreeIfNeeded()
        if openLauncherOnFinish && !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        introPanel.orderFrontRegardless()
        introPanel.makeKeyAndOrderFront(nil)
        self.panel = introPanel

        sequenceTask = Task { [weak self] in
            await self?.runChoreography(state: state)
        }
    }

    func skipAndOpenLauncherNow() {
        sequenceTask?.cancel()
        sequenceTask = nil
        if shouldOpenLauncherOnFinish {
            fireLauncherOnce()
        }
        teardownPanelAndReclaim()
    }

    func cancelImmediately() {
        sequenceTask?.cancel()
        sequenceTask = nil
        pendingLauncherCallback = nil
        hasTriggeredLauncher = true
        teardownPanelAndReclaim()
    }

    private func runChoreography(state: LaunchIntroAnimationState) async {
        // Allow frame 0 to commit resting state before triggering Beat 1 spring on cold launch.
        try? await Task.sleep(for: .milliseconds(32))
        guard !Task.isCancelled else { return }

        // Beat 1 (0.00s): Materialize 3D Prism Keycap & Ambient Aurora
        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            state.auraVisible = true
            state.iconOpacity = 1.0
            state.iconScale = 1.04
            state.iconOffsetY = 0
            state.iconTiltDegrees = 4
        }

        try? await Task.sleep(for: .milliseconds(185))
        guard !Task.isCancelled else { return }

        // Beat 2 (0.185s): "一触" Tactile Keycap Press Down-Stroke + Reveal Slogan Plaque
        withAnimation(.spring(response: 0.14, dampingFraction: 0.72)) {
            state.iconScale = 0.90
            state.iconOffsetY = 5
            state.iconTiltDegrees = -3
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            state.plaqueVisible = true
        }

        try? await Task.sleep(for: .milliseconds(115))
        guard !Task.isCancelled else { return }

        // Beat 3 (0.30s): "流光" Rebound + Shockwave Ripple + Sweeping Light Beam & Fuse Ignition
        state.rippleOpacity = 0.95
        withAnimation(.spring(response: 0.30, dampingFraction: 0.68)) {
            state.iconScale = 1.0
            state.iconOffsetY = 0
            state.iconTiltDegrees = 0
        }
        withAnimation(.easeOut(duration: 0.78)) {
            state.rippleProgress = 1.0
            state.rippleOpacity = 0.0
        }
        withAnimation(.easeInOut(duration: 0.86)) {
            state.shimmerPhase = 1.25
        }
        withAnimation(.timingCurve(0.22, 0.92, 0.36, 1.0, duration: 0.90)) {
            state.fuseProgress = 1.0
        }

        try? await Task.sleep(for: .milliseconds(860))
        guard !Task.isCancelled else { return }

        // Beat 4 (1.16s): "用完即焚 -> 跃出悬浮框" Morph Silhouette Outward & Dissolve Stage
        withAnimation(.timingCurve(0.18, 0.96, 0.30, 1.0, duration: 0.25)) {
            state.morphWaveActive = shouldOpenLauncherOnFinish
            state.stageDissolving = true
        }

        try? await Task.sleep(for: .milliseconds(95))
        guard !Task.isCancelled else { return }

        // Overlap Floating Panel spring pop-out seamlessly out of the dissolving light core!
        if shouldOpenLauncherOnFinish {
            fireLauncherOnce()
        }

        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled else { return }

        // Self-clean intro window & heap pages ("用完即焚")
        teardownPanelAndReclaim()
    }

    private func fireLauncherOnce() {
        guard !hasTriggeredLauncher else { return }
        hasTriggeredLauncher = true
        let cb = pendingLauncherCallback
        pendingLauncherCallback = nil
        cb?()
    }

    private func teardownPanelAndReclaim() {
        if let p = panel {
            p.onUserInterrupt = nil
            p.orderOut(nil)
            p.contentView = nil
            p.close()
        }
        panel = nil
        animState = nil
        MemoryStats.reclaimFreeHeapPages()
    }
}

extension MenuBarAndWindowCoordinator {
    func performInitialLaunchPresentation() {
        let prefs = viewModel.generalPreferences
        let reduceMotion = SystemDisplayPreferences.shared.reduceMotion
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let action = LaunchPresentationPolicy.resolve(
            launchSilentlyInMenuBar: prefs.launchSilentlyInMenuBar,
            showLaunchIntroAnimation: prefs.showLaunchIntroAnimation,
            reduceMotion: reduceMotion
        )
        switch action {
        case .silent:
            return
        case .playIntroThenShowLauncher:
            let frame = panelController.resolvedLaunchTargetFrame()
            LaunchIntroController.shared.play(targetFrame: frame, openLauncherOnFinish: true) { [weak self] in
                self?.panelController.showFromLaunchIntro(filter: .all)
            }
        case .playIntroThenStaySilent:
            let frame = panelController.resolvedLaunchTargetFrame()
            LaunchIntroController.shared.play(targetFrame: frame, openLauncherOnFinish: false)
        case .showLauncherImmediately:
            panelController.show(filter: .all)
        }
    }

    func replayLaunchIntroSequence() {
        panelController.hide(restorePreviousApp: false, immediately: true)
        for win in windows.values where win.isVisible {
            win.orderBack(nil)
        }
        let frame = panelController.resolvedLaunchTargetFrame()
        LaunchIntroController.shared.play(targetFrame: frame, openLauncherOnFinish: true) { [weak self] in
            self?.panelController.showFromLaunchIntro(filter: .all)
        }
    }
}
