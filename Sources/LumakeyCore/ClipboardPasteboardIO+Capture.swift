import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import CoreGraphics
import Foundation

public extension ClipboardPasteboardIO {
    @MainActor
    static func captureCurrent(from pasteboard: NSPasteboard = .general, tempRoot: URL = FileManager.default.temporaryDirectory) -> ClipboardEntry? {
        let rawTypes = Set((pasteboard.types ?? []).map(\.rawValue))
        guard rawTypes.isDisjoint(with: ClipboardService.concealedTypes) else { return nil }

        let fileURLs = readFileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            let stabilized = fileURLs.compactMap { snapshotTransientFileIfNeeded($0, from: pasteboard, tempRoot: tempRoot) }
            guard let first = stabilized.first else { return nil }
            if stabilized.count > 1 {
                let extraCount = stabilized.count - 1
                let title = L10n.pick("\(first.lastPathComponent) 等 \(stabilized.count) 项", "\(first.lastPathComponent) +\(extraCount) more")
                return ClipboardEntry(
                    title: title,
                    subtitle: first.deletingLastPathComponent().path,
                    fileURLs: stabilized,
                    payloadKind: classifyPayloadKind(for: first, allURLs: stabilized)
                )
            }
            return makeSingleFileEntry(for: first)
        }

        if let gifData = pasteboard.data(forType: gifPasteboardType), gifData.count >= 6,
           !rawTypes.contains(NSPasteboard.PasteboardType.rtf.rawValue),
           let url = writeClipboardTempData(gifData, fileName: "clip-\(shortToken()).gif", tempRoot: tempRoot) {
            let dims = MediaClassifier.readImageDimensions(at: url) ?? .zero
            return ClipboardEntry(
                title: "GIF 动图 \(Int(dims.width))×\(Int(dims.height))",
                subtitle: formatMediaSubtitle(url: url, label: "GIF"),
                fileURL: url,
                payloadKind: .image(url, dims)
            )
        }

        if let mp4Data = pasteboard.data(forType: mpeg4PasteboardType), !mp4Data.isEmpty,
           let url = writeClipboardTempData(mp4Data, fileName: "clip-\(shortToken()).mp4", tempRoot: tempRoot) {
            return makeSingleFileEntry(for: url)
        }
        if let movData = pasteboard.data(forType: quickTimeMoviePasteboardType), !movData.isEmpty,
           let url = writeClipboardTempData(movData, fileName: "clip-\(shortToken()).mov", tempRoot: tempRoot) {
            return makeSingleFileEntry(for: url)
        }

        if let str = pasteboard.string(forType: .string) {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeCopiedWebImage = hasDirectBitmapWithoutRichText(rawTypes) && isStandaloneWebURL(trimmed)
            if !trimmed.isEmpty && !looksLikeCopiedWebImage {
                let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
                if let hex = ClipboardService.parseHexColor(trimmed) {
                    return ClipboardEntry(title: hex, subtitle: "颜色 HEX · \(trimmed.count) 字符", textValue: str, payloadKind: .colorHex(hex))
                }
                return ClipboardEntry(
                    title: String(firstLine.prefix(90)),
                    subtitle: "文本 · \(trimmed.count) 字",
                    textValue: str,
                    payloadKind: .text
                )
            }
        }

        if let rawPNG = pasteboard.data(forType: .png), !rawPNG.isEmpty,
           let url = writeClipboardTempData(rawPNG, fileName: "clip-\(shortToken()).png", tempRoot: tempRoot) {
            let dims = MediaClassifier.readImageDimensions(at: url) ?? .zero
            return ClipboardEntry(
                title: "剪贴板图片 \(Int(dims.width))×\(Int(dims.height))",
                subtitle: formatMediaSubtitle(url: url, label: "PNG"),
                fileURL: url,
                payloadKind: .image(url, dims)
            )
        }

