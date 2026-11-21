import AppKit
import CoreGraphics
import ImageIO
import LucentCore
import LucentMedia
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScreenCaptureCoordinator {
    static let shared = ScreenCaptureCoordinator()

    var overlayPanels: [CaptureOverlayPanel] = []
    var panelByDisplayID: [CGDirectDisplayID: CaptureOverlayPanel] = [:]
    var keyMonitor: Any?
    var screenObserver: NSObjectProtocol?
    var activeSession: ScreenshotSessionState?
    var continuation: CheckedContinuation<ScreenshotResult, Error>?
    var pasteboardSnapshot: PasteboardSnapshot?
    var didModifyPasteboard = false
    var lastSelectionRect: CGRect?
    let focusGuard = CaptureFocusGuard()
    var captureGeneration: UInt64 = 0

    private init() {}

    func capture(mode: ScreenshotMode, preferredTargetApp: NSRunningApplication? = nil) async throws -> ScreenshotResult {
        if !overlayPanels.isEmpty { finish(with: .cancelled, animated: false) }
        captureGeneration &+= 1
        let hadVisibleLucentWindows = (NSApp?.windows ?? []).contains { $0.isVisible && !$0.isMiniaturized && $0.level == .normal }
        focusGuard.prepareForNewCapture(preferredApp: preferredTargetApp)
        guard CGPreflightScreenCaptureAccess() else {
            focusGuard.finishRestore(restorePreviousApp: false)
            CGRequestScreenCaptureAccess()
            throw LucentError.visionFailed(L10n.pick("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lucent。", "Screen Recording permission is not granted. Enable Lucent in System Settings > Privacy & Security > Screen Recording."))
        }

        if hadVisibleLucentWindows {
            try? await Task.sleep(for: .milliseconds(36))
        }
        let topology: ScreenTopologySnapshot
        do {
            topology = try await ScreenTopologyAndWindowMatcher.captureSnapshot(includeOwnOverlayWindows: false)
        } catch {
            focusGuard.finishRestore(restorePreviousApp: false)
            throw error
        }
        let initialPt = topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation)
        let remembered = lastSelectionRect
            .map { $0.intersection(topology.canvasBounds) }
            .flatMap { !$0.isNull && $0.width >= 8 && $0.height >= 8 ? $0 : nil }
        let session = ScreenshotSessionState(
            topology: topology, initialCursorCanvasPoint: initialPt, mode: mode, previousSelectionRect: remembered
        )
        let prefs = GeneralPreferences.load()
        session.excludeWindowShadow = prefs.screenshotExcludeWindowShadow
        if prefs.hiddenToolbarItemSet.contains(ScreenshotToolbarItemID.forTool(session.activeTool).rawValue) {
            session.activeTool = .move
        }
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.presentOverlays(with: session)
        }
    }

    /// Reuses the primary screenshot annotation canvas and toolbar in-place for lossless editing of an active screen Pin.
    func editPinnedImage(
        cleanBaseURL: URL,
        pinAppKitFrame: NSRect,
        existingAnnotations: [ScreenshotAnnotation]
    ) async throws -> ScreenshotResult {
        if !overlayPanels.isEmpty { finish(with: .cancelled, animated: false) }
        captureGeneration &+= 1
        guard let src = CGImageSourceCreateWithURL(cleanBaseURL as CFURL, nil),
              let cleanCG = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw LucentError.visionFailed(L10n.pick("无法加载钉图底图以进行标注编辑。", "Unable to load base pin image for editing."))
        }
        focusGuard.prepareForNewCapture(preferredApp: nil)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw LucentError.visionFailed("No display available.") }
        let targetScreen = screens.max(by: {
            $0.frame.intersection(pinAppKitFrame).width * $0.frame.intersection(pinAppKitFrame).height
                < $1.frame.intersection(pinAppKitFrame).width * $1.frame.intersection(pinAppKitFrame).height
        }) ?? screens[0]
        let dispID = ScreenTopologyAndWindowMatcher.screenDisplayID(targetScreen)
        let scale = max(1.0, CGFloat(cleanCG.width) / max(pinAppKitFrame.width, 1))
        let layout = MultiDisplayLayout(
            screens: [(displayID: dispID, appKitFrame: targetScreen.frame, appKitVisibleFrame: targetScreen.visibleFrame, scale: scale)],
            mainDisplayID: dispID
        )
        guard let desc = layout.slices.first else { throw LucentError.visionFailed("Display layout empty.") }

        let topLeft = layout.canvasPoint(fromAppKitGlobal: NSPoint(x: pinAppKitFrame.minX, y: pinAppKitFrame.maxY))
        let canvasSel = CGRect(origin: topLeft, size: pinAppKitFrame.size).intersection(desc.canvasFrame)
        let fullW = max(2, Int(round(desc.canvasFrame.width * scale)))
        let fullH = max(2, Int(round(desc.canvasFrame.height * scale)))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: fullW, height: fullH, bitsPerComponent: 8, bytesPerRow: fullW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LucentError.visionFailed("Unable to allocate pin edit canvas.")
        }
        ctx.clear(CGRect(x: 0, y: 0, width: fullW, height: fullH))
        let drawRect = CGRect(
            x: (canvasSel.minX - desc.canvasFrame.minX) * scale,
            y: CGFloat(fullH) - (canvasSel.maxY - desc.canvasFrame.minY) * scale,
            width: canvasSel.width * scale,
            height: canvasSel.height * scale
        )
        ctx.draw(cleanCG, in: drawRect)
        guard let fullSheetCG = ctx.makeImage() else { throw LucentError.visionFailed("Pin canvas image nil.") }

        let slice = ScreenDisplaySlice(descriptor: desc, scDisplay: nil, appKitScreen: targetScreen, image: fullSheetCG)
        let topology = ScreenTopologySnapshot(layout: layout, displays: [slice], windows: [])
        let mappedAnnotations: [ScreenshotAnnotation] = existingAnnotations.map { item -> ScreenshotAnnotation in
            var copy = item
            copy.points = item.points.map { pt -> CGPoint in
                CGPoint(x: canvasSel.minX + pt.x * canvasSel.width, y: canvasSel.minY + pt.y * canvasSel.height)
            }
            return copy
        }
        let session = ScreenshotSessionState(
            topology: topology,
            initialCursorCanvasPoint: CGPoint(x: canvasSel.midX, y: canvasSel.midY),
            mode: .interactiveAnnotate,
            isPinEditSession: true,
            initialAnnotations: mappedAnnotations
        )
        session.selectionRect = canvasSel
        session.activeTool = AnnotationToolKind.arrow
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.presentOverlays(with: session)
        }
    }

    func presentOverlays(with session: ScreenshotSessionState) {
        pasteboardSnapshot = PasteboardSnapshot.capture()
        didModifyPasteboard = false
        activeSession = session
        overlayPanels.removeAll(); panelByDisplayID.removeAll()
        if !session.isPinEditSession {
            focusGuard.suppressBackgroundWindowsIfNeeded(excluding: overlayPanels)
        }

        for slice in session.topology.displays {
            let panel = CaptureOverlayPanel(
                contentRect: slice.appKitScreen.frame, styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.level = .screenSaver
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.contentView = FirstMouseHostingView(rootView: LocalizedRootContainer {
                ScreenshotCanvasView(
                    session: session, slice: slice,
                    onAction: { [weak self] action in self?.handleAction(action) }
                )
            })
            panel.setFrame(slice.appKitScreen.frame, display: true)
            WindowMotionAnimator.present(panel, style: .fullscreenOverlay, makeKey: slice.displayID == session.activeDisplayID)
            overlayPanels.append(panel)
            panelByDisplayID[slice.displayID] = panel
        }
        focusGuard.activateAppForCapture()
        panelByDisplayID[session.activeDisplayID]?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .rightMouseDown, .mouseMoved, .leftMouseDragged, .scrollWheel]
        ) { [weak self] event in
            guard let self, let current = self.activeSession else { return event }
            return self.handleEvent(event, session: current)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(with: .cancelled, animated: false) }
        }
    }

    func finish(with result: ScreenshotResult, animated: Bool = true) {
        activeSession?.cancelAXProbe()
        if case .cancelled = result, didModifyPasteboard { pasteboardSnapshot?.restore() }
        pasteboardSnapshot = nil; didModifyPasteboard = false
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs); screenObserver = nil }
        let closingPanels = overlayPanels
        overlayPanels.removeAll(); panelByDisplayID.removeAll()
        activeSession = nil
        let shouldRestoreApp = {
            if case .ocrRequested = result { return false }
            if case .pinEdited = result { return false }
            return true
        }()
        if shouldRestoreApp { focusGuard.beginRestorePreviousAppIfNeeded() }
        let cont = continuation; continuation = nil
        cont?.resume(returning: result)
        guard !closingPanels.isEmpty else {
            focusGuard.finishRestore(restorePreviousApp: shouldRestoreApp); MemoryStats.reclaimFreeHeapPages(); return
        }
        let gen = captureGeneration; var remaining = closingPanels.count
        for panel in closingPanels {
            WindowMotionAnimator.dismiss(panel, style: .fullscreenOverlay, immediately: !animated) { [weak self, weak panel] in
                panel?.contentView = nil; remaining -= 1
                if remaining == 0 {
                    if let self, self.captureGeneration == gen { self.focusGuard.finishRestore(restorePreviousApp: shouldRestoreApp) }
                    MemoryStats.reclaimFreeHeapPages()
                }
            }
        }
    }
}
