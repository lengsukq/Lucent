import LucentFoundation
import Foundation

public enum CaptureRecordingMode: String, Codable, Sendable, Equatable, Hashable {
    case gif
    case video
}

public struct VideoRecordingOptions: Codable, Sendable, Equatable, Hashable {
    public static let fpsPresets: [Int] = [30, 60]
    public static let dimensionPresets: [Int] = [1280, 1920, 0]

    public var fps: Int
    public var maxDimension: Int
    public var captureAudio: Bool
    public var showsCursor: Bool
    public var maxDurationSeconds: Int

    public init(
        fps: Int = 30,
        maxDimension: Int = 0,
        captureAudio: Bool = false,
        showsCursor: Bool = true,
        maxDurationSeconds: Int = 600
    ) {
        self.fps = min(max(fps, 1), 60)
        self.maxDimension = max(0, maxDimension)
        self.captureAudio = captureAudio
        self.showsCursor = showsCursor
        self.maxDurationSeconds = min(max(maxDurationSeconds, 5), 3600)
    }

    public var frameIntervalSeconds: Double { 1.0 / Double(max(1, fps)) }

    public static func dimensionLabel(for maxDimension: Int) -> String {
        switch maxDimension {
        case 0: L10n.pick("原画", "Native")
        case 1280: "720p"
        case 1920: "1080p"
        case 2560: "2K"
        default: "\(maxDimension)p"
        }
    }

    public static func evenScaledDimensions(width: Int, height: Int, maxDimension: Int) -> (Int, Int) {
        let cap = maxDimension > 0 ? maxDimension : 3840
        let longest = max(width, height)
        let rawW: Int
        let rawH: Int
        if longest > cap, longest > 0 {
            let scale = Double(cap) / Double(longest)
            rawW = Int((Double(width) * scale).rounded())
            rawH = Int((Double(height) * scale).rounded())
        } else {
            rawW = width
            rawH = height
        }
        return (max(16, rawW & ~1), max(16, rawH & ~1))
    }
}

public struct VideoFinalizeResult: Sendable, Equatable {
    public let fileURL: URL
    public let frameCount: Int
    public let durationSeconds: Double
    public let fileSizeBytes: Int64
    public let pixelSize: CGSize
    public let hasAudio: Bool

    public init(
        fileURL: URL,
        frameCount: Int,
        durationSeconds: Double,
        fileSizeBytes: Int64,
        pixelSize: CGSize,
        hasAudio: Bool
    ) {
        self.fileURL = fileURL
        self.frameCount = frameCount
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.pixelSize = pixelSize
        self.hasAudio = hasAudio
    }
}

public enum VideoEncoderError: LocalizedError, Sendable, Equatable {
    case emptyRecording
    case writerInitializationFailed(String)
    case finalizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyRecording: L10n.pick("未捕获到有效录像画面帧。", "No video frames were captured.")
        case .writerInitializationFailed(let name): L10n.pick("无法创建 MP4 录像写入器：\(name)", "Unable to create MP4 writer: \(name)")
        case .finalizationFailed(let name): L10n.pick("MP4 视频编码保存失败：\(name)", "Failed to finalize MP4 video: \(name)")
        }
    }
}
