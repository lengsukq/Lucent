import AVFoundation
import CoreMedia
import Foundation
import LucentFoundation
import LucentSearch
import VideoToolbox

public struct VideoStreamMetadata: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public let fps: Double
    public let codecBadge: String
    public let isAudioOnly: Bool

    public init(width: Int, height: Int, fps: Double, codecBadge: String, isAudioOnly: Bool = false) {
        self.width = width
        self.height = height
        self.fps = fps
        self.codecBadge = codecBadge
        self.isAudioOnly = isAudioOnly
    }

    public var resolutionLabel: String {
        if isAudioOnly { return "AUDIO" }
        if width >= 3800 || height >= 2100 { return "4K" }
        if width >= 1900 || height >= 1070 { return "1080P" }
        if width > 0 && height > 0 { return "\(width)×\(height)" }
        return "HD"
    }
}

public enum ResolvedVideoPlayback: @unchecked Sendable {
    case ready(item: AVPlayerItem, metadata: VideoStreamMetadata, tempFileURL: URL?)
    case unsupported(reason: String)
}

public enum VideoPlaybackCompat {
    private static let registerDecodersOnce: Void = {
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
    }()

    private static let nativeCopyableVideoCodecs: Set<String> = [
        "h264", "avc1", "hevc", "h265", "av1", "vp9", "mpeg4", "prores", "mjpeg"
    ]

    private static let nativeCopyableAudioCodecs: Set<String> = [
        "aac", "mp3", "ac3", "eac3", "alac", "flac", "opus", "pcm_s16le", "pcm_s24le", "pcm_f32le"
    ]

    public static func ensureSystemDecodersRegistered() {
        _ = registerDecodersOnce
    }

