import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import CoreGraphics
import Foundation

public enum ClipboardPersistenceStore {
    public static let storeFileName = "pinned-clipboard.json"

    private enum StoredKind: String, Codable, Sendable {
        case text
        case colorHex
        case image
        case video
        case file
    }

    private struct StoredPinnedRecord: Codable, Sendable {
        let id: String
        let title: String
        let subtitle: String
        let kind: StoredKind
        let capturedAtISO8601: String
        let textValue: String?
        let colorHex: String?
        let filePaths: [String]?
        let imageWidth: Double?
        let imageHeight: Double?
    }

    public static func defaultStoreURL(appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    public static func defaultMediaDirectory(appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent("ClipboardPinned", isDirectory: true)
    }

    @discardableResult
    public static func savePinnedEntries(
        _ entries: [ClipboardEntry],
        appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory(),
        mediaDirectory: URL? = nil
    ) -> [ClipboardEntry] {
        let fm = FileManager.default
        let resolvedMediaDir = mediaDirectory ?? defaultMediaDirectory(appSupportDirectory: appSupportDirectory)
        let storeURL = defaultStoreURL(appSupportDirectory: appSupportDirectory)
        let tempRoot = ClipboardPasteboardIO.clipboardTempDirectory().standardizedFileURL.path
        let mediaRoot = resolvedMediaDir.standardizedFileURL.path
        try? fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        var records: [StoredPinnedRecord] = []
        var updatedEntries: [ClipboardEntry] = []
        var referencedMediaPaths = Set<String>()

        for item in entries {
            guard item.isPinned else {
                updatedEntries.append(item)
                continue
            }
            let migratedItem = migrateTempMediaIfNeeded(item, tempRoot: tempRoot, mediaDir: resolvedMediaDir)
            updatedEntries.append(migratedItem)
            for u in migratedItem.fileURLs where u.standardizedFileURL.path.hasPrefix(mediaRoot + "/") {
                referencedMediaPaths.insert(u.standardizedFileURL.path)
            }
            let ts = iso.string(from: migratedItem.capturedAt)
            switch migratedItem.payloadKind {
            case .text:
                records.append(StoredPinnedRecord(
                    id: migratedItem.id.uuidString, title: migratedItem.title, subtitle: migratedItem.subtitle,
                    kind: .text, capturedAtISO8601: ts, textValue: migratedItem.textValue,
                    colorHex: nil, filePaths: nil, imageWidth: nil, imageHeight: nil
                ))
            case .colorHex(let hex):
                records.append(StoredPinnedRecord(
                    id: migratedItem.id.uuidString, title: migratedItem.title, subtitle: migratedItem.subtitle,
                    kind: .colorHex, capturedAtISO8601: ts, textValue: migratedItem.textValue ?? hex,
                    colorHex: hex, filePaths: nil, imageWidth: nil, imageHeight: nil
                ))
            case .image(let u, let size):
                records.append(StoredPinnedRecord(
                    id: migratedItem.id.uuidString, title: migratedItem.title, subtitle: migratedItem.subtitle,
                    kind: .image, capturedAtISO8601: ts, textValue: nil, colorHex: nil,
                    filePaths: [u.standardizedFileURL.path], imageWidth: Double(size.width), imageHeight: Double(size.height)
                ))
            case .video:
                records.append(StoredPinnedRecord(
                    id: migratedItem.id.uuidString, title: migratedItem.title, subtitle: migratedItem.subtitle,
                    kind: .video, capturedAtISO8601: ts, textValue: nil, colorHex: nil,
                    filePaths: migratedItem.fileURLs.map(\.standardizedFileURL.path), imageWidth: nil, imageHeight: nil
                ))
            case .file:
                records.append(StoredPinnedRecord(
                    id: migratedItem.id.uuidString, title: migratedItem.title, subtitle: migratedItem.subtitle,
                    kind: .file, capturedAtISO8601: ts, textValue: nil, colorHex: nil,
                    filePaths: migratedItem.fileURLs.map(\.standardizedFileURL.path), imageWidth: nil, imageHeight: nil
                ))
            }
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(records) {
            try? data.write(to: storeURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        }
        pruneOrphanedMediaFiles(in: resolvedMediaDir, keeping: referencedMediaPaths)
        return updatedEntries
    }

    public static func loadPinnedEntries(
        appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()
    ) -> [ClipboardEntry] {
        let storeURL = defaultStoreURL(appSupportDirectory: appSupportDirectory)
        guard let data = try? Data(contentsOf: storeURL),
              let records = try? JSONDecoder().decode([StoredPinnedRecord].self, from: data) else {
            return []
        }
        let fm = FileManager.default
        let iso = ISO8601DateFormatter()
        var loaded: [ClipboardEntry] = []

        for rec in records {
            let uuid = UUID(uuidString: rec.id) ?? UUID()
            let captured = iso.date(from: rec.capturedAtISO8601) ?? Date()
            switch rec.kind {
            case .text:
                loaded.append(ClipboardEntry(
                    id: uuid, title: rec.title, subtitle: rec.subtitle,
                    textValue: rec.textValue, capturedAt: captured, isPinned: true, payloadKind: .text
                ))
            case .colorHex:
                let hex = rec.colorHex ?? rec.textValue ?? "#000000"
                loaded.append(ClipboardEntry(
                    id: uuid, title: rec.title, subtitle: rec.subtitle,
                    textValue: rec.textValue ?? hex, capturedAt: captured, isPinned: true, payloadKind: .colorHex(hex)
                ))
            case .image:
                guard let path = rec.filePaths?.first, fm.fileExists(atPath: path) else { continue }
                let u = URL(fileURLWithPath: path).standardizedFileURL
                let fallback = CGSize(width: rec.imageWidth ?? 0, height: rec.imageHeight ?? 0)
                let dims = MediaClassifier.readImageDimensions(at: u) ?? fallback
                loaded.append(ClipboardEntry(
                    id: uuid, title: rec.title, subtitle: rec.subtitle,
                    fileURL: u, capturedAt: captured, isPinned: true, payloadKind: .image(u, dims)
                ))
            case .video:
                let urls = (rec.filePaths ?? []).filter { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0).standardizedFileURL }
                guard let first = urls.first else { continue }
                loaded.append(ClipboardEntry(
                    id: uuid, title: rec.title, subtitle: rec.subtitle,
                    fileURL: first, fileURLs: urls, capturedAt: captured, isPinned: true, payloadKind: .video(first)
                ))
            case .file:
                let urls = (rec.filePaths ?? []).filter { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0).standardizedFileURL }
                guard let first = urls.first else { continue }
                loaded.append(ClipboardEntry(
                    id: uuid, title: rec.title, subtitle: rec.subtitle,
                    fileURL: first, fileURLs: urls, capturedAt: captured, isPinned: true, payloadKind: .file(first)
                ))
            }
        }
        return loaded
    }

    private static func migrateTempMediaIfNeeded(_ item: ClipboardEntry, tempRoot: String, mediaDir: URL) -> ClipboardEntry {
        guard !item.fileURLs.isEmpty else { return item }
        let fm = FileManager.default
        var changed = false
        var nextURLs: [URL] = []
        for (idx, u) in item.fileURLs.enumerated() {
            let std = u.standardizedFileURL
            guard std.path.hasPrefix(tempRoot + "/"), fm.fileExists(atPath: std.path) else {
                nextURLs.append(std)
                continue
            }
            try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let ext = std.pathExtension.isEmpty ? "bin" : std.pathExtension
            let suffix = idx == 0 ? "" : "-\(idx)"
            let dest = mediaDir.appendingPathComponent("pinned-\(item.id.uuidString)\(suffix).\(ext)", isDirectory: false).standardizedFileURL
            if dest.path != std.path {
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.copyItem(at: std, to: dest)
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                }
                if fm.fileExists(atPath: dest.path) {
                    nextURLs.append(dest)
                    changed = true
                    continue
                }
            }
            nextURLs.append(std)
        }
        guard changed, let first = nextURLs.first else { return item }
        let nextKind: ClipboardPayloadKind
        switch item.payloadKind {
        case .image(_, let sz): nextKind = .image(first, sz)
        case .video: nextKind = .video(first)
        case .file: nextKind = .file(first)
        case .text, .colorHex: nextKind = item.payloadKind
        }
        return ClipboardEntry(
            id: item.id, title: item.title, subtitle: item.subtitle, textValue: item.textValue,
            fileURL: first, fileURLs: nextURLs, capturedAt: item.capturedAt, isPinned: item.isPinned, payloadKind: nextKind
        )
    }

    private static func pruneOrphanedMediaFiles(in mediaDir: URL, keeping keptPaths: Set<String>) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil) else { return }
        for u in urls where u.lastPathComponent.hasPrefix("pinned-") {
            let std = u.standardizedFileURL.path
            if !keptPaths.contains(std) {
                try? fm.removeItem(at: u)
            }
        }
    }
}
