import CoreGraphics
import Foundation
import LucentFoundation
import LucentSearch

public enum ClipboardBatchCleanupKind: Equatable, Sendable {
    case unpinnedAll
    case olderThan24Hours
    case olderThan7Days
    case unpinnedMediaOnly
    case unpinnedCategory(ClipboardCategory)
    case allIncludingPinned
}

public enum ClipboardBatchCleaner {
    public static func apply(
        _ kind: ClipboardBatchCleanupKind,
        to entries: [ClipboardEntry],
        now: Date = Date()
    ) -> (remaining: [ClipboardEntry], removed: [ClipboardEntry]) {
        var remaining: [ClipboardEntry] = []
        var removed: [ClipboardEntry] = []
        remaining.reserveCapacity(entries.count)

        for item in entries {
            let shouldRemove: Bool = switch kind {
            case .allIncludingPinned:
                true
            case .unpinnedAll:
                !item.isPinned
            case .olderThan24Hours:
                !item.isPinned && now.timeIntervalSince(item.capturedAt) >= 86_400
            case .olderThan7Days:
                !item.isPinned && now.timeIntervalSince(item.capturedAt) >= 7 * 86_400
            case .unpinnedMediaOnly:
                !item.isPinned && isMediaPayload(item.payloadKind)
            case .unpinnedCategory(let category):
                !item.isPinned && matchesCategory(item, category: category)
            }
            if shouldRemove {
                removed.append(item)
            } else {
                remaining.append(item)
            }
        }
        return (remaining, removed)
    }

    private static func isMediaPayload(_ kind: ClipboardPayloadKind) -> Bool {
        switch kind {
        case .image, .video: true
        default: false
        }
    }

    private static func matchesCategory(_ item: ClipboardEntry, category: ClipboardCategory) -> Bool {
        switch category {
        case .all: return true
        case .pinned: return item.isPinned
        case .text:
            switch item.payloadKind {
            case .text, .colorHex: return true
            default: return false
            }
        case .image:
            if case .image = item.payloadKind { return true }
            return false
        case .video:
            if case .video = item.payloadKind { return true }
            return false
        case .file:
            if case .file = item.payloadKind { return true }
            return false
        }
    }
}

public enum ClipboardHistoryStore {
    public static let storeFileName = "clipboard-history.json"
    private static let lock = NSLock()

    private enum StoredKind: String, Codable, Sendable {
        case text, colorHex, image, video, file
    }

    private struct StoredHistoryRecord: Codable, Sendable {
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

