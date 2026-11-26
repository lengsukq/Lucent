import Foundation
import PluginKit

struct ShareImageResponse: Codable {
    let ok: Bool
    let copied: Bool
    let path: String?
    let width: Int
    let height: Int
    let bytes: Int
    let message: String
}

private enum ShareImageBounds {
    static let minBytes = 64
    static let maxBytes = 16 * 1024 * 1024
    static let maxDimension = 8192
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let ihdrTag: [UInt8] = [0x49, 0x48, 0x44, 0x52]
}

private func decodeValidatedPNG(from raw: String) -> (data: Data, width: Int, height: Int)? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let base64Body: String
    if let comma = trimmed.firstIndex(of: ","), trimmed[..<comma].lowercased().contains("base64") {
        base64Body = String(trimmed[trimmed.index(after: comma)...])
    } else {
        base64Body = trimmed
    }
    guard let data = Data(base64Encoded: base64Body, options: [.ignoreUnknownCharacters]),
          data.count >= ShareImageBounds.minBytes,
          data.count <= ShareImageBounds.maxBytes else {
        return nil
    }
    let header = [UInt8](data.prefix(24))
    guard header.count == 24,
          Array(header[0..<8]) == ShareImageBounds.pngSignature,
          Array(header[12..<16]) == ShareImageBounds.ihdrTag else {
        return nil
    }
    let width = Int(header[16]) << 24 | Int(header[17]) << 16 | Int(header[18]) << 8 | Int(header[19])
    let height = Int(header[20]) << 24 | Int(header[21]) << 16 | Int(header[22]) << 8 | Int(header[23])
    guard width > 0, width <= ShareImageBounds.maxDimension,
          height > 0, height <= ShareImageBounds.maxDimension else {
        return nil
    }
    return (data, width, height)
}

func handleCopyShareImage(input: PluginInput, isEn: Bool) -> ShareImageResponse {
    guard let png = decodeValidatedPNG(from: input.query) else {
        return ShareImageResponse(
            ok: false, copied: false, path: nil, width: 0, height: 0, bytes: 0,
            message: isEn ? "Invalid PNG share card payload" : "分享图片数据无效或格式不受支持"
        )
    }

    let dirPath = input.dataDir.isEmpty ? defaultPulseDataDir() : input.dataDir
    let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
    let outURL = dirURL.appendingPathComponent("share-card.png")
    do {
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try png.data.write(to: outURL, options: .atomic)
    } catch {
        return ShareImageResponse(
            ok: false, copied: false, path: nil, width: png.width, height: png.height, bytes: png.data.count,
            message: isEn ? "Failed to stage PNG: \(error.localizedDescription)" : "暂存分享图失败：\(error.localizedDescription)"
        )
    }

    let bridge = HostBridgeClient(input: input, timeoutSeconds: 6)
    guard bridge.isAvailable else {
        return ShareImageResponse(
            ok: true, copied: false, path: outURL.path, width: png.width, height: png.height, bytes: png.data.count,
            message: isEn ? "Image rendered; host clipboard bridge unavailable" : "图片已生成，等待宿主剪贴板桥接写入"
        )
    }

    let resp = bridge.call(capability: "clipboard", action: "writeImage", params: ["imagePath": outURL.path])
    let written = resp.ok && resp.bool("written", default: true)
    if written {
        return ShareImageResponse(
            ok: true, copied: true, path: outURL.path, width: png.width, height: png.height, bytes: png.data.count,
            message: isEn ? "Share card copied to clipboard" : "精美分享图已复制到剪贴板"
        )
    }
    let reason = resp.message ?? resp.error ?? (isEn ? "Clipboard write failed" : "写入剪贴板失败")
    return ShareImageResponse(
        ok: false, copied: false, path: outURL.path, width: png.width, height: png.height, bytes: png.data.count,
        message: isEn ? "Clipboard error: \(reason)" : "复制图片失败：\(reason)"
    )
}

func handleSaveShareImage(input: PluginInput, isEn: Bool) -> ShareImageResponse {
    guard let png = decodeValidatedPNG(from: input.query) else {
        return ShareImageResponse(
            ok: false, copied: false, path: nil, width: 0, height: 0, bytes: 0,
            message: isEn ? "Invalid PNG share card payload" : "分享图片数据无效或格式不受支持"
        )
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.timeZone = .current
    let stamp = formatter.string(from: Date())
    let desktopURL = URL(fileURLWithPath: pulseUserHomePath(), isDirectory: true).appendingPathComponent("Desktop", isDirectory: true)
    let outURL = desktopURL.appendingPathComponent("Antigravity-Pulse-\(stamp).png")
    do {
        try FileManager.default.createDirectory(at: desktopURL, withIntermediateDirectories: true)
        try png.data.write(to: outURL, options: .atomic)
        return ShareImageResponse(
            ok: true, copied: false, path: outURL.path, width: png.width, height: png.height, bytes: png.data.count,
            message: isEn ? "Saved to Desktop: \(outURL.lastPathComponent)" : "已保存到桌面：\(outURL.lastPathComponent)"
        )
    } catch {
        return ShareImageResponse(
            ok: false, copied: false, path: nil, width: png.width, height: png.height, bytes: png.data.count,
            message: isEn ? "Save failed: \(error.localizedDescription)" : "保存失败：\(error.localizedDescription)"
        )
    }
}
