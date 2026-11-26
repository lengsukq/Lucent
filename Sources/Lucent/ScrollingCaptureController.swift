import AppKit
import CoreGraphics
import LucentCore
import LucentFoundation
import LucentMedia
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScrollingCaptureState: ObservableObject {
    @Published var pixelWidth: Int = 0
    @Published var pixelHeight: Int = 0
    @Published var segmentCount: Int = 0
    @Published var canUndo: Bool = false
    @Published var previewImage: CGImage?
    @Published var hintMessage: String = L10n.pick("请在选区内缓慢滚动页面 · 回车完成", "Scroll steadily inside region · Return to finish")
}

@MainActor
final class ScrollingCaptureController {
    static let shared = ScrollingCaptureController()

    private var borderPanels: [RecordingRegionBorderPanel] = []
    var hudPanel: NSPanel?
    var previewPanel: NSPanel?
    private var keyMonitor: Any?
    private var samplingTask: Task<Void, Never>?
    private var activeStream: SCStream?
    private var stitcher: ScrollingCaptureStitcher?
    private var state: ScrollingCaptureState?
    private var activeScale: CGFloat = 2.0
    private var activeSelectionAppKitRect: NSRect = .zero

    var onStatusMessage: ((String) -> Void)?

    private init() {}

    func start(
        selectionCanvasRect: CGRect,
        lockedWindowID: CGWindowID?,
        topology: ScreenTopologySnapshot
    ) {
        stopCleanup()
        let appKitRect = topology.appKitGlobalRect(fromCanvas: selectionCanvasRect)
        let scale = topology.effectiveScale(forSelection: selectionCanvasRect)
        activeScale = scale
        activeSelectionAppKitRect = appKitRect

        let newState = ScrollingCaptureState()
        let newStitcher = ScrollingCaptureStitcher(maxPixelHeight: 30_000)
        state = newState
        stitcher = newStitcher

        if let initial = try? ScreenshotCompositor.renderMultiDisplaySelection(
            slices: topology.compositorSlices,
            canvasBounds: topology.canvasBounds,
            selectionRect: selectionCanvasRect,
            annotations: []
        ) {
            _ = newStitcher.pushFrame(initial.image)
            refreshPreviewState()
        }

        borderPanels = RecordingRegionBorderPanel.presentBorders(forAppKitRect: appKitRect)
        presentControlHUD(near: appKitRect, state: newState)
        presentSidePreviewIfFits(near: appKitRect, state: newState)

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleGlobalKey(event) }
        }

        let displaySpecs = topology.displays.compactMap { slice -> (scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)? in
            guard let sc = slice.scDisplay else { return nil }
            return (sc, slice.canvasFrame, slice.scale)
        }
        let outW = max(32, Int(round(selectionCanvasRect.width * scale)))
        let outH = max(48, Int(round(selectionCanvasRect.height * scale)))

        samplingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
                self.finishCancel()
                return
            }
            let hideSelf = GeneralPreferences.load().hideLucentDuringScreenshot
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let allOwnWinIDs = Set(content.windows.filter { $0.owningApplication?.processID == ownPID }.map(\.windowID))
            var chromeWinIDs = Set(self.borderPanels.compactMap { CaptureSelfVisibilityPolicy.validWindowID(from: $0.windowNumber) })
            if let hudID = self.hudPanel.flatMap({ CaptureSelfVisibilityPolicy.validWindowID(from: $0.windowNumber) }) { chromeWinIDs.insert(hudID) }
            if let prevID = self.previewPanel.flatMap({ CaptureSelfVisibilityPolicy.validWindowID(from: $0.windowNumber) }) { chromeWinIDs.insert(prevID) }
            let excludedWinIDs = CaptureSelfVisibilityPolicy.scrollingExcludedWindowIDs(
                hideLucentDuringScreenshot: hideSelf,
                allOwnWindowIDs: allOwnWinIDs,
                chromeWindowIDs: chromeWinIDs
            )
            let started = await ScreenRecordingStreamEngine.startHardwareStreamIfSingleSource(
                canvasRect: selectionCanvasRect, lockedWindowID: lockedWindowID,
                displaySpecs: displaySpecs, excludedWindowIDs: excludedWinIDs,
                fps: 15, maxDimension: 4096, showsCursor: false,
                outputSize: (outW, outH), shareableContent: content
            )
            self.activeStream = started?.stream
            let excludedWins = content.windows.filter { excludedWinIDs.contains($0.windowID) }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let stitcher = self.stitcher else { break }
                let next = await ScreenRecordingStreamEngine.captureNextFrame(
                    streamSink: started?.sink, lockedWindowID: lockedWindowID,
                    canvasRect: selectionCanvasRect, displaySpecs: displaySpecs,
                    shareableContent: content, excludedWindows: excludedWins,
                    showsCursor: false, outputSize: (outW, outH)
                )
                guard let frame = next.image else { continue }
                let outcome = stitcher.pushFrame(frame)
                switch outcome {
                case .initialized, .appendedDown, .appendedUp:
                    self.state?.hintMessage = L10n.pick("正在拼接… 继续滚动或按回车收尾", "Stitching… keep scrolling or press Return")
                    self.refreshPreviewState()
                case .overlapLost:
                    self.state?.hintMessage = L10n.pick("滚动略快未对齐，请稍放慢或按 ⌘Z 撤回上一段", "Scrolled too fast — slow down or press ⌘Z to undo")
                case .reachedMaxHeight:
                    self.state?.hintMessage = L10n.pick("已达最大高度上限，正在完成拼接", "Max height reached — finishing")
                    self.finishCopy()
                    return
                case .unchanged:
                    break
                }
            }
        }
    }

    private func handleGlobalKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if event.keyCode == 53 { finishCancel(); return }
        if event.keyCode == 36 || event.keyCode == 76 { finishCopy(); return }
        if event.keyCode == 6 && mods == [.command] { undoSegment(); return }
        if event.keyCode == 1 && mods == [.command] { finishSave(); return }
        if event.keyCode == 35 && mods.isEmpty { finishPin(); return }
        if event.keyCode == 14 && mods.isEmpty { finishIntoAnnotator(); return }
    }

    func undoSegment() {
        guard let stitcher, stitcher.undoLastSegment() else { return }
        state?.hintMessage = L10n.pick("已撤回最后一段拼接", "Reverted last stitched segment")
        refreshPreviewState()
    }

    func finishCopy() {
        guard let img = stitcher?.makeComposedImage() else { finishCancel(); return }
        let scale = activeScale
        stopCleanup()
        ScreenshotCompositor.copyImageToPasteboard(img, scale: scale, lazy: false)
        _ = try? ScreenshotCompositor.saveTempCapture(img, scale: scale)
        onStatusMessage?(L10n.pick("长截图已复制到剪贴板 (\(img.width)×\(img.height) px)", "Long screenshot copied (\(img.width)×\(img.height) px)"))
    }

    func finishPin() {
        guard let img = stitcher?.makeComposedImage() else { finishCancel(); return }
        let scale = activeScale
        stopCleanup()
        if let url = try? ScreenshotCompositor.saveTempCapture(img, scale: scale) {
            ScreenshotCompositor.copyImageToPasteboard(img, scale: scale, lazy: false)
            PinWindowController.shared.pinImage(at: url)
            onStatusMessage?(L10n.pick("长截图已钉在屏幕并复制到剪贴板", "Long screenshot pinned & copied"))
        }
    }

    func finishIntoAnnotator() {
        guard let img = stitcher?.makeComposedImage() else { finishCancel(); return }
        let scale = activeScale
        let rect = activeSelectionAppKitRect
        stopCleanup()
        guard let url = try? ScreenshotCompositor.saveTempCapture(img, scale: scale) else { return }
        let logicalW = max(180, min(CGFloat(img.width) / max(scale, 1), 640))
        let ratio = CGFloat(img.width) / max(CGFloat(img.height), 1)
        let visible = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let logicalH = min(max(160, logicalW / max(ratio, 0.08)), visible.height * 0.84)
        let finalW = min(logicalW, logicalH * ratio)
        let pinFrame = NSRect(x: rect.midX - finalW / 2, y: visible.midY - logicalH / 2, width: max(140, finalW), height: logicalH)
        PinWindowController.shared.pinImage(at: url, screenRect: pinFrame)
        if let lastPin = PinWindowController.shared.managedPins.last {
            PinWindowController.shared.beginInPlaceAnnotationEdit(for: lastPin)
        }
    }

    func finishSave() {
        guard let img = stitcher?.makeComposedImage() else { finishCancel(); return }
        let scale = activeScale
        stopCleanup()
        var prefs = GeneralPreferences.load()
        let fmt = prefs.captureExportFormat
        let saveDir = prefs.resolvedCaptureSaveDirectory()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let base = CaptureFileNameFormatter.formatBaseName(template: prefs.captureFileNameTemplate, appName: "LongShot")
        ScreenshotCompositor.copyImageToPasteboard(img, scale: scale, lazy: false)
        if prefs.quickSaveCaptureWithoutDialog {
            let dst = CaptureFileNameFormatter.uniqueFileURL(in: saveDir, baseName: base, format: fmt)
            try? ScreenshotCompositor.writeEncodedImage(img, scale: scale, format: fmt, to: dst)
            QuickSaveRevealToast.present(savedURL: dst)
            onStatusMessage?(L10n.pick("长截图已保存：\(dst.lastPathComponent)", "Saved long screenshot: \(dst.lastPathComponent)"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fmt.utType]
        panel.directoryURL = !prefs.lastCaptureSavePanelDirectoryPath.isEmpty
            ? URL(fileURLWithPath: prefs.lastCaptureSavePanelDirectoryPath, isDirectory: true)
            : saveDir
        panel.nameFieldStringValue = "\(base).\(fmt.fileExtension)"
        if panel.runModal() == .OK, let dst = panel.url {
            prefs.lastCaptureSavePanelDirectoryPath = dst.deletingLastPathComponent().standardizedFileURL.path
            prefs.save()
            try? ScreenshotCompositor.writeEncodedImage(img, scale: scale, format: fmt, to: dst)
            onStatusMessage?(L10n.pick("长截图已另存为：\(dst.lastPathComponent)", "Saved long screenshot: \(dst.lastPathComponent)"))
        }
    }

    func finishCancel() {
        stopCleanup()
    }

    private func refreshPreviewState() {
        guard let stitcher, let state else { return }
        let composed = stitcher.makeComposedImage()
        state.pixelWidth = composed?.width ?? stitcher.width
        state.pixelHeight = composed?.height ?? stitcher.stitchedRows
        state.segmentCount = stitcher.segmentCount
        state.canUndo = stitcher.canUndo
        state.previewImage = composed
    }

    private func stopCleanup() {
        samplingTask?.cancel(); samplingTask = nil
        if let stream = activeStream {
            activeStream = nil
            Task { try? await stream.stopCapture() }
        }
        if let mon = keyMonitor { NSEvent.removeMonitor(mon); keyMonitor = nil }
        for p in borderPanels { p.contentView = nil; p.close() }
        borderPanels.removeAll()
        hudPanel?.contentView = nil; hudPanel?.close(); hudPanel = nil
        previewPanel?.contentView = nil; previewPanel?.close(); previewPanel = nil
        stitcher = nil; state = nil
        MemoryStats.reclaimFreeHeapPages()
    }
}
