import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public extension Notification.Name {
    static let lumakeyScriptsDidChange = Notification.Name("com.queensu.lumakey.scriptsDidChange")
}

public struct ScriptLibraryIndex: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var seededDefaults: Bool
    public var scripts: [ScriptRecord]

    public init(schemaVersion: Int = 1, seededDefaults: Bool = false, scripts: [ScriptRecord] = []) {
        self.schemaVersion = schemaVersion
        self.seededDefaults = seededDefaults
        self.scripts = scripts
    }
}

public struct ScriptMatch: Identifiable, Sendable, Hashable {
    public var id: String { script.id }
    public let script: ScriptRecord
    public let trailingQuery: String
    public let score: Int

    public init(script: ScriptRecord, trailingQuery: String, score: Int) {
        self.script = script
        self.trailingQuery = trailingQuery
        self.score = score
    }
}

public final class ScriptLibraryStore: @unchecked Sendable {
    public static let shared = ScriptLibraryStore()
    public static let indexFileName = "scripts-library.json"
    public static let distributedReloadNotificationName = Notification.Name("com.queensu.lumakey.scriptsDidChange.distributed")

    public let scriptsDirectory: URL
    public let indexFileURL: URL
    private let lock = NSLock()
    private var cached: [ScriptRecord]?

    public static func defaultScriptsDirectory(
        appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent("Scripts", isDirectory: true)
    }

    public static func defaultIndexFileURL(
        appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent(indexFileName, isDirectory: false)
    }

    public static func scopedPaths(forPluginsRoot pluginsRoot: URL) -> (scriptsDir: URL, indexURL: URL) {
        let std = pluginsRoot.standardizedFileURL
        let base = std.lastPathComponent == "Plugins" ? std.deletingLastPathComponent() : std
        return (
            base.appendingPathComponent("Scripts", isDirectory: true),
            base.appendingPathComponent(indexFileName, isDirectory: false)
        )
    }

    public init(
        scriptsDirectory: URL = ScriptLibraryStore.defaultScriptsDirectory(),
        indexFileURL: URL = ScriptLibraryStore.defaultIndexFileURL()
    ) {
        self.scriptsDirectory = scriptsDirectory
        self.indexFileURL = indexFileURL
    }

    public func allScripts(includeDisabled: Bool = true) -> [ScriptRecord] {
        let list = lock.withLock { () -> [ScriptRecord] in
            if let cached { return cached }
            let synced = syncWithDiskUnlocked()
            cached = synced
            return synced
        }
        return includeDisabled ? list : list.filter(\.isEnabled)
    }

    @discardableResult
    public func syncWithDisk() -> [ScriptRecord] {
        lock.withLock {
            let synced = syncWithDiskUnlocked()
            cached = synced
            return synced
        }
    }

    public func scriptURL(for record: ScriptRecord) -> URL {
        scriptsDirectory.appendingPathComponent(record.fileName, isDirectory: false)
    }

    public func readCode(for record: ScriptRecord) -> String {
        (try? String(contentsOf: scriptURL(for: record), encoding: .utf8)) ?? ""
    }

