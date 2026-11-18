import Darwin
import Foundation
import PluginKit
import SQLite3

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
            kind: "bookmark", browser: "safari",
            profile: folderChain.contains("Reading List") ? "Reading List" : "Default",
            title: title, url: urlVal, folder: folderChain.joined(separator: " / "), visitCount: 1, timestamp: ts
        ))
        return
    }
    if let children = node["Children"] as? [[String: Any]] {
        let rawTitle = ((node["Title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let friendlyMap = ["BookmarksBar": "个人收藏", "BookmarksMenu": "书签菜单", "com.apple.ReadingList": "Reading List"]
        let friendly = friendlyMap[rawTitle] ?? rawTitle
        let nextChain = (!friendly.isEmpty && friendly != "Root") ? (folderChain + [friendly]) : folderChain
        for child in children { walkSafariPlistNode(child, folderChain: nextChain, out: &out) }
    }
}

func readSafariStore(safariDir: URL, cutoffUnix: Double, limit: Int = 400) -> (records: [RawRecord], denied: Bool) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: safariDir.path) else { return ([], false) }
    var records: [RawRecord] = [], permissionDenied = false

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
                    list.append(RawRecord(
                        kind: "history", browser: "safari", profile: "Default",
                        title: rawTitle.isEmpty ? fallbackTitle(urlVal) : rawTitle, url: urlVal, folder: "",
                        visitCount: max(1, Int(sqlite3_column_int(s, 2))), timestamp: coreDataToUnix(sqlite3_column_double(s, 3))
                    ))
                }
                return list
            }) { records.append(contentsOf: rows) }
        } catch SnapshotDBError.permissionDenied { permissionDenied = true } catch {}
    }

    if records.isEmpty && !fm.isReadableFile(atPath: safariDir.path) { permissionDenied = true }
    return (records, permissionDenied)
}

func normalizeURLKey(_ urlVal: String) -> String {
    (urlVal.filter { $0 == "/" }.count >= 3 && urlVal.hasSuffix("/")) ? String(urlVal.dropLast()) : urlVal
}

func aggregateRecords(_ rawRecords: [RawRecord], pinnedURLs: Set<String>) -> [AggregatedItem] {
    var merged: [String: AggregatedItem] = [:], orderKeys: [String] = []
    for rec in rawRecords {
        let urlVal = rec.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlVal.isEmpty else { continue }
        let normKey = normalizeURLKey(urlVal), isBM = (rec.kind == "bookmark")
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
                id: uid, url: urlVal, title: rec.title, hasBookmark: isBM, hasHistory: !isBM,
                browsers: [rec.browser], primaryBrowser: rec.browser, profiles: [profTag],
                folders: rec.folder.isEmpty ? [] : [rec.folder], visitCount: max(1, rec.visitCount),
                timestamp: rec.timestamp, pinned: pinnedURLs.contains(urlVal) || pinnedURLs.contains(normKey)
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
            return (it.hasBookmark ? 35.0 : 0.0) + recency + freq
        }
        return score(a) > score(b)
    }
    return items
}

