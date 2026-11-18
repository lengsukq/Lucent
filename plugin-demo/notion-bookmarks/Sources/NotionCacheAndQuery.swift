import Foundation
import PluginKit

func cacheFileURL(databaseID: String, dataDir: String) -> URL {
    let env = ProcessInfo.processInfo.environment
    let cacheDir: URL
    if let custom = env["LUCENT_NOTION_CACHE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
        cacheDir = URL(fileURLWithPath: custom, isDirectory: true)
    } else if !dataDir.isEmpty {
        cacheDir = URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("cache", isDirectory: true)
    } else {
        cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Lucent/notion-bookmarks", isDirectory: true)
    }
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let filtered = databaseID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
    let safeDB = String(String.UnicodeScalarView(filtered))
    return cacheDir.appendingPathComponent("\(safeDB.isEmpty ? "default" : safeDB).json")
}

func loadCache(databaseID: String, ttlSeconds: Int, dataDir: String) -> NotionCacheEnvelope? {
    guard ttlSeconds > 0 else { return nil }
    let url = cacheFileURL(databaseID: databaseID, dataDir: dataDir)
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(NotionCacheEnvelope.self, from: data) else {
        return nil
    }
    return (Date().timeIntervalSince1970 - decoded.fetchedAt) <= Double(ttlSeconds) ? decoded : nil
}

