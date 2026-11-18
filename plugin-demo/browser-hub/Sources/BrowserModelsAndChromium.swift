import Darwin
import Foundation
import PluginKit
import SQLite3

let webkitEpochOffsetSec: Double = 11_644_473_600.0
let coreDataEpochOffsetSec: Double = 978_307_200.0

struct BrowserSpec {
    let key: String
    let label: String
    let bundleID: String
    let icon: String
    let relRoot: String
}

let browserSpecs: [String: BrowserSpec] = [
    "edge": BrowserSpec(key: "edge", label: "Edge", bundleID: "com.microsoft.edgemac", icon: "globe", relRoot: "Library/Application Support/Microsoft Edge"),
    "chrome": BrowserSpec(key: "chrome", label: "Chrome", bundleID: "com.google.Chrome", icon: "globe.americas.fill", relRoot: "Library/Application Support/Google/Chrome"),
    "safari": BrowserSpec(key: "safari", label: "Safari", bundleID: "com.apple.Safari", icon: "safari.fill", relRoot: "Library/Safari")
]

struct RawRecord {
    var kind: String
    var browser: String
    var profile: String
    var title: String
    var url: String
    var folder: String
    var visitCount: Int
    var timestamp: Double
}

struct AggregatedItem: Codable {
    var id: String
    var url: String
    var title: String
    var hasBookmark: Bool
    var hasHistory: Bool
    var browsers: [String]
    var primaryBrowser: String
    var profiles: [String]
    var folders: [String]
    var visitCount: Int
    var timestamp: Double
    var pinned: Bool
}

struct SnapshotCacheFile: Codable {
    var savedAt: Double
    var sig: String
    var safariDenied: Bool
    var browserCounts: [String: Int]
    var items: [AggregatedItem]
}

func webkitToUnix(_ rawVal: Any?) -> Double {
    let us: Int64
    if let i = rawVal as? Int64 { us = i }
    else if let i = rawVal as? Int { us = Int64(i) }
    else if let n = rawVal as? NSNumber { us = n.int64Value }
    else if let s = rawVal as? String, let parsed = Int64(s) { us = parsed }
    else { return 0.0 }
    return us > 0 ? max(0.0, (Double(us) / 1_000_000.0) - webkitEpochOffsetSec) : 0.0
}

func coreDataToUnix(_ rawVal: Double) -> Double {
    rawVal > 0 ? max(0.0, rawVal + coreDataEpochOffsetSec) : 0.0
}

func fallbackTitle(_ urlStr: String) -> String {
    guard let host = URL(string: urlStr)?.host, !host.isEmpty else { return urlStr }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

func parseEnabledBrowsers(_ rawCfg: String) -> [String] {
    let tokens = rawCfg.components(separatedBy: CharacterSet(charactersIn: ",， \t\n"))
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return ["edge", "chrome", "safari"] }
    var selected: [String] = []
    for tok in tokens {
        if tok.contains("edge") && !selected.contains("edge") { selected.append("edge") }
        else if tok.contains("chrome") && !selected.contains("chrome") { selected.append("chrome") }
        else if tok.contains("safari") && !selected.contains("safari") { selected.append("safari") }
    }
    return selected.isEmpty ? ["edge", "chrome", "safari"] : selected
}

func resolveBrowserRoots() -> [String: URL] {
    let env = ProcessInfo.processInfo.environment
    let homePath = env["LUCENT_BROWSER_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
    var roots: [String: URL] = [:]
    for (k, spec) in browserSpecs {
        if let override = env["LUCENT_\(k.uppercased())_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            roots[k] = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            roots[k] = homeURL.appendingPathComponent(spec.relRoot, isDirectory: true)
        }
    }
    return roots
}

func discoverChromiumProfiles(browserRoot: URL) -> [(dir: URL, label: String)] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: browserRoot.path, isDirectory: &isDir), isDir.boolValue else { return [] }

    var nameMap: [String: String] = [:]
    let localStateURL = browserRoot.appendingPathComponent("Local State")
    if let data = try? Data(contentsOf: localStateURL),
       let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       let profObj = json["profile"] as? [String: Any],
       let infoCache = profObj["info_cache"] as? [String: Any] {
        for (dirName, metaAny) in infoCache {
            if let meta = metaAny as? [String: Any],
               let name = (meta["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                nameMap[dirName] = name
            }
        }
    }

    var candidates: [URL] = []
    let defaultDir = browserRoot.appendingPathComponent("Default", isDirectory: true)
    if fm.fileExists(atPath: defaultDir.path, isDirectory: &isDir), isDir.boolValue { candidates.append(defaultDir) }
    if let children = try? fm.contentsOfDirectory(at: browserRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where child.lastPathComponent.hasPrefix("Profile ") {
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { candidates.append(child) }
        }
    }

    return candidates.compactMap { profDir in
        let hasBM = fm.fileExists(atPath: profDir.appendingPathComponent("Bookmarks").path)
        let hasHis = fm.fileExists(atPath: profDir.appendingPathComponent("History").path)
        guard hasBM || hasHis else { return nil }
        return (profDir, nameMap[profDir.lastPathComponent] ?? profDir.lastPathComponent)
    }
}

