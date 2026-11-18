import Foundation
import PluginKit

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
    let notionPortal = "https://www.notion.so/my-integrations"
    var items: [ViewItem] = [
        ViewItem(
            title: "打开 Lucent 插件设置填写凭证",
            subtitle: "填入 Token 与 Database ID 后点击「保存配置」即可使用",
            icon: "gearshape.fill", badge: "SETUP",
            openURL: "lucent://settings/plugin/notion-bookmarks"
        ),
        ViewItem(title: "获取 Notion Integration Token", subtitle: notionPortal, icon: "key.fill", copyText: notionPortal, openURL: notionPortal)
    ]
    if !clipboardURL.isEmpty {
        items.append(ViewItem(title: "已检测到剪贴板链接（配置完成后可一键收藏）", subtitle: clipboardURL, icon: "link", copyText: clipboardURL))
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "Notion 书签插件尚未配置", subtitle: "缺少：\(missing.joined(separator: "、"))", badge: "SETUP",
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
            if let tVal = (formData["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !tVal.isEmpty { updates["title"] = tVal }
            if let dVal = formData["description"] as? String { updates["description"] = dVal.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let tagsVal = formData["tags"] as? String { updates["tags"] = parseTagsCSV(tagsVal) }
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
        default: break
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
            ? String(query.split(maxSplits: 1, whereSeparator: \.isWhitespace)[1]) : ""
        let (targetQ, updates) = parseEditQuery(rest)
        let (_, _, items, _) = try syncBookmarks(client: client, ttlSeconds: ttlSeconds, dataDir: dataDir, force: false)
        guard let target = findBookmarkTarget(items, needle: targetQ), !updates.isEmpty else {
            PluginOutput.emit(ViewPayload(
                schemaVersion: 2, title: "编辑指令参数不足或未命中书签",
                subtitle: "用法：bm edit <书签标题或ID> title=... desc=... tags=a,b pin=true priority=10", badge: "EDIT",
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
                PluginOutput.emit(ViewPayload(schemaVersion: 2, title: "未找到匹配「\(needle)」的书签", badge: "404", items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])]))
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
                PluginOutput.emit(ViewPayload(schemaVersion: 2, title: "未找到匹配「\(needle)」的书签", badge: "404", items: [ViewItem(title: "返回书签列表", icon: "list.bullet", commandArgs: ["--list"])]))
                exit(0)
            }
            try handleArchiveBookmark(client: client, pageID: target.id, ttlSeconds: ttlSeconds, dataDir: dataDir)
            exit(0)
        }
    }

    try handleListView(client: client, query: query, clipboardURL: clipboardURL, maxItems: maxItems, ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: false)
} catch let err as NotionAPIError {
    var hint = "请检查 Notion Token 与 Database ID 是否正确，并确认数据库已 Connect 到你的 Integration。"
    if err.status == 401 { hint = "Notion Token 无效或已过期，请在插件中心更新。" }
    else if err.status == 404 { hint = "未找到对应数据库，请确认 Database ID 且已在 Notion 页面右上角 ... -> Connect to 授权。" }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "Notion API 请求失败 (\(err.status))", subtitle: String(err.message.prefix(120)), badge: "ERROR",
        items: [
            ViewItem(title: "打开 Lucent 插件设置检查凭证", subtitle: hint, icon: "gearshape.fill", openURL: "lucent://settings/plugin/notion-bookmarks"),
            ViewItem(title: "重试刷新", icon: "arrow.clockwise", commandArgs: ["--refresh"])
        ]
    ))
} catch {
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2, title: "插件执行异常", subtitle: String(error.localizedDescription.prefix(140)), badge: "ERROR",
        items: [ViewItem(title: "返回书签列表", icon: "arrow.uturn.backward", commandArgs: ["--list"])]
    ))
}
