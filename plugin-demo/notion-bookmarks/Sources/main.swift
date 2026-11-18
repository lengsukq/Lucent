import Foundation
import PluginKit

private func cacheFileURL(databaseID: String, dataDir: String) -> URL {
    let env = ProcessInfo.processInfo.environment
    let cacheDir: URL
    if let custom = env["LUMAKEY_NOTION_CACHE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
        cacheDir = URL(fileURLWithPath: custom, isDirectory: true)
    } else if !dataDir.isEmpty {
        cacheDir = URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("cache", isDirectory: true)
    } else {
        cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Lumakey/notion-bookmarks", isDirectory: true)
    }
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    let filtered = databaseID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
    let safeDB = String(String.UnicodeScalarView(filtered))
    return cacheDir.appendingPathComponent("\(safeDB.isEmpty ? "default" : safeDB).json")
}

private func loadCache(databaseID: String, ttlSeconds: Int, dataDir: String) -> NotionCacheEnvelope? {
    guard ttlSeconds > 0 else { return nil }
    let url = cacheFileURL(databaseID: databaseID, dataDir: dataDir)
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(NotionCacheEnvelope.self, from: data) else {
        return nil
    }
    let age = Date().timeIntervalSince1970 - decoded.fetchedAt
    return age <= Double(ttlSeconds) ? decoded : nil
}

private func loadCacheRaw(databaseID: String, dataDir: String) -> NotionCacheEnvelope? {
    let url = cacheFileURL(databaseID: databaseID, dataDir: dataDir)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(NotionCacheEnvelope.self, from: data)
}

private func exportSearchIndex(_ items: [BookmarkItem], dataDir: String) {
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
            id: bm.id,
            title: bm.title.isEmpty ? "Untitled" : bm.title,
            subtitle: subtitle,
            url: (urlVal.hasPrefix("http://") || urlVal.hasPrefix("https://")) ? urlVal : nil,
            copyText: urlVal.isEmpty ? bm.title : urlVal,
            icon: bm.pinned ? "pin.fill" : "bookmark.fill",
            badge: String(badgeRaw.prefix(16)),
            tags: cleanTags,
            pinned: bm.pinned,
            priority: bm.priority,
            commandArgs: bm.id.isEmpty ? nil : ["--detail", bm.id]
        )
    }

    if let overridePath = env["LUMAKEY_PLUGIN_INDEX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
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

private func saveCache(
    databaseID: String,
    dbTitle: String,
    schemaMap: [String: (name: String, type: String)],
    items: [BookmarkItem],
    dataDir: String
) {
    let sorted = sortBookmarks(items)
    let url = cacheFileURL(databaseID: databaseID, dataDir: dataDir)
    var rawSchema: [String: [String]] = [:]
    for (k, v) in schemaMap { rawSchema[k] = [v.name, v.type] }
    let env = NotionCacheEnvelope(
        fetchedAt: Date().timeIntervalSince1970,
        dbTitle: dbTitle,
        schema: rawSchema,
        items: sorted
    )
    if let data = try? PluginOutput.encodeJSON(env) {
        try? data.write(to: url, options: .atomic)
    }
    exportSearchIndex(sorted, dataDir: dataDir)
    PluginOutput.writeRuntimeStatus(summary: "\(dbTitle) · \(sorted.count) 条书签", badge: "\(sorted.count)", to: dataDir)
}

private func schemaFromCache(_ raw: NotionCacheEnvelope?) -> [String: (name: String, type: String)] {
    guard let raw else { return [:] }
    var out: [String: (String, String)] = [:]
    for (k, v) in raw.schema where v.count == 2 {
        out[k] = (v[0], v[1])
    }
    return out
}

private func syncBookmarks(
    client: NotionClient,
    ttlSeconds: Int,
    dataDir: String,
    force: Bool = false
) throws -> (dbTitle: String, schemaMap: [String: (name: String, type: String)], items: [BookmarkItem], cacheLabel: String) {
    if !force, let cached = loadCache(databaseID: client.databaseID, ttlSeconds: ttlSeconds, dataDir: dataDir) {
        let age = max(0, Int(Date().timeIntervalSince1970 - cached.fetchedAt))
        let title = cached.dbTitle.isEmpty ? "Notion 书签库" : cached.dbTitle
        return (title, schemaFromCache(cached), cached.items, "缓存 (\(age)s 前)")
    }
    let (dbTitle, schemaMap) = try client.retrieveDatabaseInfo()
    let items = try client.queryAllBookmarks()
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)
    return (dbTitle, schemaMap, items, "刚刚实时同步")
}

