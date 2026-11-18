import LucentFoundation
import LucentMedia
import AppKit
import CoreGraphics
import Foundation
import ImageIO
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

public extension ScreenshotCompositor {
    @MainActor
    @discardableResult
    static func copyImageToPasteboard(
        _ cgImage: CGImage,
        scale: CGFloat = 2.0,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let safeScale = max(scale, 1.0)
        let logicalSize = NSSize(
            width: max(1, CGFloat(cgImage.width) / safeScale),
            height: max(1, CGFloat(cgImage.height) / safeScale)
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = logicalSize
        let pngData = rep.representation(using: .png, properties: [:])
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
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw LucentError.visionFailed("无法写入 PNG 文件：\(url.lastPathComponent)")
        }
        let safeScale = max(scale, 1.0)
        let dpi = 72.0 * Double(safeScale)
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            throw LucentError.visionFailed("PNG 编码失败：\(url.lastPathComponent)")
        }
    }
}
