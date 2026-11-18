import Foundation
import PluginKit

let notionVersion = "2022-06-28"
let fieldCandidates: [String: [String]] = [
    "title": ["name", "title", "名称", "标题"],
    "url": ["url", "link", "链接", "地址"],
    "description": ["description", "desc", "描述", "说明"],
    "tags": ["tag", "tags", "标签"],
    "category": ["category", "group", "分类", "分组"],
    "icon": ["icon", "图标"],
    "priority": ["priority", "sort", "优先级"],
    "pinned": ["pinned", "pin", "is_top", "置顶"]
]

struct NotionAPIError: Error {
    let status: Int
    let code: String
    let message: String
}

struct BookmarkItem: Codable {
    var id: String
    var notionUrl: String
    var title: String
    var url: String
    var description: String
    var tags: [String]
    var category: String
    var icon: String
    var priority: Int
    var pinned: Bool
    var createdTime: String
    var lastEditedTime: String
}

struct NotionCacheEnvelope: Codable {
    var fetchedAt: Double
    var dbTitle: String
    var schema: [String: [String]]
    var items: [BookmarkItem]
}

func normalizeDatabaseID(_ raw: String) -> String {
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return "" }
    let uuidRe = try! NSRegularExpression(pattern: #"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#)
    let r1 = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
    if let m = uuidRe.firstMatch(in: cleaned, range: r1), let r = Range(m.range(at: 1), in: cleaned) {
        return cleaned[r].lowercased()
    }
    let beforeQuery = cleaned.split(separator: "?").first.map(String.init) ?? cleaned
    let compact = beforeQuery.replacingOccurrences(of: "-", with: "")
    let hexRe = try! NSRegularExpression(pattern: #"([0-9a-fA-F]{32})"#)
    let r2 = NSRange(compact.startIndex..<compact.endIndex, in: compact)
    if let m = hexRe.firstMatch(in: compact, range: r2), let r = Range(m.range(at: 1), in: compact) {
        let h = Array(compact[r].lowercased())
        let p1 = String(h[0..<8]), p2 = String(h[8..<12]), p3 = String(h[12..<16]), p4 = String(h[16..<20]), p5 = String(h[20..<32])
        return "\(p1)-\(p2)-\(p3)-\(p4)-\(p5)"
    }
    return cleaned
}

func extractFirstURL(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let urlRe = try! NSRegularExpression(pattern: #"(https?://[^\s<>\"'\]\)]+)"#, options: [.caseInsensitive])
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let m = urlRe.firstMatch(in: trimmed, range: range), let r = Range(m.range(at: 1), in: trimmed) else {
        return ""
    }
    let punct = CharacterSet(charactersIn: ".,;!?，。；！？")
    return String(trimmed[r]).trimmingCharacters(in: punct)
}

func normalizeTargetURL(_ raw: String) -> String {
    let first = extractFirstURL(raw)
    var candidate = first.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : first
    guard !candidate.isEmpty else { return "" }
    if !candidate.lowercased().hasPrefix("http://") && !candidate.lowercased().hasPrefix("https://") {
        candidate = "https://" + candidate
    }
    return candidate
}

func isTruthy(_ raw: String) -> Bool {
    ["1", "true", "yes", "y", "on", "是"].contains(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

func parseTagsCSV(_ raw: String) -> [String] {
    let parts = raw.components(separatedBy: CharacterSet(charactersIn: ",，、"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    var seen = Set<String>()
    return parts.filter { seen.insert($0).inserted }
}

func decodeHTMLEntities(_ text: String) -> String {
    var out = text
    let map = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "
    ]
    for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
    return out
}

private func extractMetaContent(body: String, attr: String, value: String) -> String {
    let valEsc = NSRegularExpression.escapedPattern(for: value)
    let p1 = "<meta[^>]+\\b\(attr)\\s*=\\s*[\"']\(valEsc)[\"'][^>]+content\\s*=\\s*[\"']([^\"']*)[\"']"
    let p2 = "<meta[^>]+content\\s*=\\s*[\"']([^\"']*)[\"'][^>]+\\b\(attr)\\s*=\\s*[\"']\(valEsc)[\"']"
    let range = NSRange(body.startIndex..<body.endIndex, in: body)
    for pat in [p1, p2] {
        if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
           let m = re.firstMatch(in: body, range: range),
           let r = Range(m.range(at: 1), in: body) {
            let unescaped = decodeHTMLEntities(String(body[r]))
            return unescaped.replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return ""
}

func fetchURLMetadata(_ targetURL: String, timeout: Double = 2.5) -> (title: String, description: String) {
    let hostname = (URL(string: targetURL)?.host ?? targetURL).replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    guard let url = URL(string: targetURL) else { return (hostname, "") }

    let resp = SyncHTTPClient.request(
        url: url,
        headers: [
            "User-Agent": "LumakeyNotionBookmarks/1.0",
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ],
        timeoutSeconds: timeout
    )
    guard resp.isSuccess else { return (hostname, "") }
    let body = String(decoding: resp.data.prefix(262_144), as: UTF8.self)

    var title = extractMetaContent(body: body, attr: "property", value: "og:title")
    if title.isEmpty,
       let titleRe = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        if let m = titleRe.firstMatch(in: body, range: range), let r = Range(m.range(at: 1), in: body) {
            title = decodeHTMLEntities(String(body[r]))
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    if !title.isEmpty,
       let suffixRe = try? NSRegularExpression(pattern: #"\s*[-_|—–·]\s*(?:哔哩哔哩|bilibili|知乎|GitHub|百度百科|官方网站|Official Site|主页).*$"#, options: [.caseInsensitive]) {
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        let stripped = suffixRe.stringByReplacingMatches(in: title, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stripped.isEmpty { title = stripped }
    }
    let ogDesc = extractMetaContent(body: body, attr: "property", value: "og:description")
    let desc = ogDesc.isEmpty ? extractMetaContent(body: body, attr: "name", value: "description") : ogDesc
    return (title.isEmpty ? hostname : title, desc)
}

func resolveSchemaMap(_ dbProps: [String: Any]) -> [String: (name: String, type: String)] {
    var lowered: [String: (String, String)] = [:]
    for (k, v) in dbProps {
        if let dict = v as? [String: Any] {
            lowered[k.lowercased()] = (k, (dict["type"] as? String) ?? "")
        }
    }
    var resolved: [String: (String, String)] = [:]
    for (logical, cands) in fieldCandidates {
        for cand in cands {
            if let hit = lowered[cand.lowercased()] {
                resolved[logical] = hit
                break
            }
        }
    }
    if resolved["title"] == nil {
        for (propName, propMeta) in dbProps {
            if let dict = propMeta as? [String: Any], (dict["type"] as? String) == "title" {
                resolved["title"] = (propName, "title")
                break
            }
        }
    }
    return resolved
}

private func findProp(_ props: [String: Any], logical: String) -> [String: Any]? {
    var lowered: [String: [String: Any]] = [:]
    for (k, v) in props {
        if let d = v as? [String: Any] { lowered[k.lowercased()] = d }
    }
    for cand in fieldCandidates[logical] ?? [] {
        if let hit = lowered[cand.lowercased()] { return hit }
    }
    if logical == "title" {
        for v in props.values {
            if let d = v as? [String: Any], (d["type"] as? String) == "title" { return d }
        }
    }
    return nil
}

func transformPage(_ page: [String: Any]) -> BookmarkItem {
    let props = (page["properties"] as? [String: Any]) ?? [:]

    let titleProp = findProp(props, logical: "title")
    let titleArr = (titleProp?["title"] as? [[String: Any]]) ?? []
    let rawTitle = titleArr.compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    let title = rawTitle.isEmpty ? "Untitled" : rawTitle

    var urlVal = ""
    if let urlProp = findProp(props, logical: "url") {
        let ptype = (urlProp["type"] as? String) ?? ""
        if ptype == "url" {
            urlVal = ((urlProp["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if ptype == "rich_text", let items = urlProp["rich_text"] as? [[String: Any]], let first = items.first {
            if let textObj = first["text"] as? [String: Any],
               let linkObj = textObj["link"] as? [String: Any],
               let linkURL = linkObj["url"] as? String {
                urlVal = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                urlVal = items.compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    let descProp = findProp(props, logical: "description")
    let desc = ((descProp?["rich_text"] as? [[String: Any]]) ?? [])
        .compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

    var tags: [String] = []
    if let tagProp = findProp(props, logical: "tags") {
        let ptype = (tagProp["type"] as? String) ?? ""
        if ptype == "multi_select", let arr = tagProp["multi_select"] as? [[String: Any]] {
            tags = arr.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if ptype == "select", let sel = tagProp["select"] as? [String: Any], let n = sel["name"] as? String {
            tags = [n.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        } else if ptype == "rich_text" {
            let rt = ((tagProp["rich_text"] as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined()
            tags = rt.components(separatedBy: CharacterSet(charactersIn: ",，、 \t\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    var rawCategory = ""
    if let catProp = findProp(props, logical: "category") {
        let ptype = (catProp["type"] as? String) ?? ""
        if ptype == "select", let sel = catProp["select"] as? [String: Any], let n = sel["name"] as? String {
            rawCategory = n.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if ptype == "rich_text" {
            rawCategory = ((catProp["rich_text"] as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    let mergedTags = (!rawCategory.isEmpty && !tags.contains(rawCategory)) ? ([rawCategory] + tags) : tags
    let primaryCategory = !rawCategory.isEmpty ? rawCategory : (mergedTags.first ?? "")

    var icon = ""
    if let iconProp = findProp(props, logical: "icon") {
        let ptype = (iconProp["type"] as? String) ?? ""
        if ptype == "phone_number", let p = iconProp["phone_number"] as? String { icon = p.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if ptype == "url", let u = iconProp["url"] as? String { icon = u.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if ptype == "rich_text" {
            icon = ((iconProp["rich_text"] as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    let prioProp = findProp(props, logical: "priority")
    let priority = (prioProp?["number"] as? NSNumber)?.intValue ?? 0

    var pinnedFlag = false
    if let pinProp = findProp(props, logical: "pinned") {
        let ptype = (pinProp["type"] as? String) ?? ""
        if ptype == "checkbox" {
            pinnedFlag = (pinProp["checkbox"] as? Bool) ?? false
        } else if ptype == "select", let sel = pinProp["select"] as? [String: Any], let n = sel["name"] as? String {
            pinnedFlag = ["置顶", "Yes", "true", "True"].contains(n)
        }
    }

    return BookmarkItem(
        id: (page["id"] as? String) ?? "",
        notionUrl: (page["url"] as? String) ?? "",
        title: title,
        url: urlVal,
        description: desc,
        tags: mergedTags,
        category: primaryCategory,
        icon: icon,
        priority: priority,
        pinned: pinnedFlag || priority > 0,
        createdTime: (page["created_time"] as? String) ?? "",
        lastEditedTime: (page["last_edited_time"] as? String) ?? ""
    )
}

func sortBookmarks(_ items: [BookmarkItem]) -> [BookmarkItem] {
    items.sorted { a, b in
        if a.pinned != b.pinned { return a.pinned }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.title.lowercased() < b.title.lowercased()
    }
}

func buildNotionProperties(
    payload: [String: Any],
    schemaMap: [String: (name: String, type: String)],
    isUpdate: Bool
) -> [String: Any] {
    var props: [String: Any] = [:]
    let (titleName, _) = schemaMap["title"] ?? ("name", "title")
    let (urlName, urlType) = schemaMap["url"] ?? ("url", "rich_text")

    if let titleVal = payload["title"] as? String {
        props[titleName] = ["title": [["type": "text", "text": ["content": titleVal.trimmingCharacters(in: .whitespacesAndNewlines)]]]]
    }
    if let urlVal = payload["url"] as? String {
        let clean = urlVal.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlType == "url" {
            let urlObj: Any = clean.isEmpty ? NSNull() : clean
            props[urlName] = ["url": urlObj]
        } else {
            props[urlName] = [
                "rich_text": clean.isEmpty ? [] : [["type": "text", "text": ["content": clean, "link": ["url": clean]]]]
            ]
        }
    }
    if let desc = payload["description"] as? String, (schemaMap.isEmpty || schemaMap["description"] != nil) {
        let (descName, _) = schemaMap["description"] ?? ("description", "rich_text")
        let trimmed = String(desc.prefix(1900))
        props[descName] = ["rich_text": trimmed.isEmpty ? [] : [["type": "text", "text": ["content": trimmed]]]]
    }
    if let tags = payload["tags"] as? [String], (schemaMap.isEmpty || schemaMap["tags"] != nil) {
        let (tagName, tagType) = schemaMap["tags"] ?? ("tag", "multi_select")
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if tagType == "select" {
            let selObj: Any = if let firstTag = cleanTags.first { ["name": firstTag] } else { NSNull() }
            props[tagName] = ["select": selObj]
        } else if tagType == "rich_text" {
            let joined = cleanTags.joined(separator: ", ")
            props[tagName] = ["rich_text": joined.isEmpty ? [] : [["type": "text", "text": ["content": joined]]]]
        } else {
            props[tagName] = ["multi_select": cleanTags.map { ["name": $0] }]
        }
    }
    if let prio = payload["priority"] as? Int, let (prioName, prioType) = schemaMap["priority"], prioType == "number" {
        props[prioName] = ["number": prio]
    }
    if let pinBool = payload["pinned"] as? Bool, let (pinName, pinType) = schemaMap["pinned"] {
        if pinType == "checkbox" {
            props[pinName] = ["checkbox": pinBool]
        } else if pinType == "select" {
            let pinObj: Any = pinBool ? ["name": "置顶"] : NSNull()
            props[pinName] = ["select": pinObj]
        }
    }
    _ = isUpdate
    return props
}

final class NotionClient {
    let token: String
    let databaseID: String
    let apiBase: String

    init(token: String, databaseID: String, apiBase: String? = nil) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.databaseID = normalizeDatabaseID(databaseID)
        let defaultBase = ["https", "://", "api.", "notion.com", "/v1"].joined()
        let rawBase = apiBase ?? ProcessInfo.processInfo.environment["LUMAKEY_NOTION_API_BASE"] ?? defaultBase
        self.apiBase = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
    }

    private func request(method: String, path: String, body: [String: Any]? = nil, timeout: Double = 4.5) throws -> [String: Any] {
        guard let url = URL(string: "\(apiBase)\(path)") else {
            throw NotionAPIError(status: 0, code: "invalid_url", message: "无效的 Notion API 地址")
        }
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let authHeader = ["Bearer", token].joined(separator: " ")
        let resp = SyncHTTPClient.request(
            url: url,
            method: method,
            headers: [
                "Authorization": authHeader,
                "Notion-Version": notionVersion,
                "Content-Type": "application/json"
            ],
            body: bodyData,
            timeoutSeconds: timeout
        )
        if let netErr = resp.errorDescription, resp.statusCode == 0 {
            throw NotionAPIError(status: 0, code: "network_error", message: "网络请求失败：\(netErr)")
        }
        if !(200...299).contains(resp.statusCode) {
            let parsed = resp.jsonObject()
            let code = (parsed?["code"] as? String) ?? "http_\(resp.statusCode)"
            let msg = (parsed?["message"] as? String) ?? (resp.text.isEmpty ? "HTTP \(resp.statusCode)" : resp.text)
            throw NotionAPIError(status: resp.statusCode, code: code, message: msg)
        }
        return resp.jsonObject() ?? [:]
    }

    func retrieveDatabaseInfo() throws -> (title: String, schema: [String: (name: String, type: String)]) {
        let db = try request(method: "GET", path: "/databases/\(databaseID)")
        let titleArr = (db["title"] as? [[String: Any]]) ?? []
        let rawTitle = titleArr.compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let dbTitle = rawTitle.isEmpty ? "Notion 书签库" : rawTitle
        let props = (db["properties"] as? [String: Any]) ?? [:]
        return (dbTitle, resolveSchemaMap(props))
    }

    func queryAllBookmarks(maxPages: Int = 3) throws -> [BookmarkItem] {
        var items: [BookmarkItem] = []
        var cursor: String? = nil
        for _ in 0..<maxPages {
            var payload: [String: Any] = ["page_size": 100]
            if let cursor { payload["start_cursor"] = cursor }
            let res = try request(method: "POST", path: "/databases/\(databaseID)/query", body: payload)
            let pages = (res["results"] as? [[String: Any]]) ?? []
            for page in pages where (page["archived"] as? Bool) != true {
                items.append(transformPage(page))
            }
            guard (res["has_more"] as? Bool) == true,
                  let next = res["next_cursor"] as? String, !next.isEmpty else {
                break
            }
            cursor = next
        }
        return sortBookmarks(items)
    }

    func createBookmark(payload: [String: Any], schemaMap: [String: (name: String, type: String)]) throws -> BookmarkItem {
        let props = buildNotionProperties(payload: payload, schemaMap: schemaMap, isUpdate: false)
        let page = try request(
            method: "POST",
            path: "/pages",
            body: ["parent": ["database_id": databaseID], "properties": props]
        )
        return transformPage(page)
    }

    func updateBookmark(pageID: String, payload: [String: Any], schemaMap: [String: (name: String, type: String)]) throws -> BookmarkItem {
        let props = buildNotionProperties(payload: payload, schemaMap: schemaMap, isUpdate: true)
        let page = try request(method: "PATCH", path: "/pages/\(pageID)", body: ["properties": props])
        return transformPage(page)
    }

    func archiveBookmark(pageID: String) throws {
        _ = try request(method: "PATCH", path: "/pages/\(pageID)", body: ["archived": true])
    }
}