private func formatBookmarkItem(_ bm: BookmarkItem, includeManage: Bool = true) -> ViewItem {
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
        icon: bm.pinned ? "pin.fill" : "bookmark.fill",
        badge: String(badgeRaw.prefix(16)),
        copyText: bm.url.isEmpty ? bm.title : bm.url,
        openURL: validURL,
        commandArgs: (includeManage && !bm.id.isEmpty) ? ["--detail", bm.id] : nil
    )
}

private func filterBookmarks(_ items: [BookmarkItem], query: String) -> [BookmarkItem] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return items }
    let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
    var results = items
    for tok in tokens {
        if tok.hasPrefix("#") && tok.count > 1 {
            let tagQ = String(tok.dropFirst()).lowercased()
            results = results.filter { bm in
                bm.tags.contains(where: { $0.lowercased().contains(tagQ) }) || bm.category.lowercased().contains(tagQ)
            }
        } else {
            let kw = tok.lowercased()
            results = results.filter { bm in
                bm.title.lowercased().contains(kw)
                    || bm.url.lowercased().contains(kw)
                    || bm.description.lowercased().contains(kw)
                    || bm.tags.contains(where: { $0.lowercased().contains(kw) })
            }
        }
    }
    return results
}

private func findBookmarkTarget(_ items: [BookmarkItem], needle: String) -> BookmarkItem? {
    let clean = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !clean.isEmpty else { return nil }
    let cleanNoDash = clean.replacingOccurrences(of: "-", with: "")
    for bm in items {
        if bm.id.lowercased() == clean || bm.id.replacingOccurrences(of: "-", with: "").lowercased() == cleanNoDash {
            return bm
        }
    }
    for bm in items where bm.title.lowercased() == clean {
        return bm
    }
    return filterBookmarks(items, query: needle).first
}

private func parseAddQuery(rest: String, clipboardURL: String, defaultTags: [String]) -> (url: String, title: String, tags: [String]) {
    let tokens = rest.split(whereSeparator: \.isWhitespace).map(String.init)
    var tags: [String] = []
    var nonTags: [String] = []
    for tok in tokens {
        if tok.hasPrefix("#") && tok.count > 1 {
            tags.append(String(tok.dropFirst()))
        } else {
            nonTags.append(tok)
        }
    }
    var urlVal = ""
    var titleParts: [String] = []
    for tok in nonTags {
        if urlVal.isEmpty && (!extractFirstURL(tok).isEmpty || (tok.contains(".") && !tok.hasPrefix("/"))) {
            urlVal = normalizeTargetURL(tok)
        } else {
            titleParts.append(tok)
        }
    }
    if urlVal.isEmpty && !clipboardURL.isEmpty { urlVal = clipboardURL }
    let finalTags = tags.isEmpty ? defaultTags : tags
    return (urlVal, titleParts.joined(separator: " ").trimmingCharacters(in: .whitespaces), finalTags)
}

