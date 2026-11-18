import AppKit
import CoreGraphics
import LucentCore
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScreenCaptureCoordinator {
    static let shared = ScreenCaptureCoordinator()

    private var overlayPanels: [CaptureOverlayPanel] = []
    private var panelByDisplayID: [CGDirectDisplayID: CaptureOverlayPanel] = [:]
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var activeSession: ScreenshotSessionState?
    private var continuation: CheckedContinuation<ScreenshotResult, Error>?
    private var pasteboardSnapshot: PasteboardSnapshot?
    private var didModifyPasteboard = false
    private var lastSelectionRect: CGRect?
    private let focusGuard = CaptureFocusGuard()
    private var captureGeneration: UInt64 = 0

    private init() {}

    func capture(mode: ScreenshotMode, preferredTargetApp: NSRunningApplication? = nil) async throws -> ScreenshotResult {
        if !overlayPanels.isEmpty { finish(with: .cancelled, animated: false) }
        captureGeneration &+= 1
        focusGuard.prepareForNewCapture(preferredApp: preferredTargetApp)
        guard CGPreflightScreenCaptureAccess() else {
            focusGuard.finishRestore(restorePreviousApp: false)
            CGRequestScreenCaptureAccess()
            throw LucentError.visionFailed(L10n.pick("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lucent。", "Screen Recording permission is not granted. Enable Lucent in System Settings > Privacy & Security > Screen Recording."))
        }

        try? await Task.sleep(for: .milliseconds(70))
        let topology: ScreenTopologySnapshot
        do {
            topology = try await ScreenTopologyAndWindowMatcher.captureSnapshot(includePixelatedPreview: true)
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
        session.excludeWindowShadow = GeneralPreferences.load().screenshotExcludeWindowShadow
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.presentOverlays(with: session)
        }
    }

    private func presentOverlays(with session: ScreenshotSessionState) {
        pasteboardSnapshot = PasteboardSnapshot.capture()
        didModifyPasteboard = false
        activeSession = session
        overlayPanels.removeAll(); panelByDisplayID.removeAll()
        focusGuard.suppressBackgroundWindowsIfNeeded(excluding: overlayPanels)

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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self, let current = self.activeSession else { return event }
            return self.handleEvent(event, session: current)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(with: .cancelled, animated: false) }
        }
    }

    private func handleEvent(_ event: NSEvent, session current: ScreenshotSessionState) -> NSEvent? {
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            let prevID = current.activeDisplayID
            current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
            if event.type == .mouseMoved, current.activeDisplayID != prevID,
               !current.isDraggingSelection, current.activeDragMode == nil, current.pendingTextPoint == nil {
                panelByDisplayID[current.activeDisplayID]?.makeKey()
            }
            return event
        }
        if event.type == .rightMouseDown {
            if current.pendingTextPoint != nil {
                current.pendingTextPoint = nil; current.pendingTextValue = ""
            } else if current.selectionRect != nil {
                current.selectionRect = nil; current.selectedWindow = nil
                current.clearAnnotations(); current.activeTool = .move
                current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
            } else {
                finish(with: .cancelled)
            }
            return nil
        }
        if event.keyCode == 53 {
            if current.pendingTextPoint != nil { current.pendingTextPoint = nil; current.pendingTextValue = "" }
            else { finish(with: .cancelled) }
            return nil
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 6 && mods.contains(.command) {
            if mods.contains(.shift) { current.redoAnnotation() } else { current.undoAnnotation() }
            return nil
        }
        guard current.pendingTextPoint == nil else { return event }
        let cleanMods = mods.subtracting([.numericPad, .function])
        if event.keyCode == 48 && cleanMods.isEmpty && current.selectionRect == nil { _ = current.cycleHoveredWindow(); return nil }
        if (event.keyCode == 36 || event.keyCode == 76), current.selectionRect != nil {
            handleAction(current.mode == .quickOCR ? .ocr : .copy); return nil
        }
        if event.keyCode == 8 && mods.contains(.command), current.selectionRect != nil { handleAction(.copy); return nil }
        if event.keyCode == 1 && cleanMods == [.command], current.selectionRect != nil { handleAction(.save); return nil }
        if event.keyCode == 8 && !mods.contains(.command) {
            didModifyPasteboard = false
            let colorVal = mods.contains(.shift) ? current.cursorRGB : current.cursorHex
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(colorVal, forType: .string)
            current.bannerMessage = L10n.pick("已复制色值 \(colorVal)", "Copied color \(colorVal)")
            return nil
        }
        if current.selectionRect != nil, [123, 124, 125, 126].contains(event.keyCode), cleanMods.isSubset(of: [.shift]) {
            let step: CGFloat = cleanMods.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
            let dy: CGFloat = event.keyCode == 126 ? -step : (event.keyCode == 125 ? step : 0)
            if current.nudgeSelection(dx: dx, dy: dy) { syncSelectionIfPossible(session: current); return nil }
        }
        if event.keyCode == 15 && cleanMods.isEmpty && current.selectionRect == nil, let prev = current.previousSelectionRect {
            current.selectionRect = prev; current.selectedWindow = nil
            handleAction(current.mode == .quickOCR ? .ocr : .syncClipboard)
            return nil
        }
        if cleanMods.isEmpty, current.selectionRect != nil {
            if event.keyCode == 35 { handleAction(.pin); return nil }
            if event.keyCode == 31 { handleAction(.ocr); return nil }
            if let shortcutTool = AnnotationToolKind.fromShortcutKeyCode(event.keyCode) {
                current.commitTextAnnotation(); current.activeTool = shortcutTool; return nil
            }
        }
        return event
    }

    func handleAction(_ action: ScreenshotToolbarAction) {
        guard let session = activeSession else { return }
        session.commitTextAnnotation()
        switch action {
        case .cancel: finish(with: .cancelled)
        case .undo: session.undoAnnotation()
        case .redo: session.redoAnnotation()
        case .clear: session.clearAnnotations()
        case .syncClipboard: syncSelectionIfPossible(session: session)
        case .copy, .pin, .ocr, .cutout, .save:
            guard let sel = session.selectionRect?.standardized, sel.width >= 4, sel.height >= 4 else { return }
            lastSelectionRect = sel
            Task { [weak self] in
                guard let self else { return }
                do {
                    let rendered = try await self.renderCaptureImage(session: session, selection: sel)
                    self.performExport(action: action, image: rendered.image, scale: rendered.scale, session: session)
                } catch {
                    session.bannerMessage = error.localizedDescription
                }
            }
        }
    }

    private func renderCaptureImage(session: ScreenshotSessionState, selection: CGRect) async throws -> (image: CGImage, scale: CGFloat) {
        let fallbackScale = session.effectiveScale(for: selection)
        if let win = session.selectedWindow,
           let winCapture = try? await ScreenTopologyAndWindowMatcher.captureIndependentWindowImage(
               windowID: win.id, ignoreShadow: session.excludeWindowShadow, fallbackScale: fallbackScale
           ) {
            let composed = try ScreenshotCompositor.compositeAnnotationsOntoWindowImage(
                windowImage: winCapture.image, windowCanvasFrame: win.frame, annotations: session.annotations
            )
            return (composed, winCapture.scale)
        }
        return try ScreenshotCompositor.renderMultiDisplaySelection(
            slices: session.topology.compositorSlices, canvasBounds: session.screenBounds,
            selectionRect: selection, annotations: session.annotations
        )
    }

    private func syncSelectionIfPossible(session: ScreenshotSessionState) {
        guard session.mode == .interactiveAnnotate,
              let sel = session.selectionRect?.standardized, sel.width >= 4, sel.height >= 4 else { return }
        Task { [weak self] in
            guard let self, self.activeSession === session else { return }
            if let rendered = try? await self.renderCaptureImage(session: session, selection: sel) {
                self.copyComposedToPasteboard(rendered.image, scale: rendered.scale, session: session)
                let prefix = session.selectedWindow != nil ? L10n.pick("✓ 已捕获独立窗口", "✓ Window captured") : L10n.pick("✓ 已自动放入剪贴板", "✓ Auto-copied")
                session.bannerMessage = "\(prefix) · " + L10n.pick("1–0 标注、P 钉图、O 识字或回车完成", "1–0 annotate, P pin, O OCR, or Return")
            }
        }
    }

    private func copyComposedToPasteboard(_ image: CGImage, scale: CGFloat, session: ScreenshotSessionState) {
        ScreenshotCompositor.copyImageToPasteboard(image, scale: scale)
        didModifyPasteboard = true; session.hasAutoCopied = true
    }

    private func performExport(action: ScreenshotToolbarAction, image: CGImage, scale: CGFloat, session: ScreenshotSessionState) {
        do {
            switch action {
            case .copy:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                copyComposedToPasteboard(image, scale: scale, session: session); finish(with: .copied(url))
            case .pin:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                copyComposedToPasteboard(image, scale: scale, session: session)
                let rect = session.screenRectForSelection() ?? NSRect(x: 200, y: 260, width: 360, height: 240)
                finish(with: .pinned(url, rect), animated: false)
            case .ocr:
                finish(with: .ocrRequested(try ScreenshotCompositor.saveTempCapture(image, scale: scale)))
            case .cutout:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                copyComposedToPasteboard(image, scale: scale, session: session); finish(with: .cutoutRequested(url))
            case .save:
                let prefs = GeneralPreferences.load()
                let saveDir = prefs.resolvedCaptureSaveDirectory()
                try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let fileName = "Lucent-\(stamp).png"
                if prefs.quickSaveCaptureWithoutDialog {
                    let dst = saveDir.appendingPathComponent(fileName, isDirectory: false)
                    try ScreenshotCompositor.writePNG(image, scale: scale, to: dst)
                    copyComposedToPasteboard(image, scale: scale, session: session)
                    finish(with: .saved(dst), animated: true)
                    return
                }
                for p in overlayPanels { p.orderOut(nil) }
                let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
                panel.directoryURL = saveDir
                panel.nameFieldStringValue = fileName
                if panel.runModal() == .OK, let url = panel.url {
                    try ScreenshotCompositor.writePNG(image, scale: scale, to: url)
                    copyComposedToPasteboard(image, scale: scale, session: session)
                    finish(with: .saved(url), animated: false)
                } else {
                    for p in overlayPanels { p.orderFrontRegardless() }
                    panelByDisplayID[session.activeDisplayID]?.makeKeyAndOrderFront(nil)
                }
            default: break
            }
        } catch { session.bannerMessage = error.localizedDescription }
    }

    private func finish(with result: ScreenshotResult, animated: Bool = true) {
        if case .cancelled = result, didModifyPasteboard { pasteboardSnapshot?.restore() }
        pasteboardSnapshot = nil; didModifyPasteboard = false
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs); screenObserver = nil }
        let closingPanels = overlayPanels
        overlayPanels.removeAll(); panelByDisplayID.removeAll()
        activeSession = nil
        let shouldRestoreApp = { if case .ocrRequested = result { return false }; return true }()
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