    public static var tempDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lucent-cinema", isDirectory: true)
    }

    public static func preparePlayback(for url: URL, allowFFmpegRemux: Bool = true) async -> ResolvedVideoPlayback {
        ensureSystemDecodersRegistered()

        let nativeAsset = AVURLAsset(url: url)
        if let meta = await inspectDecodableMedia(in: nativeAsset, badgeSuffix: "原生直开") {
            return .ready(item: AVPlayerItem(asset: nativeAsset), metadata: meta, tempFileURL: nil)
        }

        let scan = await Task.detached(priority: .userInitiated) {
            Hev1ResourceLoader.findHev1SampleEntryOffsets(in: url)
        }.value
        if !scan.offsets.isEmpty,
           let patchedAsset = Hev1ResourceLoader.makePatchedAsset(fileURL: url, fileSize: scan.fileSize, patchOffsets: scan.offsets),
           let meta = await inspectDecodableMedia(in: patchedAsset, badgeSuffix: "HEVC · 硬解直开") {
            return .ready(item: AVPlayerItem(asset: patchedAsset), metadata: meta, tempFileURL: nil)
        }

        if allowFFmpegRemux, let ffmpegPath = HostToolingStatus.detect().ffmpegPath {
            let isAudioExt = MediaClassifier.classify(url: url, isDirectory: false) == .audio
            if let remuxedURL = await remuxToFastContainer(sourceURL: url, ffmpegPath: ffmpegPath, audioOnly: isAudioExt) {
                let remuxAsset = AVURLAsset(url: remuxedURL)
                if let meta = await inspectDecodableMedia(in: remuxAsset, badgeSuffix: isAudioExt ? "音频快转" : "兼容快封 · 硬解") {
                    return .ready(item: AVPlayerItem(asset: remuxAsset), metadata: meta, tempFileURL: remuxedURL)
                }
                try? FileManager.default.removeItem(at: remuxedURL)
            }
        }
        return .unsupported(reason: "当前媒体封装或编码超出 macOS 原生解码范围，建议使用外部播放器打开。")
    }

    public static func cleanupTempDirectory() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    private static func inspectDecodableMedia(in asset: AVURLAsset, badgeSuffix: String) async -> VideoStreamMetadata? {
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        if !videoTracks.isEmpty {
            var bestMeta: VideoStreamMetadata?
            for track in videoTracks {
                guard let (decodable, playable, size, rawFPS) = try? await track.load(
                    .isDecodable, .isPlayable, .naturalSize, .nominalFrameRate
                ), decodable && playable else { continue }

                let fps = Double(rawFPS)
                let w = Int(abs(size.width)), h = Int(abs(size.height))
                let tempMeta = VideoStreamMetadata(width: w, height: h, fps: fps, codecBadge: "")
                let candidate = VideoStreamMetadata(width: w, height: h, fps: fps, codecBadge: "\(tempMeta.resolutionLabel) \(badgeSuffix)")
                if bestMeta == nil || (fps > 0 && (bestMeta?.fps ?? 0) == 0) || (w * h > (bestMeta?.width ?? 0) * (bestMeta?.height ?? 0)) {
                    bestMeta = candidate
                }
            }
            return bestMeta
        }

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        for track in audioTracks {
            if let (decodable, playable) = try? await track.load(.isDecodable, .isPlayable), decodable && playable {
                let extUpper = asset.url.pathExtension.uppercased()
                let label = extUpper.isEmpty ? "音频" : extUpper
                return VideoStreamMetadata(width: 0, height: 0, fps: 0, codecBadge: "\(label) · \(badgeSuffix)", isAudioOnly: true)
            }
        }
        return nil
    }

    private static func remuxToFastContainer(sourceURL: URL, ffmpegPath: String, audioOnly: Bool) async -> URL? {
        let probePath = HostToolingStatus.detect().ffprobePath
        return await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            if audioOnly {
                let destURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).m4a")
                let args = ["-y", "-nostdin", "-loglevel", "error", "-i", sourceURL.path, "-vn", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", destURL.path]
                guard let res = try? ProcessSupervisor.shared.run(executableURL: URL(fileURLWithPath: ffmpegPath), arguments: args, timeoutSeconds: 60, maxOutputBytes: 4096),
                      res.exitCode == 0, FileManager.default.fileExists(atPath: destURL.path) else {
                    try? FileManager.default.removeItem(at: destURL)
                    return nil
                }
                return destURL
            }

            let destURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).mp4")
            let codecs = probeStreamCodecs(sourceURL: sourceURL, ffprobePath: probePath, ffmpegPath: ffmpegPath)
            if runFFmpegAttempt(sourceURL: sourceURL, destURL: destURL, ffmpegPath: ffmpegPath, codecs: codecs, forceTranscode: false) {
                return destURL
            }
            if nativeCopyableVideoCodecs.contains(codecs.video),
               runFFmpegAttempt(sourceURL: sourceURL, destURL: destURL, ffmpegPath: ffmpegPath, codecs: codecs, forceTranscode: true) {
                return destURL
            }
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }.value
    }

    private static func runFFmpegAttempt(
        sourceURL: URL, destURL: URL, ffmpegPath: String, codecs: (video: String, audio: String), forceTranscode: Bool
    ) -> Bool {
        var args = ["-y", "-nostdin", "-loglevel", "error", "-i", sourceURL.path, "-map", "0:v:0", "-map", "0:a:0?"]
        if !forceTranscode && nativeCopyableVideoCodecs.contains(codecs.video) {
            args += ["-c:v", "copy"]
            if codecs.video == "hevc" || codecs.video == "h265" { args += ["-tag:v", "hvc1"] }
        } else {
            args += ["-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p"]
        }
        if !forceTranscode && (codecs.audio.isEmpty || nativeCopyableAudioCodecs.contains(codecs.audio)) {
            args += ["-c:a", "copy"]
        } else {
            args += ["-c:a", "aac", "-b:a", "192k"]
        }
        args += ["-movflags", "+faststart", destURL.path]

        guard let res = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: ffmpegPath), arguments: args, timeoutSeconds: 90, maxOutputBytes: 4096
        ), res.exitCode == 0, FileManager.default.fileExists(atPath: destURL.path) else {
            try? FileManager.default.removeItem(at: destURL)
            return false
        }
        return true
    }

    private static func probeStreamCodecs(sourceURL: URL, ffprobePath: String?, ffmpegPath: String) -> (video: String, audio: String) {
        if let ffprobePath {
            let url = URL(fileURLWithPath: ffprobePath)
            let vRes = try? ProcessSupervisor.shared.run(executableURL: url, arguments: ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", sourceURL.path], timeoutSeconds: 5, maxOutputBytes: 128)
            let aRes = try? ProcessSupervisor.shared.run(executableURL: url, arguments: ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", sourceURL.path], timeoutSeconds: 5, maxOutputBytes: 128)
            let v = vRes?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let a = aRes?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if !v.isEmpty { return (v, a) }
        }
        let info = try? ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: ffmpegPath), arguments: ["-nostdin", "-hide_banner", "-i", sourceURL.path], timeoutSeconds: 4, maxOutputBytes: 8192
        )
        let stderr = (info?.stderr ?? "").lowercased()
        return (extractFFmpegStreamCodec(from: stderr, marker: "video: ") ?? "", extractFFmpegStreamCodec(from: stderr, marker: "audio: ") ?? "")
    }

    private static func extractFFmpegStreamCodec(from text: String, marker: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let token = text[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return token.isEmpty ? nil : String(token)
    }
}
