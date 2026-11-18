import Foundation
import PluginKit

func handleDetailView(
    client: NotionClient, pageID: String, ttlSeconds: Int, dataDir: String, notice: String = ""
) throws {
    var (dbTitle, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    var bm = findBookmarkTarget(items, needle: pageID)
    if bm == nil {
        (dbTitle, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: true)
        bm = findBookmarkTarget(items, needle: pageID)
    }
    guard let bm else {
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2, title: "未找到该书签", subtitle: "可能已被归档或移除", badge: "404",
            items: [ViewItem(title: "刷新并回到书签列表", icon: "arrow.clockwise", commandArgs: ["--refresh"])]
        ))
        return
    }

    let nextPrio = bm.priority + 10
    var detailItems: [ViewItem] = []
    if !bm.url.isEmpty {
        detailItems.append(ViewItem(title: "在浏览器打开", subtitle: bm.url, icon: "safari", badge: "OPEN", copyText: bm.url, openURL: bm.url))
    }
    detailItems.append(contentsOf: [
        ViewItem(title: bm.pinned ? "取消置顶" : "设为置顶", subtitle: "更新 Notion pinned / 置顶字段", icon: bm.pinned ? "pin.slash" : "pin.fill", badge: "PIN", commandArgs: ["--set-pin", bm.id, bm.pinned ? "false" : "true"]),
        ViewItem(title: "提高优先级 (\(bm.priority) → \(nextPrio))", subtitle: "调整 priority 排序权重", icon: "arrow.up.circle", badge: "PRIO", commandArgs: ["--set-priority", bm.id, String(nextPrio)]),
        ViewItem(
            id: "edit-form-\(bm.id)", title: "表单修改标题、标签或说明", subtitle: "通过原生表单直接提交到 Notion 数据库", icon: "pencil.line",
            actions: [
                ViewAction(
                    id: "edit-form", label: "编辑字段", style: "primary", commandArgs: ["--edit-form", bm.id],
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
        detailItems.append(ViewItem(title: "在 Notion 中编辑字段", subtitle: "直达 Notion 原页面修改标题、标签与说明", icon: "square.and.pencil", openURL: bm.notionUrl))
    }
    detailItems.append(ViewItem(
        id: "archive-\(bm.id)", title: "归档删除此书签", subtitle: "在 Notion 中设为 archived=true（可在废纸篓恢复）", icon: "trash", badge: "DEL",
        actions: [
            ViewAction(
                id: "confirm-archive", label: "归档删除", style: "destructive", commandArgs: ["--archive", bm.id],
                confirmMessage: "确认将「\(bm.title.isEmpty ? bm.id : bm.title)」移入 Notion 废纸篓？"
            )
        ]
    ))
    detailItems.append(ViewItem(title: "返回书签列表", icon: "arrow.uturn.backward", commandArgs: ["--list"]))

    let tagsStr = bm.tags.isEmpty ? "无标签" : bm.tags.joined(separator: ", ")
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: bm.title, subtitle: notice.isEmpty ? "\(dbTitle) · \(bm.url)" : notice,
        badge: bm.pinned ? "PINNED" : "BOOKMARK", markdown: bm.description.isEmpty ? nil : bm.description,
        metrics: [
            KeyValue(key: "置顶状态", value: bm.pinned ? "已置顶" : "普通"),
            KeyValue(key: "优先级", value: String(bm.priority)),
            KeyValue(key: "标签", value: String(tagsStr.prefix(24)))
        ],
        items: detailItems,
        effect: notice.isEmpty ? nil : PostActionEffect(toast: notice, reloadSearchIndex: true)
    ))
}

func handleAddBookmark(
    client: NotionClient, urlVal: String, explicitTitle: String,
    tags: [String], autoFetch: Bool, ttlSeconds: Int, dataDir: String
) throws {
    guard !urlVal.isEmpty else {
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2, title: "未检测到可收藏链接", subtitle: "请在命令中附带网址，或先复制网页链接到剪贴板", badge: "ADD",
            items: [
                ViewItem(title: "用法：bm add https://example.com [自定义标题] [#标签]", subtitle: "也可先复制链接，再输入 bm 点击「一键收藏剪贴板链接」", icon: "link.badge.plus", copyText: "bm add https://example.com #常用"),
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
        payload: ["title": title, "url": urlVal, "description": meta.description, "tags": tags, "pinned": false, "priority": 0],
        schemaMap: schemaMap
    )
    items.removeAll { $0.id == created.id }
    items.insert(created, at: 0)
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)

    var viewItems: [ViewItem] = [
        ViewItem(title: created.title, subtitle: created.url, icon: "checkmark.circle.fill", badge: "已入库", copyText: created.url, openURL: created.url, commandArgs: ["--detail", created.id]),
        ViewItem(title: "置顶此书签", subtitle: "同步写入 Notion 置顶状态（Nav-Notion-Lime Dock 可见）", icon: "pin.fill", commandArgs: ["--set-pin", created.id, "true"]),
        ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])
    ]
    if !created.notionUrl.isEmpty {
        viewItems.append(ViewItem(title: "在 Notion 中查看页面", subtitle: created.notionUrl, icon: "doc.text", openURL: created.notionUrl))
    }

    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "已收藏到 Notion 书签库",
        subtitle: "\(dbTitle) · 标签：\(tags.isEmpty ? "无" : tags.joined(separator: ", "))", badge: "SAVED",
        metrics: [KeyValue(key: "标题", value: String(created.title.prefix(28))), KeyValue(key: "总书签数", value: String(items.count))],
        items: viewItems, effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