private func splitShellTokens(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character? = nil
    var escaped = false
    for ch in text {
        if escaped {
            current.append(ch)
            escaped = false
            continue
        }
        if ch == "\\" {
            escaped = true
            continue
        }
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
        } else if ch == "\"" || ch == "'" {
            quote = ch
        } else if ch.isWhitespace {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

private func parseEditQuery(_ rest: String) -> (targetQuery: String, updates: [String: Any]) {
    let tokens = splitShellTokens(rest)
    var updates: [String: Any] = [:]
    var targetParts: [String] = []
    for tok in tokens {
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

private func extractInputJSON(_ argv: [String]) -> (cleaned: [String], form: [String: Any]) {
    var cleaned: [String] = []
    var form: [String: Any] = [:]
    var i = 0
    while i < argv.count {
        if argv[i] == "--input-json", i + 1 < argv.count {
            if let data = argv[i + 1].data(using: .utf8),
               let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                form = parsed
            }
            i += 2
            continue
        }
        cleaned.append(argv[i])
        i += 1
    }
    return (cleaned, form)
}

private func handleDetailView(
    client: NotionClient,
    pageID: String,
    ttlSeconds: Int,
    dataDir: String,
    notice: String = ""
) throws {
    var (dbTitle, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    var bm = findBookmarkTarget(items, needle: pageID)
    if bm == nil {
        (dbTitle, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: true)
        bm = findBookmarkTarget(items, needle: pageID)
    }
    guard let bm else {
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2,
            title: "未找到该书签",
            subtitle: "可能已被归档或移除",
            badge: "404",
            items: [ViewItem(title: "刷新并回到书签列表", icon: "arrow.clockwise", commandArgs: ["--refresh"])]
        ))
        return
    }

    let nextPrio = bm.priority + 10
    var detailItems: [ViewItem] = []
    if !bm.url.isEmpty {
        detailItems.append(ViewItem(
            title: "在浏览器打开",
            subtitle: bm.url,
            icon: "safari",
            badge: "OPEN",
            copyText: bm.url,
            openURL: bm.url
        ))
    }
    detailItems.append(contentsOf: [
        ViewItem(
            title: bm.pinned ? "取消置顶" : "设为置顶",
            subtitle: "更新 Notion pinned / 置顶字段",
            icon: bm.pinned ? "pin.slash" : "pin.fill",
            badge: "PIN",
            commandArgs: ["--set-pin", bm.id, bm.pinned ? "false" : "true"]
        ),
        ViewItem(
            title: "提高优先级 (\(bm.priority) → \(nextPrio))",
            subtitle: "调整 priority 排序权重",
            icon: "arrow.up.circle",
            badge: "PRIO",
            commandArgs: ["--set-priority", bm.id, String(nextPrio)]
        ),
        ViewItem(
            id: "edit-form-\(bm.id)",
            title: "表单修改标题、标签或说明",
            subtitle: "通过原生表单直接提交到 Notion 数据库",
            icon: "pencil.line",
            actions: [
                ViewAction(
                    id: "edit-form",
                    label: "编辑字段",
                    style: "primary",
                    commandArgs: ["--edit-form", bm.id],
                    promptFields: [
                        PromptField(key: "title", label: "标题", type: "text", defaultValue: bm.title, required: true),
                        PromptField(key: "tags", label: "标签（逗号分隔）", type: "text", defaultValue: bm.tags.joined(separator: ", ")),
                        PromptField(key: "description", label: "说明描述", type: "text", defaultValue: bm.description)
                    ]
                )
            ]
        )
    ])
    if !bm.notionUrl.isEmpty {
        detailItems.append(ViewItem(
            title: "在 Notion 中编辑字段",
            subtitle: "直达 Notion 原页面修改标题、标签与说明",
            icon: "square.and.pencil",
            openURL: bm.notionUrl
        ))
    }
    detailItems.append(ViewItem(
        id: "archive-\(bm.id)",
        title: "归档删除此书签",
        subtitle: "在 Notion 中设为 archived=true（可在废纸篓恢复）",
        icon: "trash",
        badge: "DEL",
        actions: [
            ViewAction(
                id: "confirm-archive",
                label: "归档删除",
                style: "destructive",
                commandArgs: ["--archive", bm.id],
                confirmMessage: "确认将「\(bm.title.isEmpty ? bm.id : bm.title)」移入 Notion 废纸篓？"
            )
        ]
    ))
    detailItems.append(ViewItem(title: "返回书签列表", icon: "arrow.uturn.backward", commandArgs: ["--list"]))

    let tagsStr = bm.tags.isEmpty ? "无标签" : bm.tags.joined(separator: ", ")
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: bm.title,
        subtitle: notice.isEmpty ? "\(dbTitle) · \(bm.url)" : notice,
        badge: bm.pinned ? "PINNED" : "BOOKMARK",
        markdown: bm.description.isEmpty ? nil : bm.description,
        metrics: [
            KeyValue(key: "置顶状态", value: bm.pinned ? "已置顶" : "普通"),
            KeyValue(key: "优先级", value: String(bm.priority)),
            KeyValue(key: "标签", value: String(tagsStr.prefix(24)))
        ],
        items: detailItems,
        effect: notice.isEmpty ? nil : PostActionEffect(toast: notice, reloadSearchIndex: true)
    ))
}

