import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import LucentCore
@preconcurrency import ScreenCaptureKit
import SwiftUI
import VideoToolbox

final class RecordingRegionBorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    static func presentBorders(forAppKitRect region: NSRect) -> [RecordingRegionBorderPanel] {
        let expanded = region.insetBy(dx: -3, dy: -3)
        var panels: [RecordingRegionBorderPanel] = []
        for screen in NSScreen.screens {
            let inter = screen.frame.intersection(expanded)
            guard !inter.isNull, inter.width >= 6, inter.height >= 6 else { continue }
            let panel = RecordingRegionBorderPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            let localRect = NSRect(
                x: expanded.minX - screen.frame.minX,
                y: screen.frame.maxY - expanded.maxY,
                width: expanded.width,
                height: expanded.height
            )
            panel.contentView = NSHostingView(rootView: RecordingRegionBorderView(
                localRect: localRect, screenSize: screen.frame.size
            ))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        return panels
    }
}

private struct RecordingRegionBorderView: View {
    let localRect: CGRect
    let screenSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    Color(red: 1.0, green: 0.27, blue: 0.25).opacity(0.88),
                    style: StrokeStyle(lineWidth: 1.8, dash: [6, 4])
                )
                .frame(width: localRect.width, height: localRect.height)
                .position(x: localRect.midX, y: localRect.midY)
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }
}

final class ActiveRecordingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var accumulated: Double = 0
    private var activeSegmentStart: Double?

    func currentElapsed(at hostSeconds: Double = ProcessInfo.processInfo.systemUptime) -> Double? {
        lock.withLock {
            guard !paused else { return nil }
            if let start = activeSegmentStart {
                return accumulated + max(0, hostSeconds - start)
            }
            activeSegmentStart = hostSeconds
            return accumulated
        }
    }

    func setPaused(_ isPaused: Bool, at hostSeconds: Double = ProcessInfo.processInfo.systemUptime) {
        lock.withLock {
            guard paused != isPaused else { return }
            if isPaused {
                if let start = activeSegmentStart {
                    accumulated += max(0, hostSeconds - start)
                    activeSegmentStart = nil
                }
                paused = true
            } else {
                paused = false
                activeSegmentStart = hostSeconds
            }
        }
    }
}

final class ScreenStreamFrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latestFrame: CGImage?
    private var streamError: Error?
    private let onVideoSampleBuffer: (@Sendable (CVPixelBuffer, Double) -> Void)?
    private let onAudioSampleBuffer: (@Sendable (CMSampleBuffer, Double) -> Void)?

    init(
        onVideoSampleBuffer: (@Sendable (CVPixelBuffer, Double) -> Void)? = nil,
        onAudioSampleBuffer: (@Sendable (CMSampleBuffer, Double) -> Void)? = nil
    ) {
        self.onVideoSampleBuffer = onVideoSampleBuffer
        self.onAudioSampleBuffer = onAudioSampleBuffer
        super.init()
    }

    func snapshotLatest() -> (image: CGImage?, error: Error?) {
        lock.withLock { (latestFrame, streamError) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        if outputType == .audio {
            onAudioSampleBuffer?(sampleBuffer, ProcessInfo.processInfo.systemUptime)
            return
        }
        guard outputType == .screen else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let first = attachments.first,
           let rawStatus = first[.status] as? Int,
           let status = SCFrameStatus(rawValue: rawStatus),
           status != .complete {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let onVideoSampleBuffer {
            onVideoSampleBuffer(pixelBuffer, ProcessInfo.processInfo.systemUptime)
            return
        }
        var cgImage: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage) == noErr,
              let resolved = cgImage else { return }
        lock.withLock { latestFrame = resolved }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock { streamError = error }
    }
}

