import AppKit
import CoreGraphics
import LumakeyCore
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum GifCapturePhase: Equatable {
    case idle
    case selectingRegion
    case recording(isPaused: Bool)
    case encoding
    case completed(GifFinalizeResult)
}

@MainActor
final class GifCaptureController: ObservableObject {
    static let shared = GifCaptureController()

    @Published private(set) var phase: GifCapturePhase = .idle
    @Published var options: GifRecordingOptions = GifRecordingOptions()
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var encodedFrameCount: Int = 0
    @Published private(set) var mergedFrameCount: Int = 0
    @Published private(set) var latestResult: GifFinalizeResult?

    var onRecordingCompleted: ((GifFinalizeResult) -> Void)?
    var onStatusMessage: ((String) -> Void)?
    var onDiagnostic: ((UserFacingDiagnostic) -> Void)?

    private var selectionPanels: [CaptureOverlayPanel] = []
    private var panelByDisplayID: [CGDirectDisplayID: CaptureOverlayPanel] = [:]
    private var hudPanel: GifHUDPanel?
    private var keyMonitor: Any?
    private var selectionSession: GifSelectionSession?
    private var captureTask: Task<Void, Never>?
    private var activeEncoder: GifStreamEncoder?
    private var pendingCompletionHandler: ((GifFinalizeResult) -> Void)?

    private init() {}

    var isActive: Bool { phase != .idle }

    func startInteractiveCapture(options overrideOptions: GifRecordingOptions? = nil, onComplete: ((GifFinalizeResult) -> Void)? = nil) {
        if case .recording = phase { hudPanel?.orderFrontRegardless(); return }
        if case .encoding = phase { return }
        cleanupAllResources(discardEncoder: true, animatedHUD: false)
        if let overrideOptions { self.options = overrideOptions }
        self.pendingCompletionHandler = onComplete

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let err = LumakeyError.visionFailed("尚未授予“屏幕录制”权限，请在系统设置 -> 隐私与安全性 -> 屏幕录制 中勾选 Lumakey。")
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
        captureTask?.cancel(); captureTask = nil; activeEncoder = nil; phase = .encoding

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

    func recordAgain() {
        let cb = pendingCompletionHandler; dismissCompletedHUD(immediately: true); startInteractiveCapture(onComplete: cb)
    }

    func copyResultAgain(_ result: GifFinalizeResult) {
        if GifStreamEncoder.copyGifToPasteboard(at: result.fileURL) {
            onStatusMessage?("已重新复制 GIF 动图到剪贴板")
        }
    }

    func saveResultAs(_ result: GifFinalizeResult) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "Lumakey-GIF-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).gif"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dst = panel.url {
            try? FileManager.default.removeItem(at: dst); try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = GifStreamEncoder.copyGifToPasteboard(at: dst)
            onStatusMessage?("GIF 已另存为：\(dst.lastPathComponent)")
        }
    }

    func revealResultInFinder(_ result: GifFinalizeResult) { NSWorkspace.shared.activateFileViewerSelecting([result.fileURL]) }
    func previewResult(_ result: GifFinalizeResult) { NSWorkspace.shared.open(result.fileURL) }