private func handleAddBookmark(
    client: NotionClient,
    urlVal: String,
    explicitTitle: String,
    tags: [String],
    autoFetch: Bool,
    ttlSeconds: Int,
    dataDir: String
) throws {
    guard !urlVal.isEmpty else {
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2,
            title: "未检测到可收藏链接",
            subtitle: "请在命令中附带网址，或先复制网页链接到剪贴板",
            badge: "ADD",
            items: [
                ViewItem(
                    title: "用法：bm add https://example.com [自定义标题] [#标签]",
                    subtitle: "也可先复制链接，再输入 bm 点击「一键收藏剪贴板链接」",
                    icon: "link.badge.plus",
                    copyText: "bm add https://example.com #常用"
                ),
                ViewItem(title: "返回书签列表", icon: "arrow.uturn.backward", commandArgs: ["--list"])
            ]
        ))
        return
    }

    var (dbTitle, schemaMap, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    let meta = autoFetch ? fetchURLMetadata(urlVal) : (title: "", description: "")
    let fallbackHost = URL(string: urlVal)?.host ?? urlVal
    let title = !explicitTitle.isEmpty ? explicitTitle : (!meta.title.isEmpty ? meta.title : fallbackHost)

    let created = try client.createBookmark(
        payload: [
            "title": title,
            "url": urlVal,
            "description": meta.description,
            "tags": tags,
            "pinned": false,
            "priority": 0
        ],
        schemaMap: schemaMap
    )
    items.removeAll { $0.id == created.id }
    items.insert(created, at: 0)
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)

    var viewItems: [ViewItem] = [
        ViewItem(
            title: created.title,
            subtitle: created.url,
            icon: "checkmark.circle.fill",
            badge: "已入库",
            copyText: created.url,
            openURL: created.url,
            commandArgs: ["--detail", created.id]
        ),
        ViewItem(
            title: "置顶此书签",
            subtitle: "同步写入 Notion 置顶状态（Nav-Notion-Lime Dock 可见）",
            icon: "pin.fill",
            commandArgs: ["--set-pin", created.id, "true"]
        ),
        ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])
    ]
    if !created.notionUrl.isEmpty {
        viewItems.append(ViewItem(
            title: "在 Notion 中查看页面",
            subtitle: created.notionUrl,
            icon: "doc.text",
            openURL: created.notionUrl
        ))
    }

    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "已收藏到 Notion 书签库",
        subtitle: "\(dbTitle) · 标签：\(tags.isEmpty ? "无" : tags.joined(separator: ", "))",
        badge: "SAVED",
        metrics: [
            KeyValue(key: "标题", value: String(created.title.prefix(28))),
            KeyValue(key: "总书签数", value: String(items.count))
        ],
        items: viewItems,
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

private func handleUpdateFields(
    client: NotionClient,
    pageID: String,
    updates: [String: Any],
    ttlSeconds: Int,
    dataDir: String,
    showDetail: Bool = true
) throws {
    var (dbTitle, schemaMap, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    if schemaMap.isEmpty {
        let info = try client.retrieveDatabaseInfo()
        dbTitle = info.title
        schemaMap = info.schema
    }
    let updated = try client.updateBookmark(pageID: pageID, payload: updates, schemaMap: schemaMap)
    var found = false
    for i in items.indices where items[i].id == pageID {
        items[i] = updated
        found = true
    }
    if !found { items.append(updated) }
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)

    if showDetail {
        try handleDetailView(client: client, pageID: pageID, ttlSeconds: ttlSeconds, dataDir: dataDir, notice: "✅ 已同步更新到 Notion")
        return
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "书签已更新",
        subtitle: updated.title,
        badge: "UPDATED",
        items: [
            formatBookmarkItem(updated),
            ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])
        ],
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

private func handleArchiveBookmark(client: NotionClient, pageID: String, ttlSeconds: Int, dataDir: String) throws {
    let (dbTitle, schemaMap, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    let target = findBookmarkTarget(items, needle: pageID)
    try client.archiveBookmark(pageID: pageID)
    let remaining = items.filter { $0.id != pageID }
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: remaining, dataDir: dataDir)
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "已归档书签",
        subtitle: "已将「\(target?.title ?? pageID)」移入 Notion 废纸篓",
        badge: "ARCHIVED",
        metrics: [KeyValue(key: "剩余书签", value: String(remaining.count))],
        items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])],
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

