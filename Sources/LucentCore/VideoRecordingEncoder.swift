import LucentFoundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

public final class VideoStreamEncoder: @unchecked Sendable {
    public let options: VideoRecordingOptions
    public let outputURL: URL
    public let pixelSize: (width: Int, height: Int)

    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var finished = false
    private var frameCount = 0
    private var hasRecordedAudio = false
    private var durationSum: Double = 0
    private var lastVideoPTS: CMTime?
    private var lastAudioPTS: CMTime?

    public static func defaultOutputDirectory(tempRoot: URL = FileManager.default.temporaryDirectory) -> URL {
        tempRoot.appendingPathComponent("lucent-videos", isDirectory: true)
    }

    public init(
        options: VideoRecordingOptions = VideoRecordingOptions(),
        outputSize: (Int, Int),
        outputURL: URL? = nil
    ) {
        self.options = options
        self.pixelSize = (max(16, outputSize.0 & ~1), max(16, outputSize.1 & ~1))
        if let outputURL {
            try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.outputURL = outputURL
        } else {
            let dir = Self.defaultOutputDirectory()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.outputURL = dir.appendingPathComponent("lucent-video-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).mp4")
        }
    }

    public var encodedFrameCount: Int { lock.withLock { frameCount } }
    public var totalDurationSeconds: Double { lock.withLock { durationSum } }

    public func prepare() throws {
        try lock.withLock {
            if writer != nil { return }
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let assetWriter: AVAssetWriter
            do {
                assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            } catch {
                throw VideoEncoderError.writerInitializationFailed(error.localizedDescription)
            }

            let w = pixelSize.width
            let h = pixelSize.height
            let targetBitrate = max(2_500_000, min(28_000_000, Int(Double(w * h) * Double(options.fps) * 0.14)))
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: targetBitrate,
                    AVVideoExpectedSourceFrameRateKey: options.fps,
                    AVVideoMaxKeyFrameIntervalKey: options.fps * 2,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true
            let poolAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput, sourcePixelBufferAttributes: poolAttrs)
            guard assetWriter.canAdd(vInput) else {
                throw VideoEncoderError.writerInitializationFailed("canAdd videoInput == false")
            }
            assetWriter.add(vInput)

            var aInput: AVAssetWriterInput?
            if options.captureAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
                let candidate = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                candidate.expectsMediaDataInRealTime = true
                if assetWriter.canAdd(candidate) {
                    assetWriter.add(candidate)
                    aInput = candidate
                }
            }

