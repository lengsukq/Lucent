import AppKit
import CoreGraphics
import Foundation
import ImageIO
import LucentFoundation
import LucentMedia
import UniformTypeIdentifiers

public struct PasteboardSnapshot: Sendable {
    private struct ItemEntry: Sendable {
        let rawType: String
        let data: Data
    }

    private let items: [[ItemEntry]]

    @MainActor
    public static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let captured: [[ItemEntry]] = (pasteboard.pasteboardItems ?? []).compactMap { item in
            let entries: [ItemEntry] = item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return ItemEntry(rawType: type.rawValue, data: data)
            }
            return entries.isEmpty ? nil : entries
        }
        return PasteboardSnapshot(items: captured)
    }

    @MainActor
    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let pbItems: [NSPasteboardItem] = items.map { entries in
            let pbItem = NSPasteboardItem()
            for entry in entries {
                pbItem.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.rawType))
            }
            return pbItem
        }
        pasteboard.writeObjects(pbItems)
    }
}

/// Deferred pasteboard provider so live selection/annotation updates register on `NSPasteboard`
/// in sub-millisecond time and encode PNG/TIFF bytes only when an external consumer pastes.
public final class LazyImagePasteboardProvider: NSObject, NSPasteboardItemDataProvider {
    @MainActor private static var retainedActiveProvider: LazyImagePasteboardProvider?

    private let cgImage: CGImage
    private let scale: CGFloat
    private let lock = NSLock()
    private var cachedPNG: Data?
    private var cachedTIFF: Data?

    public init(cgImage: CGImage, scale: CGFloat) {
        self.cgImage = cgImage
        self.scale = max(scale, 1.0)
        super.init()
    }

    @MainActor
    public static func install(
        cgImage: CGImage,
        scale: CGFloat,
        on pasteboard: NSPasteboard = .general
    ) -> Bool {
        let provider = LazyImagePasteboardProvider(cgImage: cgImage, scale: scale)
        retainedActiveProvider = provider
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png, .tiff])
        return pasteboard.writeObjects([item])
    }

    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .png, let data = encodedPNG() {
            item.setData(data, forType: .png)
        } else if type == .tiff, let data = encodedTIFF() {
            item.setData(data, forType: .tiff)
        }
    }

    private func encodedPNG() -> Data? {
        lock.withLock {
            if let cachedPNG { return cachedPNG }
            let data = Self.encodeData(cgImage: cgImage, scale: scale, utType: .png)
            cachedPNG = data
            return data
        }
    }

    private func encodedTIFF() -> Data? {
        lock.withLock {
            if let cachedTIFF { return cachedTIFF }
            let logical = NSSize(
                width: max(1, CGFloat(cgImage.width) / scale),
                height: max(1, CGFloat(cgImage.height) / scale)
            )
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = logical
            let data = rep.tiffRepresentation
            cachedTIFF = data
            return data
        }
    }

    static func encodeData(cgImage: CGImage, scale: CGFloat, utType: UTType, quality: Double = 0.92) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, utType.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72.0 * Double(max(scale, 1.0))
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if utType != .png {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? (out as Data) : nil
    }
}

public extension ScreenshotCompositor {
    @MainActor
    @discardableResult
    static func copyImageToPasteboard(
        _ cgImage: CGImage,
        scale: CGFloat = 2.0,
        lazy: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        if lazy {
            return LazyImagePasteboardProvider.install(cgImage: cgImage, scale: scale, on: pasteboard)
        }
        let safeScale = max(scale, 1.0)
        let logicalSize = NSSize(
            width: max(1, CGFloat(cgImage.width) / safeScale),
            height: max(1, CGFloat(cgImage.height) / safeScale)
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = logicalSize
        let pngData = LazyImagePasteboardProvider.encodeData(cgImage: cgImage, scale: safeScale, utType: .png)
        let tiffData = rep.tiffRepresentation
        pasteboard.clearContents()
        if pngData != nil || tiffData != nil {
            let item = NSPasteboardItem()
            if let pngData { item.setData(pngData, forType: .png) }
            if let tiffData { item.setData(tiffData, forType: .tiff) }
            return pasteboard.writeObjects([item])
        }
        return pasteboard.writeObjects([NSImage(cgImage: cgImage, size: logicalSize)])
    }

    @MainActor
    @discardableResult
    static func copyImageFileToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        ClipboardPasteboardIO.writeImageFileToPasteboard(at: url, to: pasteboard)
    }

    static func saveTempCapture(_ cgImage: CGImage, scale: CGFloat = 2.0) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-captures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("lucent-pin-\(UUID().uuidString).png")
        try writePNG(cgImage, scale: scale, to: url)
        return url
    }

    static func writePNG(_ cgImage: CGImage, scale: CGFloat = 2.0, to url: URL) throws {
        try writeEncodedImage(cgImage, scale: scale, format: .png, to: url)
    }

    static func writeEncodedImage(
        _ cgImage: CGImage,
        scale: CGFloat = 2.0,
        format: CaptureExportFormat,
        quality: Double = 0.92,
        to url: URL
    ) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw LucentError.visionFailed("无法写入 \(format.displayLabel) 文件：\(url.lastPathComponent)")
        }
        let dpi = 72.0 * Double(max(scale, 1.0))
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if format != .png {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            throw LucentError.visionFailed("\(format.displayLabel) 编码失败：\(url.lastPathComponent)")
        }
    }
}