private func handleListView(
    client: NotionClient,
    query: String,
    clipboardURL: String,
    maxItems: Int,
    ttlSeconds: Int,
    dataDir: String,
    forceRefresh: Bool = false
) throws {
    let (dbTitle, _, items, syncStatus) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: forceRefresh)
    let filtered = filterBookmarks(items, query: query)
    let pinnedCount = items.filter(\.pinned).count
    let qTrim = query.trimmingCharacters(in: .whitespacesAndNewlines)

    var viewItems: [ViewItem] = []
    if qTrim.isEmpty {
        viewItems.append(ViewItem(
            id: "add-bookmark-form",
            title: "➕ 新增书签到 Notion",
            subtitle: "弹窗填写网址、标题与标签（支持自动抓取网页元数据）",
            icon: "plus.app.fill",
            badge: "NEW",
            actions: [
                ViewAction(
                    id: "add-form",
                    label: "填写表单",
                    style: "primary",
                    commandArgs: ["--add-form"],
                    promptFields: [
                        PromptField(key: "url", label: "网页链接 URL", type: "text", defaultValue: clipboardURL, placeholder: "https://...", required: true),
                        PromptField(key: "title", label: "标题（留空则自动抓取）", type: "text", placeholder: "可选"),
                        PromptField(key: "tags", label: "标签（逗号分隔）", type: "text", defaultValue: "书签")
                    ]
                )
            ]
        ))
        if !clipboardURL.isEmpty {
            viewItems.append(ViewItem(
                title: "⭐ 一键收藏剪贴板链接",
                subtitle: clipboardURL,
                icon: "plus.circle.fill",
                badge: "CLIPBOARD",
                copyText: clipboardURL,
                commandArgs: ["--add-clipboard"]
            ))
        }
    }

    for bm in filtered.prefix(maxItems) {
        viewItems.append(formatBookmarkItem(bm))
    }

    if filtered.isEmpty {
        viewItems.append(ViewItem(
            title: qTrim.isEmpty ? "书签库暂无数据" : "未匹配到相关书签",
            subtitle: "可输入 bm add <网址> 新增，或点击下方强制刷新 Notion 缓存",
            icon: "tray"
        ))
    }

    viewItems.append(ViewItem(
        title: "强制刷新 Notion 书签缓存",
        subtitle: "当前数据源状态：\(syncStatus)",
        icon: "arrow.clockwise",
        badge: "SYNC",
        commandArgs: ["--refresh"]
    ))

    let subtitle = qTrim.isEmpty
        ? "\(dbTitle) · \(syncStatus)"
        : "筛选「\(qTrim)」命中 \(filtered.count) / \(items.count) 条 · \(syncStatus)"

    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "Notion 书签收藏",
        subtitle: subtitle,
        badge: "BOOKMARKS",
        metrics: [
            KeyValue(key: "总书签", value: String(items.count)),
            KeyValue(key: "已置顶", value: String(pinnedCount)),
            KeyValue(key: "当前展示", value: "\(min(filtered.count, maxItems))/\(filtered.count)")
        ],
        items: viewItems,
        effect: PostActionEffect(
            reloadSearchIndex: forceRefresh,
            statusSummary: "\(dbTitle) · \(items.count) 条书签",
            statusBadge: String(items.count)
        )
    ))
}

let input = PluginInput.read()
let dataDir = input.dataDir
let (argv, formData) = extractInputJSON(input.arguments)
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)

let ctxURL = extractFirstURL(input.context?.url ?? input.context?.text ?? "")
let clipURL = extractFirstURL(input.clipboard)
let clipboardURL = !clipURL.isEmpty ? clipURL : ctxURL

let env = ProcessInfo.processInfo.environment
let token = input.cfgString("notionToken", default: env["NOTION_TOKEN"] ?? "")
let rawDBID = input.cfgString("databaseId", default: env["NOTION_DATABASE_ID"] ?? "")
let databaseID = normalizeDatabaseID(rawDBID)

