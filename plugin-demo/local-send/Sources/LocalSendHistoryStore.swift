import Darwin
import Foundation

struct LocalSendHistoryEntry: Codable, Sendable, Equatable {
    let id: String
    let direction: String
    let peerAlias: String
    let kind: String
    let label: String
    let filePaths: [String]
    let text: String
    let totalBytes: Int64
    let timestampEpoch: Double

    func toJSONObject(checkFileExistence: Bool) -> [String: Any] {
        let fm = FileManager.default
        let existingPaths = checkFileExistence
            ? filePaths.filter { fm.fileExists(atPath: $0) }
            : filePaths
        return [
            "id": id,
            "direction": direction,
            "peerAlias": peerAlias,
            "kind": kind,
            "label": label,
            "filePaths": filePaths,
            "existingPaths": existingPaths,
            "missingFiles": !filePaths.isEmpty && existingPaths.isEmpty,
            "text": text,
            "totalBytes": totalBytes,
            "timestampEpoch": timestampEpoch
        ]
    }
}

/// 零常驻本地传输历史持久化（仅保存在 `PluginData/local-send/history.json`，0600 权限，最多保留 40 条）。
final class LocalSendHistoryStore: @unchecked Sendable {
    static let maxEntries = 40
    private static let maxStoredTextChars = 4_000
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "tiff"]

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [LocalSendHistoryEntry]

    init(dataDirectory: URL) {
        self.fileURL = dataDirectory.appendingPathComponent("history.json")
        self.entries = Self.loadEntries(from: fileURL)
    }

    func snapshot() -> [[String: Any]] {
        let copy = lock.withLock { entries }
        return copy.map { $0.toJSONObject(checkFileExistence: true) }
    }

    @discardableResult
    func record(completedEvent ev: [String: Any]) -> LocalSendHistoryEntry? {
        guard let entry = Self.buildEntry(from: ev) else { return nil }
        let updated: [LocalSendHistoryEntry] = lock.withLock {
            entries.removeAll { $0.id == entry.id }
            entries.insert(entry, at: 0)
            if entries.count > Self.maxEntries {
                entries = Array(entries.prefix(Self.maxEntries))
            }
            return entries
        }
        saveEntries(updated)
        return entry
    }

    func remove(id: String) {
        let updated: [LocalSendHistoryEntry] = lock.withLock {
            entries.removeAll { $0.id == id }
            return entries
        }
        saveEntries(updated)
    }

    func clear() {
        lock.withLock { entries.removeAll() }
        saveEntries([])
    }

    private static func buildEntry(from ev: [String: Any]) -> LocalSendHistoryEntry? {
        let direction = (ev["direction"] as? String) ?? "receive"
        let id = (ev["transferId"] as? String) ?? (ev["sessionId"] as? String) ?? UUID().uuidString
        let peerAlias = (ev["peerAlias"] as? String) ?? ""
        let rawPaths = (ev["filePaths"] as? [String]) ?? []
        let rawText = (ev["text"] as? String) ?? ""
        let text = rawText.count > maxStoredTextChars ? String(rawText.prefix(maxStoredTextChars)) : rawText
        let totalBytes = (ev["totalBytes"] as? NSNumber)?.int64Value ?? Int64(text.utf8.count)
        let timestamp = (ev["timestampEpoch"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970

        let kind: String
        if let explicitKind = ev["kind"] as? String, !explicitKind.isEmpty {
            kind = explicitKind
        } else if !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isURL = URL(string: trimmed).flatMap { ($0.scheme == "http" || $0.scheme == "https") && $0.host != nil } ?? false
            kind = isURL ? "url" : "text"
        } else if rawPaths.count == 1 {
            let ext = URL(fileURLWithPath: rawPaths[0]).pathExtension.lowercased()
            kind = imageExtensions.contains(ext) ? "image" : "file"
        } else {
            kind = "file"
        }

        let label: String
        if !text.isEmpty {
            label = String(text.replacingOccurrences(of: "\n", with: " ").prefix(48))
        } else if rawPaths.count == 1 {
            label = URL(fileURLWithPath: rawPaths[0]).lastPathComponent
        } else if rawPaths.count > 1 {
            label = "\(URL(fileURLWithPath: rawPaths[0]).lastPathComponent) 等 \(rawPaths.count) 项"
        } else {
            label = "传输项"
        }

        return LocalSendHistoryEntry(
            id: id,
            direction: direction,
            peerAlias: peerAlias,
            kind: kind,
            label: label,
            filePaths: rawPaths,
            text: text,
            totalBytes: max(0, totalBytes),
            timestampEpoch: timestamp
        )
    }

    private static func loadEntries(from url: URL) -> [LocalSendHistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LocalSendHistoryEntry].self, from: data) else {
            return []
        }
        return Array(decoded.prefix(maxEntries))
    }

    private func saveEntries(_ list: [LocalSendHistoryEntry]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
        Darwin.chmod(fileURL.path, 0o600)
    }
}