func exportSearchIndex(_ items: [BookmarkItem], dataDir: String) {
    let env = ProcessInfo.processInfo.environment
    let entries: [SearchIndexItem] = items.prefix(400).map { bm in
        let urlVal = bm.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTags = bm.tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let host = (URL(string: urlVal)?.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let tagStr = cleanTags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        let descShort = String(bm.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let subtitle = [host, tagStr, descShort].filter { !$0.isEmpty }.joined(separator: " · ")
        let badgeRaw = cleanTags.first ?? (bm.pinned ? "置顶" : "书签")
        return SearchIndexItem(
            id: bm.id, title: bm.title.isEmpty ? "Untitled" : bm.title, subtitle: subtitle,
            url: (urlVal.hasPrefix("http://") || urlVal.hasPrefix("https://")) ? urlVal : nil,
            copyText: urlVal.isEmpty ? bm.title : urlVal,
            icon: bm.pinned ? "pin.fill" : "bookmark.fill", badge: String(badgeRaw.prefix(16)),
            tags: cleanTags, pinned: bm.pinned, priority: bm.priority,
            commandArgs: bm.id.isEmpty ? nil : ["--detail", bm.id]
        )
    }

    if let overridePath = env["LUCENT_PLUGIN_INDEX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !overridePath.isEmpty {
        let outURL = URL(fileURLWithPath: overridePath)
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PluginOutput.encodeJSON(SearchIndexEnvelope(items: entries)) {
            try? data.write(to: outURL, options: .atomic)
        }
        return
    }
    PluginOutput.writeSearchIndex(entries, to: dataDir)
}

func saveCache(
    databaseID: String, dbTitle: String,
    schemaMap: [String: (name: String, type: String)],
    items: [BookmarkItem], dataDir: String
) {
    let sorted = sortBookmarks(items)
    let url = cacheFileURL(databaseID: databaseID, dataDir: dataDir)
    var rawSchema: [String: [String]] = [:]
    for (k, v) in schemaMap { rawSchema[k] = [v.name, v.type] }
    let env = NotionCacheEnvelope(fetchedAt: Date().timeIntervalSince1970, dbTitle: dbTitle, schema: rawSchema, items: sorted)
    if let data = try? PluginOutput.encodeJSON(env) { try? data.write(to: url, options: .atomic) }
    exportSearchIndex(sorted, dataDir: dataDir)
    PluginOutput.writeRuntimeStatus(summary: "\(dbTitle) · \(sorted.count) 条书签", badge: "\(sorted.count)", to: dataDir)
}

private func schemaFromCache(_ raw: NotionCacheEnvelope?) -> [String: (name: String, type: String)] {
    guard let raw else { return [:] }
    var out: [String: (String, String)] = [:]
    for (k, v) in raw.schema where v.count == 2 { out[k] = (v[0], v[1]) }
    return out
}

func syncBookmarks(
    client: NotionClient, ttlSeconds: Int, dataDir: String, force: Bool = false
) throws -> (dbTitle: String, schemaMap: [String: (name: String, type: String)], items: [BookmarkItem], cacheLabel: String) {
    if !force, let cached = loadCache(databaseID: client.databaseID, ttlSeconds: ttlSeconds, dataDir: dataDir) {
        let age = max(0, Int(Date().timeIntervalSince1970 - cached.fetchedAt))
        return (cached.dbTitle.isEmpty ? "Notion 书签库" : cached.dbTitle, schemaFromCache(cached), cached.items, "缓存 (\(age)s 前)")
    }
    let (dbTitle, schemaMap) = try client.retrieveDatabaseInfo()
    let items = try client.queryAllBookmarks()
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)
    return (dbTitle, schemaMap, items, "刚刚实时同步")
}

func formatBookmarkItem(_ bm: BookmarkItem, includeManage: Bool = true) -> ViewItem {
    let tagText = bm.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
    let domain = (URL(string: bm.url)?.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    let desc = String(bm.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    let subParts = [domain, tagText, desc].filter { !$0.isEmpty }
    let badgeRaw = bm.tags.first ?? (bm.pinned ? "置顶" : "LINK")
    let validURL = (bm.url.hasPrefix("http://") || bm.url.hasPrefix("https://")) ? bm.url : nil
    return ViewItem(
        id: bm.id.isEmpty ? nil : bm.id,
        title: (bm.pinned ? "📌 " : "") + String((bm.title.isEmpty ? "Untitled" : bm.title).prefix(80)),
        subtitle: subParts.isEmpty ? bm.url : subParts.joined(separator: " · "),
        icon: bm.pinned ? "pin.fill" : "bookmark.fill", badge: String(badgeRaw.prefix(16)),
        copyText: bm.url.isEmpty ? bm.title : bm.url, openURL: validURL,
        commandArgs: (includeManage && !bm.id.isEmpty) ? ["--detail", bm.id] : nil
    )
}

func filterBookmarks(_ items: [BookmarkItem], query: String) -> [BookmarkItem] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return items }
    var results = items
    for tok in q.split(whereSeparator: \.isWhitespace).map(String.init) {
        if tok.hasPrefix("#") && tok.count > 1 {
            let tagQ = String(tok.dropFirst()).lowercased()
            results = results.filter { bm in
                bm.tags.contains(where: { $0.lowercased().contains(tagQ) }) || bm.category.lowercased().contains(tagQ)
            }
        } else {
            let kw = tok.lowercased()
            results = results.filter { bm in
                bm.title.lowercased().contains(kw) || bm.url.lowercased().contains(kw)
                    || bm.description.lowercased().contains(kw) || bm.tags.contains(where: { $0.lowercased().contains(kw) })
            }
        }
    }
    return results
}

func findBookmarkTarget(_ items: [BookmarkItem], needle: String) -> BookmarkItem? {
    let clean = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !clean.isEmpty else { return nil }
    let cleanNoDash = clean.replacingOccurrences(of: "-", with: "")
    for bm in items {
        if bm.id.lowercased() == clean || bm.id.replacingOccurrences(of: "-", with: "").lowercased() == cleanNoDash { return bm }
    }
    for bm in items where bm.title.lowercased() == clean { return bm }
    return filterBookmarks(items, query: needle).first
}

func parseAddQuery(rest: String, clipboardURL: String, defaultTags: [String]) -> (url: String, title: String, tags: [String]) {
    var tags: [String] = [], nonTags: [String] = []
    for tok in rest.split(whereSeparator: \.isWhitespace).map(String.init) {
        if tok.hasPrefix("#") && tok.count > 1 { tags.append(String(tok.dropFirst())) } else { nonTags.append(tok) }
    }
    var urlVal = "", titleParts: [String] = []
    for tok in nonTags {
        if urlVal.isEmpty && (!extractFirstURL(tok).isEmpty || (tok.contains(".") && !tok.hasPrefix("/"))) {
            urlVal = normalizeTargetURL(tok)
        } else {
            titleParts.append(tok)
        }
    }
    if urlVal.isEmpty && !clipboardURL.isEmpty { urlVal = clipboardURL }
    return (urlVal, titleParts.joined(separator: " ").trimmingCharacters(in: .whitespaces), tags.isEmpty ? defaultTags : tags)
}

func splitShellTokens(_ text: String) -> [String] {
    var tokens: [String] = [], current = "", quote: Character? = nil, escaped = false
    for ch in text {
        if escaped { current.append(ch); escaped = false; continue }
        if ch == "\\" { escaped = true; continue }
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
        } else if ch == "\"" || ch == "'" {
            quote = ch
        } else if ch.isWhitespace {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

func parseEditQuery(_ rest: String) -> (targetQuery: String, updates: [String: Any]) {
    var updates: [String: Any] = [:], targetParts: [String] = []
    for tok in splitShellTokens(rest) {
        if let eqIdx = tok.firstIndex(of: "="), eqIdx != tok.startIndex {
            let k = tok[..<eqIdx].trimmingCharacters(in: .whitespaces).lowercased()
            let v = String(tok[tok.index(after: eqIdx)...])
            if ["title", "name", "标题", "名称"].contains(k) { updates["title"] = v }
            else if ["url", "link", "链接"].contains(k) { updates["url"] = normalizeTargetURL(v) }
            else if ["desc", "description", "描述", "说明"].contains(k) { updates["description"] = v }
            else if ["tags", "tag", "标签"].contains(k) { updates["tags"] = parseTagsCSV(v) }
            else if ["pin", "pinned", "置顶"].contains(k) { updates["pinned"] = isTruthy(v) }
            else if ["priority", "prio", "优先级"].contains(k) { updates["priority"] = Int(v) ?? 0 }
            else { targetParts.append(tok) }
        } else {
            targetParts.append(tok)
        }
    }
    return (targetParts.joined(separator: " "), updates)
}

func extractInputJSON(_ argv: [String]) -> (cleaned: [String], form: [String: Any]) {
    var cleaned: [String] = [], form: [String: Any] = [:], i = 0
    while i < argv.count {
        if argv[i] == "--input-json", i + 1 < argv.count {
            if let data = argv[i + 1].data(using: .utf8),
               let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                form = parsed
            }
            i += 2; continue
        }
        cleaned.append(argv[i]); i += 1
    }
    return (cleaned, form)
}
