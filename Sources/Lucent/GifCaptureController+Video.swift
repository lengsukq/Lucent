import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import LucentCore
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

extension GifCaptureController {
    func beginVideoRecordingFromSelection(session: GifSelectionSession, selection: CGRect) {
        var prefs = GeneralPreferences.load()
        videoOptions = session.videoOptions
        if prefs.videoDefaultOptions != session.videoOptions {
            prefs.videoDefaultOptions = session.videoOptions
            prefs.save()
        }

        let appKitRegion = session.appKitScreenRect(for: selection)
        let targetSlice = session.topology.targetSlice(forSelection: selection, fallbackPoint: session.cursorPoint)
            ?? session.topology.displays[0]
        let lockedWindowID = session.selectedWindow?.id
        let displaySpecs = session.topology.displays.compactMap { s in
            s.scDisplay.map { (scDisplay: $0, canvasFrame: s.canvasFrame, scale: s.scale) }
        }
        let outDims = session.outputDimensions(for: selection)

        let encoder = VideoStreamEncoder(options: videoOptions, outputSize: outDims)
        do {
            try encoder.prepare()
        } catch {
            cancelCapture()
            onStatusMessage?(error.localizedDescription)
            return
        }

        let clock = ActiveRecordingClock()
        activeVideoEncoder = encoder
        activeVideoClock = clock

        closeSelectionPanels()
        elapsedSeconds = 0
        encodedFrameCount = 0
        mergedFrameCount = 0
        phase = .recording(isPaused: false)
        if lockedWindowID == nil {
            borderPanels = RecordingRegionBorderPanel.presentBorders(forAppKitRect: appKitRegion)
        }
        hudPanel = GifHUDPanel.present(near: appKitRegion, visibleFrame: targetSlice.appKitScreen.visibleFrame, controller: self)

        var excludedIDs = Set(borderPanels.compactMap { CaptureSelfVisibilityPolicy.validWindowID(from: $0.windowNumber) })
        if let hudID = hudPanel.flatMap({ CaptureSelfVisibilityPolicy.validWindowID(from: $0.windowNumber) }) { excludedIDs.insert(hudID) }
        let opts = videoOptions

        captureTask = Task { [weak self] in
            await self?.runVideoCaptureLoop(
                canvasRect: selection,
                lockedWindowID: lockedWindowID,
                displaySpecs: displaySpecs,
                outputSize: outDims,
                excludedWindowIDs: excludedIDs,
                options: opts,
                encoder: encoder,
                clock: clock
            )
        }
    }