func handleUpdateFields(
    client: NotionClient, pageID: String, updates: [String: Any],
    ttlSeconds: Int, dataDir: String, showDetail: Bool = true
) throws {
    var (dbTitle, schemaMap, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    if schemaMap.isEmpty {
        let info = try client.retrieveDatabaseInfo()
        dbTitle = info.title; schemaMap = info.schema
    }
    let updated = try client.updateBookmark(pageID: pageID, payload: updates, schemaMap: schemaMap)
    var found = false
    for i in items.indices where items[i].id == pageID { items[i] = updated; found = true }
    if !found { items.append(updated) }
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: items, dataDir: dataDir)

    if showDetail {
        try handleDetailView(client: client, pageID: pageID, ttlSeconds: ttlSeconds, dataDir: dataDir, notice: "✅ 已同步更新到 Notion")
        return
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "书签已更新", subtitle: updated.title, badge: "UPDATED",
        items: [formatBookmarkItem(updated), ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])],
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

func handleArchiveBookmark(client: NotionClient, pageID: String, ttlSeconds: Int, dataDir: String) throws {
    let (dbTitle, schemaMap, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
    let target = findBookmarkTarget(items, needle: pageID)
    try client.archiveBookmark(pageID: pageID)
    let remaining = items.filter { $0.id != pageID }
    saveCache(databaseID: client.databaseID, dbTitle: dbTitle, schemaMap: schemaMap, items: remaining, dataDir: dataDir)
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "已归档书签", subtitle: "已将「\(target?.title ?? pageID)」移入 Notion 废纸篓", badge: "ARCHIVED",
        metrics: [KeyValue(key: "剩余书签", value: String(remaining.count))],
        items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])],
        effect: PostActionEffect(reloadSearchIndex: true)
    ))
}

func handleListView(
    client: NotionClient, query: String, clipboardURL: String,
    maxItems: Int, ttlSeconds: Int, dataDir: String, forceRefresh: Bool = false
) throws {
    let (dbTitle, _, items, syncStatus) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: forceRefresh)
    let filtered = filterBookmarks(items, query: query)
    let pinnedCount = items.filter(\.pinned).count
    let qTrim = query.trimmingCharacters(in: .whitespacesAndNewlines)

    var viewItems: [ViewItem] = []
    if qTrim.isEmpty {
        viewItems.append(ViewItem(
            id: "add-bookmark-form", title: "➕ 新增书签到 Notion", subtitle: "弹窗填写网址、标题与标签（支持自动抓取网页元数据）", icon: "plus.app.fill", badge: "NEW",
            actions: [
                ViewAction(
                    id: "add-form", label: "填写表单", style: "primary", commandArgs: ["--add-form"],
                    promptFields: [
                        PromptField(key: "url", label: "网页链接 URL", type: "text", defaultValue: clipboardURL, placeholder: "https://...", required: true),
                        PromptField(key: "title", label: "标题（留空则自动抓取）", type: "text", placeholder: "可选"),
                        PromptField(key: "tags", label: "标签（逗号分隔）", type: "text", defaultValue: "书签")
                    ]
                )
            ]
        ))
        if !clipboardURL.isEmpty {
            viewItems.append(ViewItem(title: "⭐ 一键收藏剪贴板链接", subtitle: clipboardURL, icon: "plus.circle.fill", badge: "CLIPBOARD", copyText: clipboardURL, commandArgs: ["--add-clipboard"]))
        }
    }

    for bm in filtered.prefix(maxItems) { viewItems.append(formatBookmarkItem(bm)) }
    if filtered.isEmpty {
        viewItems.append(ViewItem(title: qTrim.isEmpty ? "书签库暂无数据" : "未匹配到相关书签", subtitle: "可输入 bm add <网址> 新增，或点击下方强制刷新 Notion 缓存", icon: "tray"))
    }
    viewItems.append(ViewItem(title: "强制刷新 Notion 书签缓存", subtitle: "当前数据源状态：\(syncStatus)", icon: "arrow.clockwise", badge: "SYNC", commandArgs: ["--refresh"]))

    let subtitle = qTrim.isEmpty ? "\(dbTitle) · \(syncStatus)" : "筛选「\(qTrim)」命中 \(filtered.count) / \(items.count) 条 · \(syncStatus)"
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "Notion 书签收藏", subtitle: subtitle, badge: "BOOKMARKS",
        metrics: [
            KeyValue(key: "总书签", value: String(items.count)),
            KeyValue(key: "已置顶", value: String(pinnedCount)),
            KeyValue(key: "当前展示", value: "\(min(filtered.count, maxItems))/\(filtered.count)")
        ],
        items: viewItems,
        effect: PostActionEffect(reloadSearchIndex: forceRefresh, statusSummary: "\(dbTitle) · \(items.count) 条书签", statusBadge: String(items.count))
    ))
}
