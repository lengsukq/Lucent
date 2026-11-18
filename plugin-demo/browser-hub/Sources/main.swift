import Darwin
import Foundation
import PluginKit
import SQLite3

private let webkitEpochOffsetSec: Double = 11_644_473_600.0
private let coreDataEpochOffsetSec: Double = 978_307_200.0
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct BrowserSpec {
    let key: String
    let label: String
    let bundleID: String
    let icon: String
    let relRoot: String
}

private let browserSpecs: [String: BrowserSpec] = [
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

private func webkitToUnix(_ rawVal: Any?) -> Double {
    let us: Int64
    if let i = rawVal as? Int64 { us = i }
    else if let i = rawVal as? Int { us = Int64(i) }
    else if let n = rawVal as? NSNumber { us = n.int64Value }
    else if let s = rawVal as? String, let parsed = Int64(s) { us = parsed }
    else { return 0.0 }
    guard us > 0 else { return 0.0 }
    return max(0.0, (Double(us) / 1_000_000.0) - webkitEpochOffsetSec)
}

private func coreDataToUnix(_ rawVal: Double) -> Double {
    guard rawVal > 0 else { return 0.0 }
    return max(0.0, rawVal + coreDataEpochOffsetSec)
}

private func fallbackTitle(_ urlStr: String) -> String {
    guard let host = URL(string: urlStr)?.host, !host.isEmpty else { return urlStr }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

private func parseEnabledBrowsers(_ rawCfg: String) -> [String] {
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

private func resolveBrowserRoots() -> [String: URL] {
    let env = ProcessInfo.processInfo.environment
    let homePath = env["LUMAKEY_BROWSER_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
    let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
    var roots: [String: URL] = [:]
    for (k, spec) in browserSpecs {
        if let override = env["LUMAKEY_\(k.uppercased())_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            roots[k] = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            roots[k] = homeURL.appendingPathComponent(spec.relRoot, isDirectory: true)
        }
    }
    return roots
}

private func discoverChromiumProfiles(browserRoot: URL) -> [(dir: URL, label: String)] {
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
               let name = (meta["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                nameMap[dirName] = name
            }
        }
    }

    var candidates: [URL] = []
    let defaultDir = browserRoot.appendingPathComponent("Default", isDirectory: true)
    if fm.fileExists(atPath: defaultDir.path, isDirectory: &isDir), isDir.boolValue {
        candidates.append(defaultDir)
    }
    if let children = try? fm.contentsOfDirectory(at: browserRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if child.lastPathComponent.hasPrefix("Profile "),
               ((try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) {
                candidates.append(child)
            }
        }
    }

    var out: [(URL, String)] = []
    for profDir in candidates {
        let hasBM = fm.fileExists(atPath: profDir.appendingPathComponent("Bookmarks").path)
        let hasHis = fm.fileExists(atPath: profDir.appendingPathComponent("History").path)
        if hasBM || hasHis {
            let label = nameMap[profDir.lastPathComponent] ?? profDir.lastPathComponent
            out.append((profDir, label))
        }
    }
    return out
}

private func walkChromiumBookmarkNode(
    _ node: [String: Any],
    browserKey: String,
    profileLabel: String,
    folderChain: [String],
    out: inout [RawRecord]
) {
    let ntype = (node["type"] as? String) ?? ""
    if ntype == "url" {
        let urlVal = ((node["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlVal.isEmpty, !urlVal.hasPrefix("javascript:"), !urlVal.hasPrefix("place:") else { return }
        let rawName = ((node["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawName.isEmpty ? fallbackTitle(urlVal) : rawName
        let lastUsed = webkitToUnix(node["date_last_used"])
        let added = lastUsed > 0 ? lastUsed : webkitToUnix(node["date_added"])
        out.append(RawRecord(
            kind: "bookmark",
            browser: browserKey,
            profile: profileLabel,
            title: title,
            url: urlVal,
            folder: folderChain.joined(separator: " / "),
            visitCount: 1,
            timestamp: added
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

private func readChromiumBookmarks(fileURL: URL, browserKey: String, profileLabel: String) -> [RawRecord] {
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

private enum SnapshotDBError: Error {
    case permissionDenied
    case openFailed
}

private func withStagedSQLiteDB<T>(dbURL: URL, body: (OpaquePointer) -> T) throws -> T? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dbURL.path) else { return nil }
    if !fm.isReadableFile(atPath: dbURL.path) {
        throw SnapshotDBError.permissionDenied
    }

    let scratch = fm.temporaryDirectory.appendingPathComponent("lk-bh-db-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: scratch) }

    let stagedDB = scratch.appendingPathComponent(dbURL.lastPathComponent)
    do {
        try fm.copyItem(at: dbURL, to: stagedDB)
    } catch let err as NSError {
        if err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError {
            throw SnapshotDBError.permissionDenied
        }
        if err.domain == NSPOSIXErrorDomain && (err.code == EACCES || err.code == EPERM) {
            throw SnapshotDBError.permissionDenied
        }
        return nil
    }

    for suffix in ["-wal", "-shm"] {
        let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
        if fm.fileExists(atPath: sidecar.path) {
            try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: stagedDB.path + suffix))
        }
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

private func sqliteColumnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
    guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
    return String(cString: cStr)
}

private func readChromiumHistory(
    historyDB: URL,
    browserKey: String,
    profileLabel: String,
    cutoffUnix: Double,
    limit: Int = 400,
    deniedSink: inout Set<String>
) -> [RawRecord] {
    let minWebkitUS = Int64((cutoffUnix + webkitEpochOffsetSec) * 1_000_000.0)
    let sql = """
        SELECT url, title, visit_count, last_visit_time
        FROM urls
        WHERE hidden = 0 AND last_visit_time >= ?
        ORDER BY last_visit_time DESC
        LIMIT ?
    """
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
                let vcount = max(1, Int(sqlite3_column_int(s, 2)))
                let lastVT = sqlite3_column_int64(s, 3)
                list.append(RawRecord(
                    kind: "history",
                    browser: browserKey,
                    profile: profileLabel,
                    title: rawTitle.isEmpty ? fallbackTitle(urlVal) : rawTitle,
                    url: urlVal,
                    folder: "",
                    visitCount: vcount,
                    timestamp: webkitToUnix(lastVT)
                ))
            }
            return list
        }
        return rows ?? []
    } catch SnapshotDBError.permissionDenied {
        deniedSink.insert(browserKey)
        return []
    } catch {
        return []
    }
}

private func walkSafariPlistNode(_ node: [String: Any], folderChain: [String], out: inout [RawRecord]) {
    let btype = (node["WebBookmarkType"] as? String) ?? ""
    if btype == "WebBookmarkTypeLeaf" {
        let urlVal = ((node["URLString"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlVal.isEmpty, !urlVal.hasPrefix("javascript:") else { return }
        let uriDict = node["URIDictionary"] as? [String: Any]
        let reading = node["ReadingList"] as? [String: Any]
        let uriTitle = ((uriDict?["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nodeTitle = ((node["Title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = !uriTitle.isEmpty ? uriTitle : (!nodeTitle.isEmpty ? nodeTitle : fallbackTitle(urlVal))
        let ts = (reading?["DateAdded"] as? Date)?.timeIntervalSince1970 ?? 0.0
        out.append(RawRecord(
            kind: "bookmark",
            browser: "safari",
            profile: folderChain.contains("Reading List") ? "Reading List" : "Default",
            title: title,
            url: urlVal,
            folder: folderChain.joined(separator: " / "),
            visitCount: 1,
            timestamp: ts
        ))
        return
    }
    if let children = node["Children"] as? [[String: Any]] {
        let rawTitle = ((node["Title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let friendlyMap = [
            "BookmarksBar": "个人收藏",
            "BookmarksMenu": "书签菜单",
            "com.apple.ReadingList": "Reading List"
        ]
        let friendly = friendlyMap[rawTitle] ?? rawTitle
        let nextChain = (!friendly.isEmpty && friendly != "Root") ? (folderChain + [friendly]) : folderChain
        for child in children {
            walkSafariPlistNode(child, folderChain: nextChain, out: &out)
        }
    }
}

private func readSafariStore(safariDir: URL, cutoffUnix: Double, limit: Int = 400) -> (records: [RawRecord], denied: Bool) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: safariDir.path) else { return ([], false) }

    var records: [RawRecord] = []
    var permissionDenied = false

    let plistURL = safariDir.appendingPathComponent("Bookmarks.plist")
    if fm.fileExists(atPath: plistURL.path) {
        if !fm.isReadableFile(atPath: plistURL.path) {
            permissionDenied = true
        } else {
            do {
                let data = try Data(contentsOf: plistURL)
                if let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    walkSafariPlistNode(root, folderChain: [], out: &records)
                }
            } catch let err as NSError {
                if (err.domain == NSCocoaErrorDomain && err.code == NSFileReadNoPermissionError)
                    || (err.domain == NSPOSIXErrorDomain && (err.code == EACCES || err.code == EPERM)) {
                    permissionDenied = true
                }
            }
        }
    }

    let histDB = safariDir.appendingPathComponent("History.db")
    let minCD = cutoffUnix - coreDataEpochOffsetSec
    let sql = """
        SELECT hi.url, COALESCE(MAX(hv.title), ''), hi.visit_count, MAX(hv.visit_time) AS last_vt
        FROM history_items hi
        JOIN history_visits hv ON hv.history_item = hi.id
        WHERE hv.visit_time >= ?
        GROUP BY hi.id
        ORDER BY last_vt DESC
        LIMIT ?
    """
    if fm.fileExists(atPath: histDB.path) {
        do {
            if let rows = try withStagedSQLiteDB(dbURL: histDB, body: { conn -> [RawRecord] in
                var stmt: OpaquePointer? = nil
                guard sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return [] }
                defer { sqlite3_finalize(s) }
                sqlite3_bind_double(s, 1, minCD)
                sqlite3_bind_int(s, 2, Int32(limit))

                var list: [RawRecord] = []
                while sqlite3_step(s) == SQLITE_ROW {
                    let urlVal = sqliteColumnText(s, 0).trimmingCharacters(in: .whitespacesAndNewlines)
                    if urlVal.isEmpty || urlVal.hasPrefix("safari-resource:") || urlVal.hasPrefix("about:") { continue }
                    let rawTitle = sqliteColumnText(s, 1).trimmingCharacters(in: .whitespacesAndNewlines)
                    let vcount = max(1, Int(sqlite3_column_int(s, 2)))
                    let lastVT = sqlite3_column_double(s, 3)
                    list.append(RawRecord(
                        kind: "history",
                        browser: "safari",
                        profile: "Default",
                        title: rawTitle.isEmpty ? fallbackTitle(urlVal) : rawTitle,
                        url: urlVal,
                        folder: "",
                        visitCount: vcount,
                        timestamp: coreDataToUnix(lastVT)
                    ))
                }
                return list
            }) {
                records.append(contentsOf: rows)
            }
        } catch SnapshotDBError.permissionDenied {
            permissionDenied = true
        } catch {}
    }

    if records.isEmpty && !fm.isReadableFile(atPath: safariDir.path) {
        permissionDenied = true
    }
    return (records, permissionDenied)
}

private func normalizeURLKey(_ urlVal: String) -> String {
    let slashCount = urlVal.filter { $0 == "/" }.count
    if slashCount >= 3 && urlVal.hasSuffix("/") {
        return String(urlVal.dropLast())
    }
    return urlVal
}

private func aggregateRecords(_ rawRecords: [RawRecord], pinnedURLs: Set<String>) -> [AggregatedItem] {
    var merged: [String: AggregatedItem] = [:]
    var orderKeys: [String] = []

    for rec in rawRecords {
        let urlVal = rec.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlVal.isEmpty else { continue }
        let normKey = normalizeURLKey(urlVal)
        let isBM = (rec.kind == "bookmark")
        let bLabel = browserSpecs[rec.browser]?.label ?? rec.browser
        let profTag = rec.profile != "Default" ? "\(bLabel)(\(rec.profile))" : bLabel

        if var existing = merged[normKey] {
            if isBM && !existing.hasBookmark {
                if !rec.title.isEmpty { existing.title = rec.title }
                existing.primaryBrowser = rec.browser
            }
            existing.hasBookmark = existing.hasBookmark || isBM
            existing.hasHistory = existing.hasHistory || !isBM
            if !existing.browsers.contains(rec.browser) { existing.browsers.append(rec.browser) }
            if !existing.profiles.contains(profTag) { existing.profiles.append(profTag) }
            if !rec.folder.isEmpty && !existing.folders.contains(rec.folder) { existing.folders.append(rec.folder) }
            existing.visitCount = max(existing.visitCount, rec.visitCount)
            existing.timestamp = max(existing.timestamp, rec.timestamp)
            merged[normKey] = existing
        } else {
            let uid = String(DigestUtils.sha1Hex(normKey).prefix(12))
            orderKeys.append(normKey)
            merged[normKey] = AggregatedItem(
                id: uid,
                url: urlVal,
                title: rec.title,
                hasBookmark: isBM,
                hasHistory: !isBM,
                browsers: [rec.browser],
                primaryBrowser: rec.browser,
                profiles: [profTag],
                folders: rec.folder.isEmpty ? [] : [rec.folder],
                visitCount: max(1, rec.visitCount),
                timestamp: rec.timestamp,
                pinned: pinnedURLs.contains(urlVal) || pinnedURLs.contains(normKey)
            )
        }
    }

    let now = Date().timeIntervalSince1970
    var items = orderKeys.compactMap { merged[$0] }
    items.sort { a, b in
        if a.pinned != b.pinned { return a.pinned }
        func score(_ it: AggregatedItem) -> Double {
            let ageHours = it.timestamp > 0 ? max(0.0, (now - it.timestamp) / 3600.0) : 720.0
            let recency = 40.0 / (1.0 + ageHours / 24.0)
            let freq = log2(Double(max(1, it.visitCount) + 1)) * 12.0
            let bmBonus = it.hasBookmark ? 35.0 : 0.0
            return bmBonus + recency + freq
        }
        return score(a) > score(b)
    }
    return items
}

private func loadPinnedURLs(dataDir: URL?) -> Set<String> {
    guard let pinFile = dataDir?.appendingPathComponent("pinned-urls.json"),
          let data = try? Data(contentsOf: pinFile),
          let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return Set(arr.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
}

private func togglePinnedURL(dataDir: URL?, targetURL: String) -> Bool {
    guard let dataDir, !targetURL.isEmpty else { return false }
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    var pins = loadPinnedURLs(dataDir: dataDir)
    let nowPinned: Bool
    if pins.contains(targetURL) {
        pins.remove(targetURL)
        nowPinned = false
    } else {
        pins.insert(targetURL)
        nowPinned = true
    }
    if let data = try? PluginOutput.encodeJSON(pins.sorted(), pretty: true) {
        try? data.write(to: dataDir.appendingPathComponent("pinned-urls.json"), options: .atomic)
    }
    return nowPinned
}

private func exportLauncherSearchIndex(items: [AggregatedItem], dataDir: URL?, safariDenied: Bool) {
    guard let dataDir else { return }
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    var idxEntries: [SearchIndexItem] = []
    for item in items.prefix(420) {
        guard item.url.hasPrefix("http://") || item.url.hasPrefix("https://") else { continue }
        let domain = fallbackTitle(item.url)
        let bBadges = item.browsers.map { browserSpecs[$0]?.label ?? $0 }.joined(separator: "/")
        let folderPart = item.folders.first ?? ""
        let subParts = [bBadges, folderPart, domain].filter { !$0.isEmpty }

        var tags = item.browsers
        tags.append(item.hasBookmark ? "bookmark" : "history")
        for f in item.folders {
            for seg in f.split(separator: "/") {
                let cleanSeg = seg.trimmingCharacters(in: .whitespaces)
                if !cleanSeg.isEmpty && !tags.contains(cleanSeg) {
                    tags.append(cleanSeg)
                }
            }
        }
        let prio = item.pinned ? 85 : (item.hasBookmark ? 55 : min(45, 10 + item.visitCount * 2))
        let icon = item.pinned ? "pin.fill" : (item.hasBookmark ? "bookmark.fill" : (browserSpecs[item.primaryBrowser]?.icon ?? "globe"))
        idxEntries.append(SearchIndexItem(
            id: item.id,
            title: (item.pinned ? "⭐ " : "") + String(item.title.prefix(90)),
            subtitle: subParts.joined(separator: " · "),
            url: item.url,
            copyText: item.url,
            icon: icon,
            badge: String("\(bBadges) · \(item.hasBookmark ? "BM" : "HIS")".prefix(18)),
            tags: Array(tags.prefix(8)),
            pinned: item.pinned,
            priority: prio
        ))
    }

    PluginOutput.writeSearchIndex(idxEntries, to: dataDir.path)
    let bmCnt = items.filter(\.hasBookmark).count
    let hisCnt = items.filter(\.hasHistory).count
    let summary = "书签 \(bmCnt) · 历史 \(hisCnt)" + (safariDenied ? " (Safari 待授磁盘权限)" : "")
    PluginOutput.writeRuntimeStatus(summary: summary, badge: String(items.count), to: dataDir.path)
}

private func collectOrLoadSnapshot(
    enabledBrowsers: [String],
    historyDays: Int,
    ttlSeconds: Int,
    dataDir: URL?,
    forceRefresh: Bool
) -> (items: [AggregatedItem], browserCounts: [String: Int], safariDenied: Bool, cacheState: String) {
    let cacheFile = dataDir?.appendingPathComponent("snapshot-cache.json")
    let pins = loadPinnedURLs(dataDir: dataDir)
    let cacheSig = "\(enabledBrowsers.joined(separator: ",")):\(historyDays)"
    let now = Date().timeIntervalSince1970

    if !forceRefresh, ttlSeconds > 0, let cacheFile,
       let data = try? Data(contentsOf: cacheFile),
       let cached = try? JSONDecoder().decode(SnapshotCacheFile.self, from: data) {
        let age = now - cached.savedAt
        if age <= Double(ttlSeconds) && cached.sig == cacheSig {
            let updatedItems = cached.items.map { it -> AggregatedItem in
                var copy = it
                copy.pinned = pins.contains(it.url) || pins.contains(normalizeURLKey(it.url))
                return copy
            }
            return (updatedItems, cached.browserCounts, cached.safariDenied, "\(Int(age))s cache")
        }
    }

    let roots = resolveBrowserRoots()
    let cutoffUnix = now - Double(max(1, historyDays)) * 86_400.0
    var rawRecords: [RawRecord] = []
    var browserCounts: [String: Int] = ["edge": 0, "chrome": 0, "safari": 0]
    var safariDenied = false
    var deniedBrowsers = Set<String>()

    for bKey in enabledBrowsers {
        if bKey == "edge" || bKey == "chrome", let root = roots[bKey] {
            let profiles = discoverChromiumProfiles(browserRoot: root)
            var bRecs: [RawRecord] = []
            for (profDir, profLabel) in profiles {
                bRecs.append(contentsOf: readChromiumBookmarks(fileURL: profDir.appendingPathComponent("Bookmarks"), browserKey: bKey, profileLabel: profLabel))
                bRecs.append(contentsOf: readChromiumHistory(historyDB: profDir.appendingPathComponent("History"), browserKey: bKey, profileLabel: profLabel, cutoffUnix: cutoffUnix, deniedSink: &deniedBrowsers))
            }
            browserCounts[bKey] = bRecs.count
            rawRecords.append(contentsOf: bRecs)
        } else if bKey == "safari", let sRoot = roots["safari"] {
            let (sRecs, denied) = readSafariStore(safariDir: sRoot, cutoffUnix: cutoffUnix)
            safariDenied = denied
            if denied { deniedBrowsers.insert("safari") }
            browserCounts["safari"] = sRecs.count
            rawRecords.append(contentsOf: sRecs)
        }
    }

    let items = aggregateRecords(rawRecords, pinnedURLs: pins)
    exportLauncherSearchIndex(items: items, dataDir: dataDir, safariDenied: !deniedBrowsers.isEmpty)

    if let cacheFile {
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snap = SnapshotCacheFile(
            savedAt: now,
            sig: cacheSig,
            safariDenied: safariDenied,
            browserCounts: browserCounts,
            items: Array(items.prefix(1500))
        )
        if let encoded = try? PluginOutput.encodeJSON(snap) {
            try? encoded.write(to: cacheFile, options: .atomic)
        }
    }
    return (items, browserCounts, safariDenied, "live")
}

private func formatRelativeTime(_ unixTS: Double, isEn: Bool) -> String {
    guard unixTS > 0 else { return "" }
    let delta = max(0.0, Date().timeIntervalSince1970 - unixTS)
    if delta < 60 { return isEn ? "just now" : "刚刚" }
    if delta < 3600 {
        let m = Int(delta / 60)
        return isEn ? "\(m)m ago" : "\(m) 分钟前"
    }
    if delta < 86_400 {
        let h = Int(delta / 3600)
        return isEn ? "\(h)h ago" : "\(h) 小时前"
    }
    let d = Int(delta / 86_400)
    if d <= 30 { return isEn ? "\(d)d ago" : "\(d) 天前" }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: Date(timeIntervalSince1970: unixTS))
}

private func openURLInBrowser(browserKey: String, targetURL: String) -> Bool {
    guard targetURL.hasPrefix("http://") || targetURL.hasPrefix("https://") else { return false }
    var args: [String] = []
    if let spec = browserSpecs[browserKey] {
        args.append(contentsOf: ["-b", spec.bundleID])
    }
    args.append(targetURL)
    let res = SubprocessRunner.run(executable: "/usr/bin/open", arguments: args, timeoutSeconds: 3.0)
    if res.exitCode == 0 { return true }
    let fb = SubprocessRunner.run(executable: "/usr/bin/open", arguments: [targetURL], timeoutSeconds: 3.0)
    return fb.exitCode == 0
}

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let dataDir: URL? = input.dataDir.isEmpty ? nil : URL(fileURLWithPath: input.dataDir, isDirectory: true)

var enabledBrowsers = parseEnabledBrowsers(input.cfgString("enabledBrowsers", default: "Edge, Chrome, Safari"))
let historyDays = input.cfgInt("historyDays", default: 14, min: 1, max: 90)
let ttlSeconds = input.cfgInt("cacheTtlSeconds", default: 120, min: 0, max: 1800)
let maxRows = input.cfgInt("maxCardItems", default: 25, min: 5, max: 50)
let openInSource = input.cfgBool("openInSourceBrowser", default: false)

var forcedBrowser = ""
var forcedKind = ""
var forceRefresh = false
var didSync = false
var toastMsg: String? = nil

let argv = input.arguments
var idx = 0
while idx < argv.count {
    let arg = argv[idx]
    if arg == "--browser", idx + 1 < argv.count {
        forcedBrowser = argv[idx + 1].lowercased()
        idx += 2
        continue
    }
    if arg == "--kind", idx + 1 < argv.count {
        forcedKind = argv[idx + 1].lowercased()
        idx += 2
        continue
    }
    if arg == "--sync" {
        forceRefresh = true
        didSync = true
        idx += 1
        continue
    }
    if arg == "--toggle-pin", idx + 1 < argv.count {
        let pinnedNow = togglePinnedURL(dataDir: dataDir, targetURL: argv[idx + 1])
        forceRefresh = true
        toastMsg = isEn ? (pinnedNow ? "Pinned to top" : "Unpinned") : (pinnedNow ? "已星标置顶该网页" : "已取消置顶")
        idx += 2
        continue
    }
    if arg == "--open-in", idx + 2 < argv.count {
        let bTarget = argv[idx + 1].lowercased()
        let targetURL = argv[idx + 2]
        let ok = openURLInBrowser(browserKey: bTarget, targetURL: targetURL)
        let bName = browserSpecs[bTarget]?.label ?? bTarget
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2,
            title: isEn ? "Opened in \(bName)" : "已在 \(bName) 中打开",
            subtitle: targetURL,
            badge: ok ? "OPENED" : "ERROR",
            items: [],
            effect: PostActionEffect(
                toast: ok
                    ? (isEn ? "Opened in \(bName)" : "已调用 \(bName) 打开链接")
                    : (isEn ? "Failed to launch browser" : "调用浏览器打开失败"),
                closeOverlay: ok
            )
        ))
        exit(0)
    }
    idx += 1
}

if !forcedBrowser.isEmpty && !enabledBrowsers.contains(forcedBrowser) {
    enabledBrowsers.append(forcedBrowser)
}

let (items, bCounts, safariDenied, cacheState) = collectOrLoadSnapshot(
    enabledBrowsers: enabledBrowsers,
    historyDays: historyDays,
    ttlSeconds: ttlSeconds,
    dataDir: dataDir,
    forceRefresh: forceRefresh
)

if didSync {
    if safariDenied {
        toastMsg = isEn
            ? "Full Disk Access needed for Safari; Chrome/Edge synced"
            : "Chrome/Edge 已同步；Safari 需授予「完全磁盘访问权限」才能读取"
    } else {
        toastMsg = isEn ? "Browser search index refreshed" : "已同步刷新三端浏览器免前缀检索索引"
    }
}

var bFilter = forcedBrowser
var kFilter = forcedKind
var folderTags: [String] = []
var textTokens: [String] = []

for tok in query.split(whereSeparator: \.isWhitespace).map(String.init) {
    let low = tok.lowercased()
    if ["@edge", "edge:"].contains(low) { bFilter = "edge" }
    else if ["@chrome", "chrome:"].contains(low) { bFilter = "chrome" }
    else if ["@safari", "safari:"].contains(low) { bFilter = "safari" }
    else if ["@bm", "@bookmark", "@bookmarks", "bm:", "书签:"].contains(low) { kFilter = "bookmarks" }
    else if ["@his", "@history", "his:", "历史:"].contains(low) { kFilter = "history" }
    else if low.hasPrefix("#") && low.count > 1 { folderTags.append(String(low.dropFirst())) }
    else { textTokens.append(low) }
}

let filtered = items.filter { it in
    if !bFilter.isEmpty && !it.browsers.contains(bFilter) { return false }
    if kFilter == "bookmarks" && !it.hasBookmark { return false }
    if kFilter == "history" && !it.hasHistory { return false }
    if !folderTags.isEmpty {
        let foldersLow = it.folders.joined(separator: " ").lowercased()
        if !folderTags.allSatisfy({ foldersLow.contains($0) }) { return false }
    }
    if !textTokens.isEmpty {
        let hay = "\(it.title) \(it.url) \(it.folders.joined(separator: " ")) \(it.profiles.joined(separator: " "))".lowercased()
        if !textTokens.allSatisfy({ hay.contains($0) }) { return false }
    }
    return true
}

var rows: [ViewItem] = []
if safariDenied && (bFilter.isEmpty || bFilter == "safari") {
    rows.append(ViewItem(
        id: "safari-fda-guide",
        title: isEn
            ? "Grant Full Disk Access to Unlock Safari Bookmarks & History"
            : "授予「完全磁盘访问权限」以解锁 Safari 书签与历史记录",
        subtitle: isEn
            ? "macOS protects ~/Library/Safari via TCC. Edge & Chrome work without extra permissions."
            : "macOS 对 ~/Library/Safari 启用了隐私保护（Edge 与 Chrome 已正常直连，无需额外权限）",
        icon: "lock.shield.fill",
        badge: "SAFARI TCC",
        openURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    ))
}

for it in filtered.prefix(maxRows) {
    let bLabel = browserSpecs[it.primaryBrowser]?.label ?? it.primaryBrowser
    let domain = fallbackTitle(it.url)
    let profilesTxt = it.profiles.prefix(2).joined(separator: " / ")
    let folderTxt = it.folders.first.map { "📁 \($0)" } ?? ""
    let visitsTxt = (it.hasHistory && it.visitCount > 1)
        ? (isEn ? "\(it.visitCount) visits" : "访问 \(it.visitCount) 次")
        : ""
    let timeTxt = formatRelativeTime(it.timestamp, isEn: isEn)
    let subParts = [profilesTxt, folderTxt, domain, visitsTxt, timeTxt].filter { !$0.isEmpty }
    let kindTag = (it.hasBookmark && it.hasHistory) ? "BM+HIS" : (it.hasBookmark ? "BM" : "HIS")
    let icon = it.pinned ? "pin.fill" : (it.hasBookmark ? "bookmark.fill" : (browserSpecs[it.primaryBrowser]?.icon ?? "globe"))

    rows.append(ViewItem(
        id: "bh-\(it.id)",
        title: (it.pinned ? "⭐ " : "") + String(it.title.prefix(88)),
        subtitle: subParts.joined(separator: " · "),
        icon: icon,
        badge: "\(bLabel) · \(kindTag)",
        copyText: it.url,
        openURL: openInSource ? nil : it.url,
        commandArgs: openInSource ? ["--open-in", it.primaryBrowser, it.url] : nil,
        actions: [
            ViewAction(
                id: "open-src-\(it.id)",
                label: isEn ? "Open in \(bLabel)" : "用 \(bLabel) 打开",
                style: "primary",
                commandArgs: ["--open-in", it.primaryBrowser, it.url]
            ),
            ViewAction(
                id: "pin-\(it.id)",
                label: isEn ? (it.pinned ? "Unpin" : "Pin") : (it.pinned ? "取消置顶" : "星标置顶"),
                commandArgs: ["--toggle-pin", it.url]
            )
        ]
    ))
}

if rows.isEmpty {
    rows.append(ViewItem(
        id: "empty-browser-hits",
        title: isEn ? "No matching bookmarks or history found" : "未匹配到符合条件的书签或历史记录",
        subtitle: isEn
            ? "Tip: use @edge, @chrome, @safari, @bm, @his, or #FolderName to filter"
            : "提示：可使用 @edge / @chrome / @safari / @bm / @his 或 #收藏夹名 组合筛选",
        icon: "magnifyingglass",
        badge: "EMPTY",
        commandArgs: ["--sync"]
    ))
}

let bmTotal = items.filter(\.hasBookmark).count
let hisTotal = items.filter(\.hasHistory).count
var scopeBits: [String] = []
if !bFilter.isEmpty { scopeBits.append(browserSpecs[bFilter]?.label ?? bFilter) }
if !kFilter.isEmpty { scopeBits.append(kFilter.uppercased()) }
let scopePrefix = scopeBits.isEmpty ? "" : "[\(scopeBits.joined(separator: " · "))] "

let subtitle = isEn
    ? "\(scopePrefix)Matched \(filtered.count)/\(items.count) · \(cacheState) · Filter: @edge @chrome @safari @bm @his #folder"
    : "\(scopePrefix)命中 \(filtered.count) / \(items.count) 条（\(cacheState)）· 支持 @edge @chrome @safari @bm @his #目录"

let statusSummary = "书签 \(bmTotal) · 历史 \(hisTotal)" + (safariDenied ? " (Safari 待授磁盘权限)" : "")

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Browser Bookmarks & History Hub" : "三端浏览器书签与历史中枢",
    subtitle: subtitle,
    badge: bFilter.isEmpty ? "3 BROWSERS" : bFilter.uppercased(),
    metrics: [
        KeyValue(key: isEn ? "Bookmarks" : "书签总数", value: String(bmTotal)),
        KeyValue(key: isEn ? "History" : "近期历史", value: String(hisTotal)),
        KeyValue(key: "Edge / Chrome", value: "\(bCounts["edge"] ?? 0) / \(bCounts["chrome"] ?? 0)"),
        KeyValue(key: "Safari", value: safariDenied ? (isEn ? "Need FDA" : "待授磁盘权限") : String(bCounts["safari"] ?? 0))
    ],
    items: rows,
    effect: PostActionEffect(
        toast: toastMsg,
        reloadSearchIndex: true,
        statusSummary: statusSummary,
        statusBadge: String(items.count)
    )
))