    private func runVideoCaptureLoop(
        canvasRect: CGRect,
        lockedWindowID: CGWindowID?,
        displaySpecs: [(scDisplay: SCDisplay, canvasFrame: CGRect, scale: CGFloat)],
        outputSize: (Int, Int),
        excludedWindowIDs: Set<CGWindowID>,
        options: VideoRecordingOptions,
        encoder: VideoStreamEncoder,
        clock: ActiveRecordingClock
    ) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            cancelCapture(); return
        }
        let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let videoHandler: @Sendable (CVPixelBuffer, Double) -> Void = { pb, ts in
            guard let t = clock.currentElapsed(at: ts) else { return }
            _ = encoder.appendPixelBuffer(pb, presentationSeconds: t)
        }
        var audioHandler: (@Sendable (CMSampleBuffer, Double) -> Void)?
        if options.captureAudio {
            audioHandler = { sb, ts in
                guard let t = clock.currentElapsed(at: ts) else { return }
                _ = encoder.appendAudioSampleBuffer(sb, presentationSeconds: t)
            }
        }
        let streamPair = await ScreenRecordingStreamEngine.startHardwareStreamIfSingleSource(
            canvasRect: canvasRect,
            lockedWindowID: lockedWindowID,
            displaySpecs: displaySpecs,
            excludedWindowIDs: excludedWindowIDs,
            fps: options.fps,
            maxDimension: options.maxDimension,
            showsCursor: options.showsCursor,
            captureAudio: options.captureAudio,
            evenOutputDimensions: true,
            outputSize: outputSize,
            shareableContent: content,
            onVideoSampleBuffer: videoHandler,
            onAudioSampleBuffer: audioHandler
        )
        activeVideoStream = streamPair?.stream

        if let sink = streamPair?.sink {
            while !Task.isCancelled {
                guard case .recording(let paused) = phase else { break }
                if sink.snapshotLatest().error != nil {
                    if encoder.encodedFrameCount > 0 { finishVideoRecording() } else { cancelCapture() }
                    return
                }
                if !paused {
                    elapsedSeconds = clock.currentElapsed() ?? encoder.totalDurationSeconds
                    encodedFrameCount = encoder.encodedFrameCount
                    if elapsedSeconds >= Double(options.maxDurationSeconds) {
                        finishVideoRecording(); return
                    }
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            return
        }

        // Multi-display cross-screen fallback loop
        let nominal = options.frameIntervalSeconds
        while !Task.isCancelled {
            guard case .recording(let paused) = phase else { break }
            if paused { try? await Task.sleep(for: .milliseconds(80)); continue }
            let tickStart = ProcessInfo.processInfo.systemUptime
            let next = await ScreenRecordingStreamEngine.captureNextFrame(
                streamSink: nil,
                lockedWindowID: lockedWindowID,
                canvasRect: canvasRect,
                displaySpecs: displaySpecs,
                shareableContent: content,
                excludedWindows: excluded,
                showsCursor: options.showsCursor,
                outputSize: outputSize
            )
            if next.fatalError {
                if encoder.encodedFrameCount > 0 { finishVideoRecording() } else { cancelCapture() }
                return
            }
            if let frame = next.image, let t = clock.currentElapsed() {
                let stats = await Task.detached(priority: .userInitiated) {
                    _ = encoder.appendImage(frame, presentationSeconds: t)
                    return (encoder.encodedFrameCount, encoder.totalDurationSeconds)
                }.value
                encodedFrameCount = stats.0
                elapsedSeconds = max(t, stats.1)
                if elapsedSeconds >= Double(options.maxDurationSeconds) { finishVideoRecording(); return }
            }
            let waitMs = max(5, Int(((nominal - (ProcessInfo.processInfo.systemUptime - tickStart)) * 1000).rounded()))
            try? await Task.sleep(for: .milliseconds(waitMs))
        }
    }

    func finishVideoRecording() {
        guard case .recording = phase, let encoder = activeVideoEncoder else { return }
        activeVideoClock?.setPaused(true)
        activeVideoClock = nil
        captureTask?.cancel(); captureTask = nil
        activeVideoEncoder = nil
        let stoppingStream = activeVideoStream
        activeVideoStream = nil
        closeBorderPanels()
        phase = .encoding

        Task { [weak self] in
            if let stoppingStream { try? await stoppingStream.stopCapture() }
            guard let self else { return }
            do {
                let result = try await encoder.finalize()
                _ = VideoStreamEncoder.copyVideoToPasteboard(at: result.fileURL)
                self.latestVideoResult = result
                self.phase = .completedVideo(result)
                let sizeStr = FastFormatters.formatFileBytes(result.fileSizeBytes)
                self.onStatusMessage?(L10n.pick(
                    "MP4 区域录像已复制 (\(sizeStr) · \(result.frameCount) 帧)，可直接 ⌘V 粘贴",
                    "MP4 recording copied (\(sizeStr) · \(result.frameCount) frames), ready for ⌘V"
                ))
                self.onVideoRecordingCompleted?(result)
                self.pendingVideoCompletionHandler?(result)
                self.pendingVideoCompletionHandler = nil
            } catch {
                self.cleanupAllResources(discardEncoder: false, animatedHUD: true)
                self.phase = .idle
                self.onStatusMessage?(error.localizedDescription)
            }
        }
    }
}