        if let rawJPEG = pasteboard.data(forType: jpegPasteboardType), !rawJPEG.isEmpty,
           let url = writeClipboardTempData(rawJPEG, fileName: "clip-\(shortToken()).jpg", tempRoot: tempRoot) {
            let dims = MediaClassifier.readImageDimensions(at: url) ?? .zero
            return ClipboardEntry(
                title: "剪贴板图片 \(Int(dims.width))×\(Int(dims.height))",
                subtitle: formatMediaSubtitle(url: url, label: "JPEG"),
                fileURL: url,
                payloadKind: .image(url, dims)
            )
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           let url = writeClipboardTempData(png, fileName: "clip-\(shortToken()).png", tempRoot: tempRoot) {
            let dims = MediaClassifier.readImageDimensions(at: url) ?? image.size
            return ClipboardEntry(
                title: "剪贴板图片 \(Int(dims.width))×\(Int(dims.height))",
                subtitle: formatMediaSubtitle(url: url, label: "PNG"),
                fileURL: url,
                payloadKind: .image(url, dims)
            )
        }
        return nil
    }

    @MainActor
    static func materializePasteboardImageIfNeeded(from pasteboard: NSPasteboard = .general, into directory: URL) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let gifData = pasteboard.data(forType: gifPasteboardType), gifData.count >= 6 {
            let dst = WorkspaceFileOperations.uniqueCopyDestinationURL(for: directory.appendingPathComponent("剪贴板动图.gif"), in: directory)
            if (try? gifData.write(to: dst, options: .atomic)) != nil { return dst }
        }
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            let dst = WorkspaceFileOperations.uniqueCopyDestinationURL(for: directory.appendingPathComponent("剪贴板图片.png"), in: directory)
            if (try? pngData.write(to: dst, options: .atomic)) != nil { return dst }
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let dst = WorkspaceFileOperations.uniqueCopyDestinationURL(for: directory.appendingPathComponent("剪贴板图片.png"), in: directory)
            if (try? png.write(to: dst, options: .atomic)) != nil { return dst }
        }
        return nil
    }

    @MainActor
    private static func snapshotTransientFileIfNeeded(_ url: URL, from pasteboard: NSPasteboard, tempRoot: URL) -> URL? {
        let std = url.standardizedFileURL
        let fm = FileManager.default
        let clipRoot = clipboardTempDirectory(tempRoot: tempRoot).standardizedFileURL.path
        if std.path.hasPrefix(clipRoot + "/") {
            return fm.fileExists(atPath: std.path) ? std : nil
        }

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: std.path, isDirectory: &isDir)
        if exists && isDir.boolValue { return std }

        let shouldSnapshot = isEphemeralOrContainerPath(std.path) || !exists || !fm.isReadableFile(atPath: std.path)
        guard shouldSnapshot else { return std }

        let safeName = sanitizeTempFileName(std.lastPathComponent)
        if exists, let size = (try? std.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
           size > 0, size <= maxCachedFileBytes {
            let slotDir = clipboardTempDirectory(tempRoot: tempRoot).appendingPathComponent(shortToken(), isDirectory: true)
            let dest = slotDir.appendingPathComponent(safeName, isDirectory: false)
            try? fm.createDirectory(at: slotDir, withIntermediateDirectories: true)
            if (try? fm.copyItem(at: std, to: dest)) != nil { return dest }
        }
        if let fallback = extractPasteboardFallbackFile(named: safeName, from: pasteboard, tempRoot: tempRoot) {
            return fallback
        }
        return exists ? std : nil
    }

    @MainActor
    private static func extractPasteboardFallbackFile(named fileName: String, from pasteboard: NSPasteboard, tempRoot: URL) -> URL? {
        let candidates: [NSPasteboard.PasteboardType] = [
            gifPasteboardType, mpeg4PasteboardType, quickTimeMoviePasteboardType, .png, jpegPasteboardType, .tiff
        ]
        for type in candidates {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return writeClipboardTempData(data, fileName: fileName, useSubfolder: true, tempRoot: tempRoot)
            }
        }
        return nil
    }

    private static func makeSingleFileEntry(for url: URL) -> ClipboardEntry {
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let kind = MediaClassifier.classify(url: url, isDirectory: isDir.boolValue)
        switch kind {
        case .image:
            let dims = MediaClassifier.readImageDimensions(at: url) ?? NSImage(contentsOf: url)?.size ?? .zero
            let dimPart = (dims.width > 0 && dims.height > 0) ? "\(Int(dims.width))×\(Int(dims.height)) · " : ""
            let sub = "\(dimPart)\(formatMediaSubtitle(url: url, label: url.pathExtension.uppercased()))"
            return ClipboardEntry(title: url.lastPathComponent, subtitle: sub, fileURL: url, payloadKind: .image(url, dims))
        case .video:
            let sub = formatMediaSubtitle(url: url, label: url.pathExtension.uppercased())
            return ClipboardEntry(title: url.lastPathComponent, subtitle: sub, fileURL: url, payloadKind: .video(url))
        default:
            return ClipboardEntry(title: url.lastPathComponent, subtitle: url.deletingLastPathComponent().path, fileURL: url, payloadKind: .file(url))
        }
    }

    private static func classifyPayloadKind(for first: URL, allURLs: [URL]) -> ClipboardPayloadKind {
        let kinds = Set(allURLs.map { u -> PreviewMediaKind in
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            return MediaClassifier.classify(url: u, isDirectory: isDir.boolValue)
        })
        if kinds == [.video] { return .video(first) }
        if kinds == [.image] && allURLs.count == 1 {
            return .image(first, MediaClassifier.readImageDimensions(at: first) ?? .zero)
        }
        return .file(first)
    }

    static func isEphemeralOrContainerPath(_ path: String) -> Bool {
        path.contains("/Library/Containers/")
            || path.contains("/Library/Group Containers/")
            || path.hasPrefix("/var/folders/")
            || path.hasPrefix("/private/var/folders/")
            || path.hasPrefix("/tmp/")
            || path.hasPrefix("/private/tmp/")
            || path.contains("/RWTemp/")
            || path.contains("/MessageTemp/")
    }

    private static func hasDirectBitmapWithoutRichText(_ rawTypes: Set<String>) -> Bool {
        let hasBitmap = rawTypes.contains(NSPasteboard.PasteboardType.png.rawValue)
            || rawTypes.contains(jpegPasteboardType.rawValue)
            || rawTypes.contains(gifPasteboardType.rawValue)
        let hasDocText = rawTypes.contains(NSPasteboard.PasteboardType.rtf.rawValue)
            || rawTypes.contains("public.tabular-text")
        return hasBitmap && !hasDocText
    }

    private static func isStandaloneWebURL(_ trimmed: String) -> Bool {
        guard !trimmed.contains(where: \.isWhitespace),
              let u = URL(string: trimmed),
              let s = u.scheme?.lowercased() else { return false }
        return s == "http" || s == "https" || s == "data"
    }

    private static func writeClipboardTempData(
        _ data: Data, fileName: String, useSubfolder: Bool = false, tempRoot: URL
    ) -> URL? {
        let base = clipboardTempDirectory(tempRoot: tempRoot)
        let dir = useSubfolder ? base.appendingPathComponent(shortToken(), isDirectory: true) : base
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(sanitizeTempFileName(fileName), isDirectory: false)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    private static func formatMediaSubtitle(url: URL, label: String) -> String {
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let sizeText = FastFormatters.formatFileBytes(bytes)
        return label.isEmpty ? sizeText : "\(label) · \(sizeText)"
    }

    private static func sanitizeTempFileName(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cleaned.isEmpty ? "clip-\(shortToken())" : cleaned
    }

    private static func shortToken() -> String {
        String(UUID().uuidString.prefix(12)).lowercased()
    }
}