func loadPinnedURLs(dataDir: URL?) -> Set<String> {
    guard let pinFile = dataDir?.appendingPathComponent("pinned-urls.json"),
          let data = try? Data(contentsOf: pinFile),
          let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return Set(arr.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
}

func togglePinnedURL(dataDir: URL?, targetURL: String) -> Bool {
    guard let dataDir, !targetURL.isEmpty else { return false }
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    var pins = loadPinnedURLs(dataDir: dataDir)
    let nowPinned = pins.contains(targetURL) ? { pins.remove(targetURL); return false }() : { pins.insert(targetURL); return true }()
    if let data = try? PluginOutput.encodeJSON(pins.sorted(), pretty: true) {
        try? data.write(to: dataDir.appendingPathComponent("pinned-urls.json"), options: .atomic)
    }
    return nowPinned
}

func exportLauncherSearchIndex(items: [AggregatedItem], dataDir: URL?, safariDenied: Bool) {
    guard let dataDir else { return }
    try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    var idxEntries: [SearchIndexItem] = []
    for item in items.prefix(420) where item.url.hasPrefix("http://") || item.url.hasPrefix("https://") {
        let domain = fallbackTitle(item.url)
        let bBadges = item.browsers.map { browserSpecs[$0]?.label ?? $0 }.joined(separator: "/")
        let subParts = [bBadges, item.folders.first ?? "", domain].filter { !$0.isEmpty }
        var tags = item.browsers + [item.hasBookmark ? "bookmark" : "history"]
        for f in item.folders {
            for seg in f.split(separator: "/") {
                let cleanSeg = seg.trimmingCharacters(in: .whitespaces)
                if !cleanSeg.isEmpty && !tags.contains(cleanSeg) { tags.append(cleanSeg) }
            }
        }
        let prio = item.pinned ? 85 : (item.hasBookmark ? 55 : min(45, 10 + item.visitCount * 2))
        let icon = item.pinned ? "pin.fill" : (item.hasBookmark ? "bookmark.fill" : (browserSpecs[item.primaryBrowser]?.icon ?? "globe"))
        idxEntries.append(SearchIndexItem(
            id: item.id, title: (item.pinned ? "⭐ " : "") + String(item.title.prefix(90)),
            subtitle: subParts.joined(separator: " · "), url: item.url, copyText: item.url,
            icon: icon, badge: String("\(bBadges) · \(item.hasBookmark ? "BM" : "HIS")".prefix(18)),
            tags: Array(tags.prefix(8)), pinned: item.pinned, priority: prio
        ))
    }
    PluginOutput.writeSearchIndex(idxEntries, to: dataDir.path)
    let summary = "书签 \(items.filter(\.hasBookmark).count) · 历史 \(items.filter(\.hasHistory).count)" + (safariDenied ? " (Safari 待授磁盘权限)" : "")
    PluginOutput.writeRuntimeStatus(summary: summary, badge: String(items.count), to: dataDir.path)
}

func collectOrLoadSnapshot(
    enabledBrowsers: [String], historyDays: Int, ttlSeconds: Int, dataDir: URL?, forceRefresh: Bool
) -> (items: [AggregatedItem], browserCounts: [String: Int], safariDenied: Bool, cacheState: String) {
    let cacheFile = dataDir?.appendingPathComponent("snapshot-cache.json")
    let pins = loadPinnedURLs(dataDir: dataDir)
    let cacheSig = "\(enabledBrowsers.joined(separator: ",")):\(historyDays)"
    let now = Date().timeIntervalSince1970

    if !forceRefresh, ttlSeconds > 0, let cacheFile,
       let data = try? Data(contentsOf: cacheFile),
       let cached = try? JSONDecoder().decode(SnapshotCacheFile.self, from: data),
       (now - cached.savedAt) <= Double(ttlSeconds), cached.sig == cacheSig {
        let updated = cached.items.map { it -> AggregatedItem in
            var copy = it; copy.pinned = pins.contains(it.url) || pins.contains(normalizeURLKey(it.url)); return copy
        }
        return (updated, cached.browserCounts, cached.safariDenied, "\(Int(now - cached.savedAt))s cache")
    }

    let roots = resolveBrowserRoots()
    let cutoffUnix = now - Double(max(1, historyDays)) * 86_400.0
    var rawRecords: [RawRecord] = [], browserCounts: [String: Int] = ["edge": 0, "chrome": 0, "safari": 0]
    var safariDenied = false, deniedBrowsers = Set<String>()

    for bKey in enabledBrowsers {
        if (bKey == "edge" || bKey == "chrome"), let root = roots[bKey] {
            var bRecs: [RawRecord] = []
            for (profDir, profLabel) in discoverChromiumProfiles(browserRoot: root) {
                bRecs.append(contentsOf: readChromiumBookmarks(fileURL: profDir.appendingPathComponent("Bookmarks"), browserKey: bKey, profileLabel: profLabel))
                bRecs.append(contentsOf: readChromiumHistory(historyDB: profDir.appendingPathComponent("History"), browserKey: bKey, profileLabel: profLabel, cutoffUnix: cutoffUnix, deniedSink: &deniedBrowsers))
            }
            browserCounts[bKey] = bRecs.count; rawRecords.append(contentsOf: bRecs)
        } else if bKey == "safari", let sRoot = roots["safari"] {
            let (sRecs, denied) = readSafariStore(safariDir: sRoot, cutoffUnix: cutoffUnix)
            safariDenied = denied; if denied { deniedBrowsers.insert("safari") }
            browserCounts["safari"] = sRecs.count; rawRecords.append(contentsOf: sRecs)
        }
    }

    let items = aggregateRecords(rawRecords, pinnedURLs: pins)
    exportLauncherSearchIndex(items: items, dataDir: dataDir, safariDenied: !deniedBrowsers.isEmpty)
    if let cacheFile {
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snap = SnapshotCacheFile(savedAt: now, sig: cacheSig, safariDenied: safariDenied, browserCounts: browserCounts, items: Array(items.prefix(1500)))
        if let encoded = try? PluginOutput.encodeJSON(snap) { try? encoded.write(to: cacheFile, options: .atomic) }
    }
    return (items, browserCounts, safariDenied, "live")
}

func formatRelativeTime(_ unixTS: Double, isEn: Bool) -> String {
    guard unixTS > 0 else { return "" }
    let delta = max(0.0, Date().timeIntervalSince1970 - unixTS)
    if delta < 60 { return isEn ? "just now" : "刚刚" }
    if delta < 3600 { return isEn ? "\(Int(delta / 60))m ago" : "\(Int(delta / 60)) 分钟前" }
    if delta < 86_400 { return isEn ? "\(Int(delta / 3600))h ago" : "\(Int(delta / 3600)) 小时前" }
    let d = Int(delta / 86_400)
    if d <= 30 { return isEn ? "\(d)d ago" : "\(d) 天前" }
    let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
    return df.string(from: Date(timeIntervalSince1970: unixTS))
}

func openURLInBrowser(browserKey: String, targetURL: String) -> Bool {
    guard targetURL.hasPrefix("http://") || targetURL.hasPrefix("https://") else { return false }
    var args: [String] = []
    if let spec = browserSpecs[browserKey] { args.append(contentsOf: ["-b", spec.bundleID]) }
    args.append(targetURL)
    if SubprocessRunner.run(executable: "/usr/bin/open", arguments: args, timeoutSeconds: 3.0).exitCode == 0 { return true }
    return SubprocessRunner.run(executable: "/usr/bin/open", arguments: [targetURL], timeoutSeconds: 3.0).exitCode == 0
}
