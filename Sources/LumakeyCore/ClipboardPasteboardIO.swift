import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardPasteboardIO {
    public static let filenamesPasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    public static let gifPasteboardType = NSPasteboard.PasteboardType("com.compuserve.gif")
    public static let jpegPasteboardType = NSPasteboard.PasteboardType("public.jpeg")
    public static let mpeg4PasteboardType = NSPasteboard.PasteboardType(UTType.mpeg4Movie.identifier)
    public static let quickTimeMoviePasteboardType = NSPasteboard.PasteboardType(UTType.quickTimeMovie.identifier)
    static let maxCachedFileBytes: Int64 = 250 * 1_024 * 1_024

    public static func clipboardTempDirectory(tempRoot: URL = FileManager.default.temporaryDirectory) -> URL {
        tempRoot.appendingPathComponent("lumakey-clipboard", isDirectory: true)
    }

    @MainActor
    public static func readFileURLs(from pasteboard: NSPasteboard = .general) -> [URL] {
        var collected: [URL] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            collected.append(contentsOf: urls.map(\.standardizedFileURL))
        }
        if collected.isEmpty,
           let paths = pasteboard.propertyList(forType: filenamesPasteboardType) as? [String] {
            collected.append(contentsOf: paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0).standardizedFileURL })
        }
        if collected.isEmpty {
            for item in pasteboard.pasteboardItems ?? [] {
                if let raw = item.string(forType: .fileURL), let u = URL(string: raw), u.isFileURL {
                    collected.append(u.standardizedFileURL)
                }
            }
        }
        return WorkspaceFileOperations.deduplicateURLs(collected)
    }

    @MainActor
    @discardableResult
    public static func writeToPasteboard(_ entry: ClipboardEntry, pasteboard: NSPasteboard = .general) -> Bool {
        switch entry.payloadKind {
        case .text, .colorHex:
            guard let text = entry.textValue else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .image(let url, _):
            let candidates = entry.fileURLs.isEmpty ? [url] : entry.fileURLs
            if candidates.count == 1 {
                return writeImageFileToPasteboard(at: candidates[0], to: pasteboard)
            }
            return writeFileURLsToPasteboard(candidates, to: pasteboard)
        case .video(let url), .file(let url):
            let candidates = entry.fileURLs.isEmpty ? [url] : entry.fileURLs
            return writeFileURLsToPasteboard(candidates, to: pasteboard)
        }
    }

    public static func plainTextRepresentation(for entry: ClipboardEntry) -> String? {
        if let text = entry.textValue, !text.isEmpty { return text }
        if !entry.fileURLs.isEmpty { return entry.fileURLs.map(\.path).joined(separator: "\n") }
        return entry.title.isEmpty ? nil : entry.title
    }

    @MainActor
    @discardableResult
    public static func writePlainTextToPasteboard(_ entry: ClipboardEntry, pasteboard: NSPasteboard = .general) -> Bool {
        guard let plain = plainTextRepresentation(for: entry), !plain.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(plain, forType: .string)
    }

    @MainActor
    @discardableResult
    public static func writeImageFileToPasteboard(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        let stdURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: stdURL.path) else { return false }

        let ext = stdURL.pathExtension.lowercased()
        let rawData = try? Data(contentsOf: stdURL)
        let gifData: Data? = (ext == "gif" && (rawData?.count ?? 0) >= 6) ? rawData : nil
        let jpegData: Data? = ((ext == "jpg" || ext == "jpeg") && (rawData?.isEmpty == false)) ? rawData : nil
        let (pngData, tiffData) = makeBitmapRepresentations(at: stdURL, ext: ext, rawData: rawData)

        pasteboard.clearContents()
        let wroteFileObj = pasteboard.writeObjects([stdURL as NSURL])
        if wroteFileObj {
            var extraTypes: [NSPasteboard.PasteboardType] = [filenamesPasteboardType]
            if gifData != nil { extraTypes.append(gifPasteboardType) }
            if jpegData != nil { extraTypes.append(jpegPasteboardType) }
            if pngData != nil { extraTypes.append(.png) }
            if tiffData != nil { extraTypes.append(.tiff) }
            pasteboard.addTypes(extraTypes, owner: nil)
            _ = pasteboard.setPropertyList([stdURL.path], forType: filenamesPasteboardType)
            if let gifData { _ = pasteboard.setData(gifData, forType: gifPasteboardType) }
            if let jpegData { _ = pasteboard.setData(jpegData, forType: jpegPasteboardType) }
            if let pngData { _ = pasteboard.setData(pngData, forType: .png) }
            if let tiffData { _ = pasteboard.setData(tiffData, forType: .tiff) }
            return true
        }

        let item = NSPasteboardItem()
        item.setString(stdURL.absoluteString, forType: .fileURL)
        _ = item.setPropertyList([stdURL.path], forType: filenamesPasteboardType)
        if let gifData { item.setData(gifData, forType: gifPasteboardType) }
        if let jpegData { item.setData(jpegData, forType: jpegPasteboardType) }
        if let pngData { item.setData(pngData, forType: .png) }
        if let tiffData { item.setData(tiffData, forType: .tiff) }
        if pasteboard.writeObjects([item]) { return true }
        if let img = NSImage(contentsOf: stdURL) { return pasteboard.writeObjects([img]) }
        return false
    }

    @MainActor
    @discardableResult
    public static func writeFileURLsToPasteboard(_ urls: [URL], to pasteboard: NSPasteboard = .general) -> Bool {
        let validURLs = WorkspaceFileOperations.deduplicateURLs(urls.map(\.standardizedFileURL))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else { return false }

        pasteboard.clearContents()
        let wroteObjects = pasteboard.writeObjects(validURLs as [NSURL])
        if wroteObjects {
            pasteboard.addTypes([filenamesPasteboardType], owner: nil)
            _ = pasteboard.setPropertyList(validURLs.map(\.path), forType: filenamesPasteboardType)
            return true
        }

        let items: [NSPasteboardItem] = validURLs.enumerated().map { idx, u in
            let item = NSPasteboardItem()
            item.setString(u.absoluteString, forType: .fileURL)
            if idx == 0 {
                _ = item.setPropertyList(validURLs.map(\.path), forType: filenamesPasteboardType)
            }
            return item
        }
        return pasteboard.writeObjects(items)
    }

    private static func makeBitmapRepresentations(at url: URL, ext: String, rawData: Data?) -> (png: Data?, tiff: Data?) {
        if ext == "png", let rawData, !rawData.isEmpty, let rep = NSBitmapImageRep(data: rawData) {
            return (rawData, rep.tiffRepresentation)
        }
        if let rawData, !rawData.isEmpty, let rep = NSBitmapImageRep(data: rawData) {
            return (rep.representation(using: .png, properties: [:]), rep.tiffRepresentation)
        }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        if let src = CGImageSourceCreateWithURL(url as CFURL, opts),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, opts) {
            let rep = NSBitmapImageRep(cgImage: cg)
            return (rep.representation(using: .png, properties: [:]), rep.tiffRepresentation)
        }
        return (nil, nil)
    }
}