@MainActor
enum ScreenRecordingStreamEngine {
    static func startHardwareStreamIfSingleSource(
        canvasRect: CGRect,
        lockedWindowID: CGWindowID?,
        displaySpecs: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        excludedWindowIDs: Set<CGWindowID>,
        fps: Int,
        maxDimension: Int,
        showsCursor: Bool,
        captureAudio: Bool = false,
        evenOutputDimensions: Bool = false,
        outputSize: (Int, Int),
        shareableContent: SCShareableContent,
        onVideoSampleBuffer: (@Sendable (CVPixelBuffer, Double) -> Void)? = nil,
        onAudioSampleBuffer: (@Sendable (CMSampleBuffer, Double) -> Void)? = nil
    ) async -> (stream: SCStream, sink: ScreenStreamFrameSink)? {
        let excludedWins = shareableContent.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let cfg = SCStreamConfiguration()
        cfg.width = evenOutputDimensions ? max(16, outputSize.0 & ~1) : max(2, outputSize.0)
        cfg.height = evenOutputDimensions ? max(16, outputSize.1 & ~1) : max(2, outputSize.1)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        cfg.queueDepth = 6
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = showsCursor
        cfg.scalesToFit = true
        cfg.captureResolution = .best
        cfg.capturesAudio = captureAudio
        if captureAudio {
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 48_000
            cfg.channelCount = 2
        }

        let filter: SCContentFilter
        if let wid = lockedWindowID,
           let scWin = shareableContent.windows.first(where: { $0.windowID == wid }) {
            filter = SCContentFilter(desktopIndependentWindow: scWin)
            let nativeScale = CGFloat(filter.pointPixelScale)
            let winScale = nativeScale >= 1.0 ? nativeScale : (displaySpecs.map(\.scale).max() ?? 2.0)
            if let winSize = CaptureSelectionGeometry.resolvedWindowCaptureSize(
                filterContentRect: filter.contentRect, fallbackWindowFrame: scWin.frame, minimumPoints: 12
            ) {
                let rawW = max(2, Int(round(winSize.width * winScale)))
                let rawH = max(2, Int(round(winSize.height * winScale)))
                let scaled = evenOutputDimensions
                    ? VideoRecordingOptions.evenScaledDimensions(width: rawW, height: rawH, maxDimension: maxDimension)
                    : GifStreamEncoder.scaledDimensions(width: rawW, height: rawH, maxDimension: maxDimension)
                cfg.width = scaled.0
                cfg.height = scaled.1
            }
            cfg.ignoreShadowsSingleWindow = true
        } else {
            let intersecting = displaySpecs.filter {
                let inter = $0.canvasFrame.intersection(canvasRect.standardized)
                return !inter.isNull && inter.width >= 1 && inter.height >= 1
            }
            guard intersecting.count == 1,
                  let spec = intersecting.first,
                  spec.canvasFrame.insetBy(dx: -1.0, dy: -1.0).contains(canvasRect.standardized),
                  let liveDisp = shareableContent.displays.first(where: { $0.displayID == spec.scDisplay.displayID }),
                  let clampedLocal = MultiDisplayLayout.clampedLocalSourceRect(forSelection: canvasRect, in: spec.canvasFrame) else {
                return nil
            }
            let liveBounds = CGRect(x: 0, y: 0, width: CGFloat(liveDisp.width), height: CGFloat(liveDisp.height))
            let safeSource = clampedLocal.intersection(liveBounds)
            guard !safeSource.isNull, safeSource.width >= 2, safeSource.height >= 2 else { return nil }
            cfg.sourceRect = safeSource
            filter = SCContentFilter(display: liveDisp, excludingWindows: excludedWins)
        }

        let sink = ScreenStreamFrameSink(onVideoSampleBuffer: onVideoSampleBuffer, onAudioSampleBuffer: onAudioSampleBuffer)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: sink)
        let sampleQueue = DispatchQueue(label: "app.lucent.capture.scstream", qos: .userInitiated)
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sampleQueue)
            if captureAudio {
                let audioQueue = DispatchQueue(label: "app.lucent.capture.scstream.audio", qos: .userInitiated)
                try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: audioQueue)
            }
            try await stream.startCapture()
            return (stream, sink)
        } catch {
            return nil
        }
    }

    @MainActor
    static func captureNextFrame(
        streamSink: ScreenStreamFrameSink?,
        lockedWindowID: CGWindowID?,
        canvasRect: CGRect,
        displaySpecs: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        shareableContent: SCShareableContent,
        excludedWindows: [SCWindow],
        showsCursor: Bool,
        outputSize: (Int, Int)
    ) async -> (image: CGImage?, fatalError: Bool) {
        if let sink = streamSink {
            let snap = sink.snapshotLatest()
            return (snap.image, snap.error != nil)
        }
        if let wid = lockedWindowID,
           let winCap = try? await ScreenTopologyAndWindowMatcher.captureIndependentWindowImage(
               windowID: wid, ignoreShadow: true, fallbackScale: displaySpecs.map(\.scale).max() ?? 2.0
           ) {
            return (winCap.image, false)
        }
        let liveSpecs = displaySpecs.compactMap { spec -> (SCDisplay, CGRect, CGFloat)? in
            guard let live = shareableContent.displays.first(where: { $0.displayID == spec.scDisplay.displayID }) else { return nil }
            return (live, spec.canvasFrame, spec.scale)
        }
        let cross = await ScreenTopologyAndWindowMatcher.captureCrossDisplayRegion(
            canvasRect: canvasRect, displays: liveSpecs,
            excludedWindows: excludedWindows, showsCursor: showsCursor, outputSize: outputSize
        )
        return (cross, false)
    }
}