    private func prepareAndPresentSelection() async {
        try? await Task.sleep(for: .milliseconds(100))
        do {
            let topology = try await ScreenTopologyAndWindowMatcher.captureSnapshot()
            let initialPt = topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation)
            let session = GifSelectionSession(topology: topology, initialCursorCanvasPoint: initialPt, options: options)
            presentSelectionOverlays(session: session)
        } catch {
            onStatusMessage?(error.localizedDescription)
        }
    }

    private func presentSelectionOverlays(session: GifSelectionSession) {
        selectionSession = session; phase = .selectingRegion
        selectionPanels.removeAll(); panelByDisplayID.removeAll()
        for slice in session.topology.displays {
            let isKey = slice.displayID == session.activeDisplayID
            let p = GifHUDPanel.presentSelection(
                session: session, slice: slice, makeKey: isKey,
                onStart: { [weak self] in self?.beginRecordingFromSelection() },
                onCancel: { [weak self] in self?.cancelCapture() }
            )
            selectionPanels.append(p)
            panelByDisplayID[slice.displayID] = p
        }
        NSApp.activate(ignoringOtherApps: true)
        panelByDisplayID[session.activeDisplayID]?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            guard let self, let current = self.selectionSession else { return event }
            if event.type == .mouseMoved {
                let prevID = current.activeDisplayID
                current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
                if current.activeDisplayID != prevID { self.panelByDisplayID[current.activeDisplayID]?.makeKey() }
                return event
            }
            if event.type == .rightMouseDown {
                if current.selectionRect != nil {
                    current.selectionRect = nil; current.selectedWindow = nil
                    current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
                } else {
                    self.cancelCapture()
                }
                return nil
            }
            if event.keyCode == 53 { self.cancelCapture(); return nil }
            if event.keyCode == 48 && current.selectionRect == nil { _ = current.cycleHoveredWindow(); return nil }
            if (event.keyCode == 36 || event.keyCode == 76), current.selectionRect != nil {
                self.beginRecordingFromSelection(); return nil
            }
            return event
        }
    }

    private func beginRecordingFromSelection() {
        guard let session = selectionSession, let sel = session.selectionRect?.standardized, sel.width >= 12, sel.height >= 12 else { return }
        options = session.options
        let appKitRegion = session.appKitScreenRect(for: sel)
        let targetSlice = session.topology.targetSlice(forSelection: sel, fallbackPoint: session.cursorPoint) ?? session.topology.displays[0]
        let lockedWindowID = session.selectedWindow?.id
        let cgUnion = session.topology.cgUnionBounds
        let displaySpecs = session.topology.displays.map { (scDisplay: $0.scDisplay, canvasFrame: $0.canvasFrame, scale: $0.scale) }
        let outDims = session.outputDimensions(for: sel)

        closeSelectionPanels()
        elapsedSeconds = 0; encodedFrameCount = 0; mergedFrameCount = 0
        phase = .recording(isPaused: false)
        hudPanel = GifHUDPanel.present(near: appKitRegion, screenFrame: targetSlice.appKitScreen.frame, controller: self)

        let encoder = GifStreamEncoder(options: options)
        activeEncoder = encoder
        let hudWinID = hudPanel.map { CGWindowID($0.windowNumber) }
        captureTask = Task { [weak self] in
            await self?.runCaptureLoop(
                canvasRect: sel, lockedWindowID: lockedWindowID, cgUnion: cgUnion,
                displaySpecs: displaySpecs, outputSize: outDims, hudWindowID: hudWinID, encoder: encoder
            )
        }
    }

    private func runCaptureLoop(
        canvasRect: CGRect,
        lockedWindowID: CGWindowID?,
        cgUnion: CGRect,
        displaySpecs: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        outputSize: (Int, Int),
        hudWindowID: CGWindowID?,
        encoder: GifStreamEncoder
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            cancelCapture(); return
        }
        let excluded = content.windows.filter { hudWindowID != nil && $0.windowID == hudWindowID }
        let singleWindowFilter: SCContentFilter? = lockedWindowID.flatMap { wid in
            content.windows.first(where: { $0.windowID == wid }).map { SCContentFilter(desktopIndependentWindow: $0) }
        }
        let singleDisplayMatch = displaySpecs.first { $0.canvasFrame.insetBy(dx: -0.5, dy: -0.5).contains(canvasRect) }
        let singleDisplayFilter: (SCContentFilter, CGRect)? = singleDisplayMatch.flatMap { spec in
            guard let liveDisp = content.displays.first(where: { $0.displayID == spec.scDisplay.displayID }) else { return nil }
            let localSrc = canvasRect.offsetBy(dx: -spec.canvasFrame.minX, dy: -spec.canvasFrame.minY)
            return (SCContentFilter(display: liveDisp, excludingWindows: excluded), localSrc)
        }

        let nominal = options.frameIntervalSeconds
        var lastUptime: TimeInterval?

        while !Task.isCancelled {
            guard case .recording(let isPaused) = phase else { break }
            if isPaused { lastUptime = nil; try? await Task.sleep(for: .milliseconds(80)); continue }
            let tickStart = ProcessInfo.processInfo.systemUptime

            let frame: CGImage?
            if let winFilter = singleWindowFilter {
                let cfg = SCStreamConfiguration()
                cfg.width = outputSize.0; cfg.height = outputSize.1
                cfg.showsCursor = options.showsCursor; cfg.scalesToFit = true; cfg.ignoreShadowsSingleWindow = true
                frame = try? await SCScreenshotManager.captureImage(contentFilter: winFilter, configuration: cfg)
            } else if let (dispFilter, localSrc) = singleDisplayFilter {
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = localSrc; cfg.width = outputSize.0; cfg.height = outputSize.1
                cfg.showsCursor = options.showsCursor; cfg.scalesToFit = true
                frame = try? await SCScreenshotManager.captureImage(contentFilter: dispFilter, configuration: cfg)
            } else {
                let liveSpecs = displaySpecs.compactMap { spec -> (SCDisplay, CGRect, CGFloat)? in
                    guard let live = content.displays.first(where: { $0.displayID == spec.scDisplay.displayID }) else { return nil }
                    return (live, spec.canvasFrame, spec.scale)
                }
                frame = await ScreenTopologyAndWindowMatcher.captureCrossDisplayRegion(
                    canvasRect: canvasRect, cgUnionBounds: cgUnion, displays: liveSpecs,
                    excludedWindows: excluded, showsCursor: options.showsCursor, outputSize: outputSize
                )
            }

            guard let frame, !Task.isCancelled else {
                try? await Task.sleep(for: .milliseconds(40)); continue
            }
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

    private func closeSelectionPanels() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
        for p in selectionPanels { p.orderOut(nil); p.contentView = nil }
        selectionPanels.removeAll(); panelByDisplayID.removeAll()
        selectionSession = nil
    }

    private func cleanupAllResources(discardEncoder: Bool, animatedHUD: Bool) {
        captureTask?.cancel(); captureTask = nil
        closeSelectionPanels()
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