            guard assetWriter.startWriting() else {
                throw VideoEncoderError.writerInitializationFailed(assetWriter.error?.localizedDescription ?? "startWriting")
            }
            self.writer = assetWriter
            self.videoInput = vInput
            self.audioInput = aInput
            self.pixelAdaptor = adaptor
        }
    }

    @discardableResult
    public func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationSeconds: Double) -> Bool {
        let bufW = CVPixelBufferGetWidth(pixelBuffer)
        let bufH = CVPixelBufferGetHeight(pixelBuffer)
        let bufFmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if bufW != pixelSize.width || bufH != pixelSize.height || bufFmt != kCVPixelFormatType_32BGRA {
            var cgImage: CGImage?
            guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage) == noErr,
                  let resolved = cgImage else { return false }
            return appendImage(resolved, presentationSeconds: presentationSeconds)
        }
        return lock.withLock {
            guard !finished, let writer, let vInput = videoInput, let adaptor = pixelAdaptor,
                  writer.status == .writing else { return false }
            let pts = nextVideoPTS(seconds: presentationSeconds)
            ensureSessionStarted(writer: writer)
            guard vInput.isReadyForMoreMediaData else { return false }
            guard adaptor.append(pixelBuffer, withPresentationTime: pts) else { return false }
            lastVideoPTS = pts
            frameCount += 1
            durationSum = max(durationSum, pts.seconds)
            return true
        }
    }

    @discardableResult
    public func appendImage(_ image: CGImage, presentationSeconds: Double) -> Bool {
        lock.withLock {
            guard !finished, let writer, let vInput = videoInput, let adaptor = pixelAdaptor,
                  writer.status == .writing else { return false }
            let pts = nextVideoPTS(seconds: presentationSeconds)
            ensureSessionStarted(writer: writer)
            guard vInput.isReadyForMoreMediaData,
                  let pool = adaptor.pixelBufferPool else { return false }
            var outBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer) == kCVReturnSuccess,
                  let target = outBuffer else { return false }
            CVPixelBufferLockBaseAddress(target, [])
            defer { CVPixelBufferUnlockBaseAddress(target, []) }
            let w = pixelSize.width, h = pixelSize.height
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(target),
                width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(target),
                space: srgb, bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard adaptor.append(target, withPresentationTime: pts) else { return false }
            lastVideoPTS = pts
            frameCount += 1
            durationSum = max(durationSum, pts.seconds)
            return true
        }
    }

    @discardableResult
    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, presentationSeconds: Double) -> Bool {
        lock.withLock {
            guard !finished, sessionStarted, let writer, let aInput = audioInput,
                  writer.status == .writing, aInput.isReadyForMoreMediaData else { return false }
            let rawPTS = CMTime(seconds: max(0, presentationSeconds), preferredTimescale: 48_000)
            let pts: CMTime
            if let prev = lastAudioPTS, rawPTS <= prev {
                pts = CMTimeAdd(prev, CMTime(value: 1, timescale: 48_000))
            } else {
                pts = rawPTS
            }
            var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
            var rebased: CMSampleBuffer?
            guard CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &rebased
            ) == noErr, let outSample = rebased else { return false }
            guard aInput.append(outSample) else { return false }
            lastAudioPTS = CMTimeAdd(pts, timing.duration.isValid ? timing.duration : CMTime(value: 1, timescale: 48_000))
            hasRecordedAudio = true
            return true
        }
    }

    public func finalize() async throws -> VideoFinalizeResult {
        let state = lock.withLock { () -> (AVAssetWriter?, AVAssetWriterInput?, AVAssetWriterInput?, Int, Double, Bool) in
            finished = true
            return (writer, videoInput, audioInput, frameCount, durationSum, hasRecordedAudio)
        }
        guard state.3 > 0, let writer = state.0 else {
            discard()
            throw VideoEncoderError.emptyRecording
        }
        state.1?.markAsFinished()
        state.2?.markAsFinished()
        nonisolated(unsafe) let finishingWriter = writer
        await withCheckedContinuation { cont in
            finishingWriter.finishWriting { cont.resume() }
        }
        if finishingWriter.status != .completed {
            let reason = finishingWriter.error?.localizedDescription ?? outputURL.lastPathComponent
            try? FileManager.default.removeItem(at: outputURL)
            throw VideoEncoderError.finalizationFailed(reason)
        }
        let bytes = Int64((try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return VideoFinalizeResult(
            fileURL: outputURL,
            frameCount: state.3,
            durationSeconds: state.4,
            fileSizeBytes: bytes,
            pixelSize: CGSize(width: pixelSize.width, height: pixelSize.height),
            hasAudio: state.5
        )
    }

    public func discard() {
        let existingWriter = lock.withLock { () -> AVAssetWriter? in
            finished = true
            let w = writer
            writer = nil; videoInput = nil; audioInput = nil; pixelAdaptor = nil
            frameCount = 0; durationSum = 0; lastVideoPTS = nil; lastAudioPTS = nil; sessionStarted = false
            return w
        }
        existingWriter?.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
    }

    @MainActor
    @discardableResult
    public static func copyVideoToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        ClipboardPasteboardIO.writeFileURLsToPasteboard([url], to: pasteboard)
    }

    private func ensureSessionStarted(writer: AVAssetWriter) {
        if !sessionStarted {
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
    }

    private func nextVideoPTS(seconds: Double) -> CMTime {
        if lastVideoPTS == nil { return .zero }
        let raw = CMTime(seconds: max(0.001, seconds), preferredTimescale: 600)
        if let prev = lastVideoPTS, raw <= prev {
            return CMTimeAdd(prev, CMTime(value: 1, timescale: 600))
        }
        return raw
    }
}
