import AppKit
import CoreGraphics
import LucentCore
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GifCaptureController: ObservableObject {
    static let shared = GifCaptureController()

    @Published private(set) var phase: GifCapturePhase = .idle
    @Published var options: GifRecordingOptions = GeneralPreferences.load().gifDefaultOptions
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var encodedFrameCount: Int = 0
    @Published private(set) var mergedFrameCount: Int = 0
    @Published private(set) var latestResult: GifFinalizeResult?

    var onRecordingCompleted: ((GifFinalizeResult) -> Void)?
    var onStatusMessage: ((String) -> Void)?
    var onDiagnostic: ((UserFacingDiagnostic) -> Void)?

    private var selectionPanels: [CaptureOverlayPanel] = []
    private var panelByDisplayID: [CGDirectDisplayID: CaptureOverlayPanel] = [:]
    private var borderPanels: [RecordingRegionBorderPanel] = []
    private var hudPanel: GifHUDPanel?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var selectionSession: GifSelectionSession?
    private var captureTask: Task<Void, Never>?
    private var activeEncoder: GifStreamEncoder?
    private var pendingCompletionHandler: ((GifFinalizeResult) -> Void)?
    private let focusGuard = CaptureFocusGuard()

    private init() {}
    var isActive: Bool { phase != .idle }

    func startInteractiveCapture(
        options overrideOptions: GifRecordingOptions? = nil, preferredTargetApp: NSRunningApplication? = nil,
        onComplete: ((GifFinalizeResult) -> Void)? = nil
    ) {
        if case .recording = phase { hudPanel?.orderFrontRegardless(); return }
        if case .encoding = phase { return }
        cleanupAllResources(discardEncoder: true, animatedHUD: false)
        focusGuard.prepareForNewCapture(preferredApp: preferredTargetApp)
        self.options = overrideOptions ?? GeneralPreferences.load().gifDefaultOptions
        self.pendingCompletionHandler = onComplete

        guard CGPreflightScreenCaptureAccess() else {
            focusGuard.finishRestore(restorePreviousApp: false)
            CGRequestScreenCaptureAccess()
            let err = LucentError.visionFailed("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lucent。")
            onDiagnostic?(err.diagnostic); onStatusMessage?(err.diagnostic.reason)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
            return
        }
        Task { [weak self] in await self?.prepareAndPresentSelection() }
    }

    func togglePauseResume() {
        guard case .recording(let isPaused) = phase else { return }
        phase = .recording(isPaused: !isPaused)
    }

    func finishRecording() {
        guard case .recording = phase, let encoder = activeEncoder else { return }
        captureTask?.cancel(); captureTask = nil; activeEncoder = nil
        closeBorderPanels(); phase = .encoding

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) { try encoder.finalize() }.value
                _ = GifStreamEncoder.copyGifToPasteboard(at: result.fileURL)
                self.latestResult = result; self.phase = .completed(result)
                let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
                self.onStatusMessage?("GIF 动图已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴")
                self.onRecordingCompleted?(result); self.pendingCompletionHandler?(result); self.pendingCompletionHandler = nil
            } catch {
                self.cleanupAllResources(discardEncoder: false, animatedHUD: true); self.phase = .idle
                self.onStatusMessage?(error.localizedDescription)
            }
        }
    }

    func cancelCapture() {
        cleanupAllResources(discardEncoder: true, animatedHUD: true); phase = .idle
        onStatusMessage?("已取消 GIF 录制并清理临时缓冲")
    }

    func dismissCompletedHUD(immediately: Bool = false) {
        cleanupAllResources(discardEncoder: false, animatedHUD: !immediately); phase = .idle
    }

    func consumePendingCompletionHandler() -> ((GifFinalizeResult) -> Void)? {
        let cb = pendingCompletionHandler
        pendingCompletionHandler = nil
        return cb
    }

    private func prepareAndPresentSelection() async {
        try? await Task.sleep(for: .milliseconds(70))
        do {
            let topology = try await ScreenTopologyAndWindowMatcher.captureSnapshot(includePixelatedPreview: false)
            let initialPt = topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation)
            presentSelectionOverlays(session: GifSelectionSession(topology: topology, initialCursorCanvasPoint: initialPt, options: options))
        } catch {
            focusGuard.finishRestore(restorePreviousApp: false); onStatusMessage?(error.localizedDescription)
        }
    }

    private func presentSelectionOverlays(session: GifSelectionSession) {
        selectionSession = session; phase = .selectingRegion
        selectionPanels.removeAll(); panelByDisplayID.removeAll()
        focusGuard.suppressBackgroundWindowsIfNeeded(excluding: selectionPanels)
        for slice in session.topology.displays {
            let p = GifHUDPanel.presentSelection(
                session: session, slice: slice, makeKey: slice.displayID == session.activeDisplayID,
                onStart: { [weak self] in self?.beginRecordingFromSelection() },
                onCancel: { [weak self] in self?.cancelCapture() }
            )
            selectionPanels.append(p); panelByDisplayID[slice.displayID] = p
        }
        focusGuard.activateAppForCapture()
        panelByDisplayID[session.activeDisplayID]?.makeKeyAndOrderFront(nil)
        installScreenChangeObserver()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self, let current = self.selectionSession else { return event }
            if event.type == .mouseMoved || event.type == .leftMouseDragged {
                let prevID = current.activeDisplayID
                current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
                if event.type == .mouseMoved, current.activeDisplayID != prevID, !current.isDragging, current.activeDrag == nil {
                    self.panelByDisplayID[current.activeDisplayID]?.makeKey()
                }
                return event
            }
            if event.type == .rightMouseDown {
                if current.selectionRect != nil {
                    current.selectionRect = nil; current.selectedWindow = nil
                    current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
                } else { self.cancelCapture() }
                return nil
            }
            if event.keyCode == 53 { self.cancelCapture(); return nil }
            if event.keyCode == 48 && current.selectionRect == nil { _ = current.cycleHoveredWindow(); return nil }
            if (event.keyCode == 36 || event.keyCode == 76), current.selectionRect != nil { self.beginRecordingFromSelection(); return nil }
            return event
        }
    }

    private func beginRecordingFromSelection() {
        guard let session = selectionSession, let sel = session.selectionRect?.standardized, sel.width >= 12, sel.height >= 12 else { return }
        options = session.options
        var prefs = GeneralPreferences.load()
        if prefs.gifDefaultOptions != session.options { prefs.gifDefaultOptions = session.options; prefs.save() }
        let appKitRegion = session.appKitScreenRect(for: sel)
        let targetSlice = session.topology.targetSlice(forSelection: sel, fallbackPoint: session.cursorPoint) ?? session.topology.displays[0]
        let lockedWindowID = session.selectedWindow?.id
        let displaySpecs = session.topology.displays.map { (scDisplay: $0.scDisplay, canvasFrame: $0.canvasFrame, scale: $0.scale) }
        let outDims = session.outputDimensions(for: sel)

        closeSelectionPanels(); elapsedSeconds = 0; encodedFrameCount = 0; mergedFrameCount = 0
        phase = .recording(isPaused: false)
        if lockedWindowID == nil { borderPanels = RecordingRegionBorderPanel.presentBorders(forAppKitRect: appKitRegion) }
        hudPanel = GifHUDPanel.present(near: appKitRegion, visibleFrame: targetSlice.appKitScreen.visibleFrame, controller: self)

        let encoder = GifStreamEncoder(options: options); activeEncoder = encoder
        var excludedIDs = Set(borderPanels.map { CGWindowID($0.windowNumber) })
        if let hudID = hudPanel.map({ CGWindowID($0.windowNumber) }) { excludedIDs.insert(hudID) }

        captureTask = Task { [weak self] in
            await self?.runCaptureLoop(
                canvasRect: sel, lockedWindowID: lockedWindowID, displaySpecs: displaySpecs,
                outputSize: outDims, excludedWindowIDs: excludedIDs, encoder: encoder
            )
        }
    }

    private func runCaptureLoop(
        canvasRect: CGRect, lockedWindowID: CGWindowID?,
        displaySpecs: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        outputSize: (Int, Int), excludedWindowIDs: Set<CGWindowID>, encoder: GifStreamEncoder
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            cancelCapture(); return
        }
        let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let streamPair = await ScreenRecordingStreamEngine.startHardwareStreamIfSingleSource(
            canvasRect: canvasRect, lockedWindowID: lockedWindowID, displaySpecs: displaySpecs,
            excludedWindowIDs: excludedWindowIDs, options: options, outputSize: outputSize, shareableContent: content
        )
        defer { if let stream = streamPair?.stream { Task { try? await stream.stopCapture() } } }

        let nominal = options.frameIntervalSeconds
        var lastUptime: TimeInterval?

        while !Task.isCancelled {
            guard case .recording(let isPaused) = phase else { break }
            if isPaused { lastUptime = nil; try? await Task.sleep(for: .milliseconds(80)); continue }
            let tickStart = ProcessInfo.processInfo.systemUptime
            let next = await ScreenRecordingStreamEngine.captureNextFrame(
                streamSink: streamPair?.sink, lockedWindowID: lockedWindowID, canvasRect: canvasRect, displaySpecs: displaySpecs,
                shareableContent: content, excludedWindows: excluded, showsCursor: options.showsCursor, outputSize: outputSize
            )
            if next.fatalError {
                if encoder.encodedFrameCount > 0 { finishRecording() } else { cancelCapture() }
                return
            }
            guard let frame = next.image, !Task.isCancelled else { try? await Task.sleep(for: .milliseconds(25)); continue }
            guard case .recording(let pausedAfter) = phase, !pausedAfter else { lastUptime = nil; continue }
            let now = ProcessInfo.processInfo.systemUptime
            let delta = lastUptime.map { min(max(now - $0, nominal * 0.4), 1.0) } ?? nominal
            lastUptime = now

            let stats = await Task.detached(priority: .userInitiated) {
                _ = encoder.appendFrame(frame, delaySeconds: delta)
                return (encoder.encodedFrameCount, encoder.mergedFrameCount, encoder.totalDurationSeconds)
            }.value
            encodedFrameCount = stats.0; mergedFrameCount = stats.1; elapsedSeconds = stats.2

            if elapsedSeconds >= Double(options.maxDurationSeconds) { finishRecording(); return }
            let waitMs = max(5, Int(((nominal - (ProcessInfo.processInfo.systemUptime - tickStart)) * 1000).rounded()))
            try? await Task.sleep(for: .milliseconds(waitMs))
        }
    }

    private func installScreenChangeObserver() {
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if case .selectingRegion = self.phase { self.cancelCapture() }
                else if case .recording = self.phase {
                    if (self.activeEncoder?.encodedFrameCount ?? 0) > 0 { self.finishRecording() } else { self.cancelCapture() }
                }
            }
        }
    }

    private func closeSelectionPanels() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        let hadPanels = !selectionPanels.isEmpty
        for p in selectionPanels { p.orderOut(nil); p.contentView = nil }
        selectionPanels.removeAll(); panelByDisplayID.removeAll(); selectionSession = nil
        if hadPanels { focusGuard.finishRestore(restorePreviousApp: true) }
    }

    private func closeBorderPanels() {
        for p in borderPanels { p.orderOut(nil); p.contentView = nil }
        borderPanels.removeAll()
    }

    private func cleanupAllResources(discardEncoder: Bool, animatedHUD: Bool) {
        captureTask?.cancel(); captureTask = nil; closeSelectionPanels(); closeBorderPanels()
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs); screenObserver = nil }
        if discardEncoder { activeEncoder?.discard() }
        activeEncoder = nil
        if let closingHUD = hudPanel {
            hudPanel = nil
            if animatedHUD && closingHUD.isVisible {
                WindowMotionAnimator.dismiss(closingHUD, style: .dynamicIsland) { [weak closingHUD] in
                    closingHUD?.contentView = nil; MemoryStats.reclaimFreeHeapPages()
                }
            } else {
                closingHUD.orderOut(nil); closingHUD.contentView = nil; MemoryStats.reclaimFreeHeapPages()
            }
        }
        elapsedSeconds = 0; encodedFrameCount = 0; mergedFrameCount = 0
    }
}