if token.isEmpty || databaseID.isEmpty {
    var missing: [String] = []
    if token.isEmpty { missing.append("Notion Secret Token (`notionToken`)") }
    if databaseID.isEmpty { missing.append("Notion Database ID (`databaseId`)") }
    let notionPortal = "https" + "://www.notion.so/my-integrations"
    var items: [ViewItem] = [
        ViewItem(
            title: "打开 Lumakey 插件设置填写凭证",
            subtitle: "填入 Token 与 Database ID 后点击「保存配置」即可使用",
            icon: "gearshape.fill",
            badge: "SETUP",
            openURL: "lumakey://settings/plugin/notion-bookmarks"
        ),
        ViewItem(
            title: "获取 Notion Integration Token",
            subtitle: notionPortal,
            icon: "key.fill",
            copyText: notionPortal,
            openURL: notionPortal
        )
    ]
    if !clipboardURL.isEmpty {
        items.append(ViewItem(
            title: "已检测到剪贴板链接（配置完成后可一键收藏）",
            subtitle: clipboardURL,
            icon: "link",
            copyText: clipboardURL
        ))
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "Notion 书签插件尚未配置",
        subtitle: "缺少：\(missing.joined(separator: "、"))",
        badge: "SETUP",
        markdown: "兼容 `nav-notion-lime` 数据库字段（`name`、`url`、`description`、`tag`、`priority`、`pinned`），记得在 Notion 数据库右上角 `... -> Connect to` 授权你的 Integration。",
        items: items
    ))
    exit(0)
}

let defaultTags = {
    let parsed = parseTagsCSV(input.cfgString("defaultTags", default: "书签"))
    return parsed.isEmpty ? ["书签"] : parsed
}()
let autoFetch = input.cfgBool("autoFetchMeta", default: true)
let ttlSeconds = input.cfgInt("cacheTtlSeconds", default: 120, min: 0, max: 86_400)
let maxItems = input.cfgInt("maxItems", default: 15, min: 1, max: 30)
let client = NotionClient(token: token, databaseID: databaseID)