    public func readCustomIconSVG(for record: ScriptRecord) -> String? {
        guard let url = record.customIconURL(in: scriptsDirectory),
              url.pathExtension.lowercased() == "svg" else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    public func upsert(
        _ draft: ScriptRecord,
        code: String,
        iconSvg: String? = nil,
        clearCustomIconSvg: Bool = false,
        notifyInProcess: Bool = true,
        notifyCrossProcess: Bool = false
    ) throws -> ScriptRecord {
        let cleanSVG: String? = if let rawSVG = iconSvg, !rawSVG.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try ScriptHeaderParser.validateSafeSVG(rawSVG)
        } else {
            nil
        }

        let saved = try lock.withLock { () -> ScriptRecord in
            var index = loadIndexUnlocked()
            if !index.seededDefaults && index.scripts.isEmpty {
                index = bootstrapDefaultsUnlocked()
            }
            let fm = FileManager.default
            try fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)

            let cleanID = ScriptHeaderParser.isSafeScriptID(draft.id)
                ? draft.id
                : ScriptHeaderParser.sanitizeSlug(draft.title.isEmpty ? draft.fileName : draft.title)
            var record = draft
            record.id = cleanID
            record.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if record.title.isEmpty { record.title = cleanID }
            record.subtitle = draft.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            record.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "效率" : draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
            record.keywords = draft.keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            record.timeoutSeconds = min(max(draft.timeoutSeconds, 3.0), 30.0)
            record.updatedAt = Date()

            let resolvedFileName = Self.resolveSafeFileName(preferred: draft.fileName, id: cleanID, runtime: draft.runtime)
            if let existing = index.scripts.first(where: { $0.id == cleanID }), existing.fileName != resolvedFileName {
                try? fm.removeItem(at: scriptsDirectory.appendingPathComponent(existing.fileName))
            }
            record.fileName = resolvedFileName

            if let cleanSVG {
                let iconsDir = scriptsDirectory.appendingPathComponent("icons", isDirectory: true)
                try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                let svgURL = iconsDir.appendingPathComponent("\(cleanID).svg", isDirectory: false)
                try Data(cleanSVG.utf8).write(to: svgURL, options: .atomic)
                record.icon = "icons/\(cleanID).svg"
            } else if clearCustomIconSvg {
                let svgURL = scriptsDirectory.appendingPathComponent("icons/\(cleanID).svg", isDirectory: false)
                try? fm.removeItem(at: svgURL)
                if record.icon.hasPrefix("icons/") { record.icon = "terminal.fill" }
            }

            let syncedCode = ScriptHeaderParser.syncExistingDirectives(in: code, with: record)
            let targetURL = scriptsDirectory.appendingPathComponent(resolvedFileName, isDirectory: false)
            try Data(syncedCode.utf8).write(to: targetURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
            record.lastSyncedHash = ScriptHeaderParser.contentSHA256(syncedCode)

            if let idx = index.scripts.firstIndex(where: { $0.id == cleanID }) {
                index.scripts[idx] = record
            } else {
                index.scripts.insert(record, at: 0)
            }
            index.seededDefaults = true
            try saveIndexUnlocked(index)
            cached = index.scripts
            return record
        }
        postNotifications(inProcess: notifyInProcess, crossProcess: notifyCrossProcess)
        return saved
    }

    public func delete(id: String, notifyInProcess: Bool = true, notifyCrossProcess: Bool = false) throws {
        try lock.withLock {
            var index = loadIndexUnlocked()
            let fm = FileManager.default
            if let existing = index.scripts.first(where: { $0.id == id }) {
                try? fm.removeItem(at: scriptsDirectory.appendingPathComponent(existing.fileName))
                let svgURL = scriptsDirectory.appendingPathComponent("icons/\(id).svg")
                try? fm.removeItem(at: svgURL)
            }
            index.scripts.removeAll { $0.id == id }
            index.seededDefaults = true
            try saveIndexUnlocked(index)
            cached = index.scripts
        }
        postNotifications(inProcess: notifyInProcess, crossProcess: notifyCrossProcess)
    }

    @discardableResult
    public func resetStarterScripts(notifyInProcess: Bool = true) throws -> [ScriptRecord] {
        let list = try lock.withLock { () -> [ScriptRecord] in
            var index = loadIndexUnlocked()
            let fm = FileManager.default
            try fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
            for (tpl, code, svg) in Self.starterTemplates() {
                let url = scriptsDirectory.appendingPathComponent(tpl.fileName)
                try Data(code.utf8).write(to: url, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                var rec = tpl
                rec.lastSyncedHash = ScriptHeaderParser.contentSHA256(code)
                if let svg {
                    let iconsDir = scriptsDirectory.appendingPathComponent("icons", isDirectory: true)
                    try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                    try Data(svg.utf8).write(to: iconsDir.appendingPathComponent("\(tpl.id).svg"), options: .atomic)
                    rec.icon = "icons/\(tpl.id).svg"
                }
                if let idx = index.scripts.firstIndex(where: { $0.id == rec.id }) {
                    index.scripts[idx] = rec
                } else {
                    index.scripts.append(rec)
                }
            }
            index.seededDefaults = true
            try saveIndexUnlocked(index)
            cached = index.scripts
            return index.scripts
        }
        postNotifications(inProcess: notifyInProcess, crossProcess: false)
        return list
    }

    func loadIndexUnlocked() -> ScriptLibraryIndex {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode(ScriptLibraryIndex.self, from: data) else {
            return ScriptLibraryIndex()
        }
        return decoded
    }

    func saveIndexUnlocked(_ index: ScriptLibraryIndex) throws {
        try FileManager.default.createDirectory(at: indexFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(index)
        try data.write(to: indexFileURL, options: .atomic)
    }

    private func postNotifications(inProcess: Bool, crossProcess: Bool) {
        if inProcess { NotificationCenter.default.post(name: .lumakeyScriptsDidChange, object: nil) }
        if crossProcess {
            DistributedNotificationCenter.default().postNotificationName(
                Self.distributedReloadNotificationName,
                object: indexFileURL.standardizedFileURL.path,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }
}