    public static func defaultStoreURL(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    public static func defaultMediaDirectory(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent("ClipboardHistory", isDirectory: true)
    }

    @discardableResult
    public static func saveHistoryEntries(
        _ entries: [ClipboardEntry],
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory(),
        mediaDirectory: URL? = nil,
        protectedMediaPaths: Set<String> = []
    ) -> [ClipboardEntry] {
        lock.withLock {
            let fm = FileManager.default
            let resolvedMediaDir = mediaDirectory ?? defaultMediaDirectory(appSupportDirectory: appSupportDirectory)
            let storeURL = defaultStoreURL(appSupportDirectory: appSupportDirectory)
            let tempRoot = ClipboardPasteboardIO.clipboardTempDirectory().standardizedFileURL.path
            let mediaRoot = resolvedMediaDir.standardizedFileURL.path
            try? fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

            let iso = ISO8601DateFormatter()
            var records: [StoredHistoryRecord] = []
            var updatedEntries: [ClipboardEntry] = []
            var referencedMediaPaths = Set(protectedMediaPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })

            for item in entries {
                guard !item.isPinned else {
                    updatedEntries.append(item)
                    continue
                }
                let migrated = migrateTempMediaIfNeeded(item, tempRoot: tempRoot, mediaDir: resolvedMediaDir)
                updatedEntries.append(migrated)
                for u in migrated.fileURLs where u.standardizedFileURL.path.hasPrefix(mediaRoot + "/") {
                    referencedMediaPaths.insert(u.standardizedFileURL.path)
                }
                records.append(encodeRecord(migrated, iso: iso))
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
    }

    public static func loadHistoryEntries(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory(),
        maxUnpinned: Int = 80,
        ttl: ClipboardRetentionTTL = .forever,
        now: Date = Date()
    ) -> [ClipboardEntry] {
        lock.withLock {
            let storeURL = defaultStoreURL(appSupportDirectory: appSupportDirectory)
            guard let data = try? Data(contentsOf: storeURL),
                  let records = try? JSONDecoder().decode([StoredHistoryRecord].self, from: data) else {
                return []
            }
            let fm = FileManager.default
            let iso = ISO8601DateFormatter()
            var loaded: [ClipboardEntry] = []
            loaded.reserveCapacity(records.count)
            for rec in records {
                if let entry = decodeRecord(rec, fm: fm, iso: iso) {
                    loaded.append(entry)
                }
            }
            return ClipboardService.pruneAndCap(loaded, maxUnpinned: max(1, maxUnpinned), ttl: ttl, now: now)
        }
    }

    public static func loadMergedEntries(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory(),
        maxUnpinned: Int = 80,
        ttl: ClipboardRetentionTTL = .forever,
        now: Date = Date()
    ) -> [ClipboardEntry] {
        let pinned = ClipboardPersistenceStore.loadPinnedEntries(appSupportDirectory: appSupportDirectory)
        let history = loadHistoryEntries(appSupportDirectory: appSupportDirectory, maxUnpinned: maxUnpinned, ttl: ttl, now: now)
        var seen = Set<UUID>()
        var merged: [ClipboardEntry] = []
        for item in pinned where seen.insert(item.id).inserted { merged.append(item) }
        for item in history where seen.insert(item.id).inserted { merged.append(item) }
        return merged.sorted { $0.capturedAt > $1.capturedAt }
    }

    private static func encodeRecord(_ item: ClipboardEntry, iso: ISO8601DateFormatter) -> StoredHistoryRecord {
        let ts = iso.string(from: item.capturedAt)
        switch item.payloadKind {
        case .text:
            return StoredHistoryRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .text, capturedAtISO8601: ts, textValue: item.textValue, colorHex: nil, filePaths: nil, imageWidth: nil, imageHeight: nil)
        case .colorHex(let hex):
            return StoredHistoryRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .colorHex, capturedAtISO8601: ts, textValue: item.textValue ?? hex, colorHex: hex, filePaths: nil, imageWidth: nil, imageHeight: nil)
        case .image(let u, let size):
            return StoredHistoryRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .image, capturedAtISO8601: ts, textValue: nil, colorHex: nil, filePaths: [u.standardizedFileURL.path], imageWidth: Double(size.width), imageHeight: Double(size.height))
        case .video:
            return StoredHistoryRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .video, capturedAtISO8601: ts, textValue: nil, colorHex: nil, filePaths: item.fileURLs.map(\.standardizedFileURL.path), imageWidth: nil, imageHeight: nil)
        case .file:
            return StoredHistoryRecord(id: item.id.uuidString, title: item.title, subtitle: item.subtitle, kind: .file, capturedAtISO8601: ts, textValue: nil, colorHex: nil, filePaths: item.fileURLs.map(\.standardizedFileURL.path), imageWidth: nil, imageHeight: nil)
        }
    }

    private static func decodeRecord(_ rec: StoredHistoryRecord, fm: FileManager, iso: ISO8601DateFormatter) -> ClipboardEntry? {
        let uuid = UUID(uuidString: rec.id) ?? UUID()
        let captured = iso.date(from: rec.capturedAtISO8601) ?? Date()
        switch rec.kind {
        case .text:
            return ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, textValue: rec.textValue, capturedAt: captured, isPinned: false, payloadKind: .text)
        case .colorHex:
            let hex = rec.colorHex ?? rec.textValue ?? "#000000"
            return ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, textValue: rec.textValue ?? hex, capturedAt: captured, isPinned: false, payloadKind: .colorHex(hex))
        case .image:
            guard let path = rec.filePaths?.first, fm.fileExists(atPath: path) else { return nil }
            let u = URL(fileURLWithPath: path).standardizedFileURL
            let dims = MediaClassifier.readImageDimensions(at: u) ?? CGSize(width: rec.imageWidth ?? 0, height: rec.imageHeight ?? 0)
            return ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, fileURL: u, capturedAt: captured, isPinned: false, payloadKind: .image(u, dims))
        case .video:
            let urls = (rec.filePaths ?? []).filter { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0).standardizedFileURL }
            guard let first = urls.first else { return nil }
            return ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, fileURL: first, fileURLs: urls, capturedAt: captured, isPinned: false, payloadKind: .video(first))
        case .file:
            let urls = (rec.filePaths ?? []).filter { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0).standardizedFileURL }
            guard let first = urls.first else { return nil }
            return ClipboardEntry(id: uuid, title: rec.title, subtitle: rec.subtitle, fileURL: first, fileURLs: urls, capturedAt: captured, isPinned: false, payloadKind: .file(first))
        }
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
            let dest = mediaDir.appendingPathComponent("hist-\(item.id.uuidString)\(suffix).\(ext)", isDirectory: false).standardizedFileURL
            if dest.path != std.path {
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.copyItem(at: std, to: dest)
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                }
                if fm.fileExists(atPath: dest.path) {
                    nextURLs.append(dest); changed = true; continue
                }
            }
            nextURLs.append(std)
        }
        guard changed, let first = nextURLs.first else { return item }
        let nextKind: ClipboardPayloadKind = switch item.payloadKind {
        case .image(_, let sz): .image(first, sz)
        case .video: .video(first)
        case .file: .file(first)
        case .text, .colorHex: item.payloadKind
        }
        return ClipboardEntry(
            id: item.id, title: item.title, subtitle: item.subtitle, textValue: item.textValue,
            fileURL: first, fileURLs: nextURLs, capturedAt: item.capturedAt, isPinned: item.isPinned, payloadKind: nextKind
        )
    }

    private static func pruneOrphanedMediaFiles(in mediaDir: URL, keeping keptPaths: Set<String>) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: mediaDir, includingPropertiesForKeys: nil) else { return }
        for u in urls where u.lastPathComponent.hasPrefix("hist-") {
            if !keptPaths.contains(u.standardizedFileURL.path) {
                try? fm.removeItem(at: u)
            }
        }
    }
}