do {
    if let cmd = argv.first {
        switch cmd {
        case "--refresh":
            try handleListView(client: client, query: "", clipboardURL: clipboardURL, maxItems: maxItems, ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: true)
            exit(0)
        case "--list":
            try handleListView(client: client, query: "", clipboardURL: clipboardURL, maxItems: maxItems, ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: false)
            exit(0)
        case "--add-clipboard":
            try handleAddBookmark(client: client, urlVal: clipboardURL, explicitTitle: "", tags: defaultTags, autoFetch: autoFetch, ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        case "--add-form":
            let formURL = normalizeTargetURL((formData["url"] as? String) ?? "")
            let formTitle = ((formData["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedTags = parseTagsCSV((formData["tags"] as? String) ?? "")
            try handleAddBookmark(client: client, urlVal: formURL, explicitTitle: formTitle, tags: parsedTags.isEmpty ? defaultTags : parsedTags, autoFetch: autoFetch, ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        case "--edit-form" where argv.count >= 2:
            var updates: [String: Any] = [:]
            if let tVal = (formData["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !tVal.isEmpty {
                updates["title"] = tVal
            }
            if let dVal = formData["description"] as? String {
                updates["description"] = dVal.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let tagsVal = formData["tags"] as? String {
                updates["tags"] = parseTagsCSV(tagsVal)
            }
            try handleUpdateFields(client: client, pageID: argv[1], updates: updates, ttlSeconds: ttlSeconds, dataDir: dataDir, showDetail: true)
            exit(0)
        case "--detail" where argv.count >= 2:
            try handleDetailView(client: client, pageID: argv[1], ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        case "--set-pin" where argv.count >= 3:
            try handleUpdateFields(client: client, pageID: argv[1], updates: ["pinned": isTruthy(argv[2])], ttlSeconds: ttlSeconds, dataDir: dataDir, showDetail: true)
            exit(0)
        case "--set-priority" where argv.count >= 3:
            try handleUpdateFields(client: client, pageID: argv[1], updates: ["priority": Int(argv[2]) ?? 0], ttlSeconds: ttlSeconds, dataDir: dataDir, showDetail: true)
            exit(0)
        case "--archive" where argv.count >= 2:
            try handleArchiveBookmark(client: client, pageID: argv[1], ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        default:
            break
        }
    }

    let lower = query.lowercased()
    if ["refresh", "sync", "刷新"].contains(lower) {
        try handleListView(client: client, query: "", clipboardURL: clipboardURL, maxItems: maxItems, ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: true)
        exit(0)
    }

    for prefix in ["add ", "+ ", "save ", "收藏 "] {
        let bare = prefix.trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix(prefix) || lower == bare {
            let rest = String(query.dropFirst(bare.count)).trimmingCharacters(in: .whitespaces)
            let (urlVal, explicitTitle, tags) = parseAddQuery(rest: rest, clipboardURL: clipboardURL, defaultTags: defaultTags)
            try handleAddBookmark(client: client, urlVal: urlVal, explicitTitle: explicitTitle, tags: tags, autoFetch: autoFetch, ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        }
    }

    if lower.hasPrefix("edit ") || lower.hasPrefix("修改 ") {
        let rest = query.split(maxSplits: 1, whereSeparator: \.isWhitespace).count > 1
            ? String(query.split(maxSplits: 1, whereSeparator: \.isWhitespace)[1])
            : ""
        let (targetQ, updates) = parseEditQuery(rest)
        let (_, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
        guard let target = findBookmarkTarget(items, needle: targetQ), !updates.isEmpty else {
            PluginOutput.emit(ViewPayload(
                schemaVersion: 2,
                title: "编辑指令参数不足或未命中书签",
                subtitle: "用法：bm edit <书签标题或ID> title=... desc=... tags=a,b pin=true priority=10",
                badge: "EDIT",
                items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])]
            ))
            exit(0)
        }
        try handleUpdateFields(client: client, pageID: target.id, updates: updates, ttlSeconds: ttlSeconds, dataDir: dataDir, showDetail: false)
        exit(0)
    }

    for (prefix, pinVal) in [("pin ", true), ("置顶 ", true), ("unpin ", false), ("取消置顶 ", false)] {
        if lower.hasPrefix(prefix) {
            let needle = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let (_, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
            guard let target = findBookmarkTarget(items, needle: needle) else {
                PluginOutput.emit(ViewPayload(
                    schemaVersion: 2,
                    title: "未找到匹配「\(needle)」的书签",
                    badge: "404",
                    items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])]
                ))
                exit(0)
            }
            try handleUpdateFields(client: client, pageID: target.id, updates: ["pinned": pinVal], ttlSeconds: ttlSeconds, dataDir: dataDir, showDetail: false)
            exit(0)
        }
    }

    for prefix in ["del ", "rm ", "delete ", "删除 "] {
        if lower.hasPrefix(prefix) {
            let needle = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            let (_, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
            guard let target = findBookmarkTarget(items, needle: needle) else {
                PluginOutput.emit(ViewPayload(
                    schemaVersion: 2,
                    title: "未找到匹配「\(needle)」的书签",
                    badge: "404",
                    items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])]
                ))
                exit(0)
            }
            try handleArchiveBookmark(client: client, pageID: target.id, ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        }
    }

    try handleListView(client: client, query: query, clipboardURL: clipboardURL, maxItems: maxItems, ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: false)
} catch let err as NotionAPIError {
    var hint = "请检查 Notion Token 与 Database ID 是否正确，并确认数据库已 Connect 到你的 Integration。"
    if err.status == 401 {
        hint = "Notion Token 无效或已过期，请在插件中心更新。"
    } else if err.status == 404 {
        hint = "未找到对应数据库，请确认 Database ID 且已在 Notion 页面右上角 ... -> Connect to 授权。"
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "Notion API 请求失败 (\(err.status))",
        subtitle: String(err.message.prefix(120)),
        badge: "ERROR",
        items: [
            ViewItem(
                title: "打开 Lumakey 插件设置检查凭证",
                subtitle: hint,
                icon: "gearshape.fill",
                openURL: "lumakey://settings/plugin/notion-bookmarks"
            ),
            ViewItem(title: "重试刷新", icon: "arrow.clockwise", commandArgs: ["--refresh"])
        ]
    ))
} catch {
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: "插件执行异常",
        subtitle: String(error.localizedDescription.prefix(140)),
        badge: "ERROR",
        items: [ViewItem(title: "返回书签列表", icon: "arrow.uturn.backward", commandArgs: ["--list"])]
    ))
}