private func walkChromiumBookmarkNode(
    _ node: [String: Any], browserKey: String, profileLabel: String, folderChain: [String], out: inout [RawRecord]
) {
    let ntype = (node["type"] as? String) ?? ""
    if ntype == "url" {
        let urlVal = ((node["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlVal.isEmpty, !urlVal.hasPrefix("javascript:"), !urlVal.hasPrefix("place:") else { return }
        let rawName = ((node["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUsed = webkitToUnix(node["date_last_used"])
        let added = lastUsed > 0 ? lastUsed : webkitToUnix(node["date_added"])
        out.append(RawRecord(
            kind: "bookmark", browser: browserKey, profile: profileLabel,
            title: rawName.isEmpty ? fallbackTitle(urlVal) : rawName, url: urlVal,
            folder: folderChain.joined(separator: " / "), visitCount: 1, timestamp: added
        ))
        return
    }
    if let children = node["children"] as? [[String: Any]] {
        let name = ((node["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nextChain = name.isEmpty ? folderChain : (folderChain + [name])
        for child in children {
            walkChromiumBookmarkNode(child, browserKey: browserKey, profileLabel: profileLabel, folderChain: nextChain, out: &out)
        }
    }
}

func readChromiumBookmarks(fileURL: URL, browserKey: String, profileLabel: String) -> [RawRecord] {
    guard let data = try? Data(contentsOf: fileURL),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let roots = json["roots"] as? [String: Any] else { return [] }
    var out: [RawRecord] = []
    for rootKey in ["bookmark_bar", "other", "synced"] {
        if let rootNode = roots[rootKey] as? [String: Any] {
            walkChromiumBookmarkNode(rootNode, browserKey: browserKey, profileLabel: profileLabel, folderChain: [], out: &out)
        }
    }
    return out
}

enum SnapshotDBError: Error {
    case permissionDenied
    case openFailed
}

func withStagedSQLiteDB<T>(dbURL: URL, body: (OpaquePointer) -> T) throws -> T? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dbURL.path) else { return nil }
    if !fm.isReadableFile(atPath: dbURL.path) { throw SnapshotDBError.permissionDenied }

    let scratch = fm.temporaryDirectory.appendingPathComponent("lk-bh-db-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: scratch) }

    let stagedDB = scratch.appendingPathComponent(dbURL.lastPathComponent)
    do {
        try fm.copyItem(at: dbURL, to: stagedDB)
    } catch let err as NSError {
        if (err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError)
            || (err.domain == NSPOSIXErrorDomain && (err.code == EACCES || err.code == EPERM)) {
            throw SnapshotDBError.permissionDenied
        }
        return nil
    }
    for suffix in ["-wal", "-shm"] {
        let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
        if fm.fileExists(atPath: sidecar.path) { try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: stagedDB.path + suffix)) }
    }

    var db: OpaquePointer? = nil
    guard sqlite3_open_v2(stagedDB.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let conn = db else {
        if let db { sqlite3_close(db) }
        throw SnapshotDBError.openFailed
    }
    defer { sqlite3_close(conn) }
    sqlite3_busy_timeout(conn, 2500)
    sqlite3_exec(conn, "PRAGMA query_only = ON;", nil, nil, nil)
    return body(conn)
}

func sqliteColumnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
    guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
    return String(cString: cStr)
}

func readChromiumHistory(
    historyDB: URL, browserKey: String, profileLabel: String,
    cutoffUnix: Double, limit: Int = 400, deniedSink: inout Set<String>
) -> [RawRecord] {
    let minWebkitUS = Int64((cutoffUnix + webkitEpochOffsetSec) * 1_000_000.0)
    let sql = "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 AND last_visit_time >= ? ORDER BY last_visit_time DESC LIMIT ?"
    do {
        let rows = try withStagedSQLiteDB(dbURL: historyDB) { conn -> [RawRecord] in
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return [] }
            defer { sqlite3_finalize(s) }
            sqlite3_bind_int64(s, 1, minWebkitUS)
            sqlite3_bind_int(s, 2, Int32(limit))

            var list: [RawRecord] = []
            let blockedPrefixes = ["chrome://", "edge://", "about:", "devtools://", "chrome-extension://", "extension://"]
            while sqlite3_step(s) == SQLITE_ROW {
                let urlVal = sqliteColumnText(s, 0).trimmingCharacters(in: .whitespacesAndNewlines)
                if urlVal.isEmpty || blockedPrefixes.contains(where: { urlVal.hasPrefix($0) }) { continue }
                let rawTitle = sqliteColumnText(s, 1).trimmingCharacters(in: .whitespacesAndNewlines)
                list.append(RawRecord(
                    kind: "history", browser: browserKey, profile: profileLabel,
                    title: rawTitle.isEmpty ? fallbackTitle(urlVal) : rawTitle, url: urlVal, folder: "",
                    visitCount: max(1, Int(sqlite3_column_int(s, 2))), timestamp: webkitToUnix(sqlite3_column_int64(s, 3))
                ))
            }
            return list
        }
        return rows ?? []
    } catch SnapshotDBError.permissionDenied {
        deniedSink.insert(browserKey); return []
    } catch { return [] }
}
