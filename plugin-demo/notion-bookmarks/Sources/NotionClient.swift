import Foundation
import PluginKit

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
            if let hit = lowered[cand.lowercased()] { resolved[logical] = hit; break }
        }
    }
    if resolved["title"] == nil {
        for (propName, propMeta) in dbProps {
            if let dict = propMeta as? [String: Any], (dict["type"] as? String) == "title" {
                resolved["title"] = (propName, "title"); break
            }
        }
    }
    return resolved
}

private func findProp(_ props: [String: Any], logical: String) -> [String: Any]? {
    var lowered: [String: [String: Any]] = [:]
    for (k, v) in props { if let d = v as? [String: Any] { lowered[k.lowercased()] = d } }
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
    let titleArr = (findProp(props, logical: "title")?["title"] as? [[String: Any]]) ?? []
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

    let desc = ((findProp(props, logical: "description")?["rich_text"] as? [[String: Any]]) ?? [])
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

    let priority = (findProp(props, logical: "priority")?["number"] as? NSNumber)?.intValue ?? 0
    var pinnedFlag = false
    if let pinProp = findProp(props, logical: "pinned") {
        let ptype = (pinProp["type"] as? String) ?? ""
        if ptype == "checkbox" { pinnedFlag = (pinProp["checkbox"] as? Bool) ?? false }
        else if ptype == "select", let sel = pinProp["select"] as? [String: Any], let n = sel["name"] as? String {
            pinnedFlag = ["置顶", "Yes", "true", "True"].contains(n)
        }
    }

    return BookmarkItem(
        id: (page["id"] as? String) ?? "",
        notionUrl: (page["url"] as? String) ?? "",
        title: title, url: urlVal, description: desc,
        tags: mergedTags, category: primaryCategory, icon: icon,
        priority: priority, pinned: pinnedFlag || priority > 0,
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

func buildNotionProperties(payload: [String: Any], schemaMap: [String: (name: String, type: String)]) -> [String: Any] {
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
            props[urlName] = ["rich_text": clean.isEmpty ? [] : [["type": "text", "text": ["content": clean, "link": ["url": clean]]]]]
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
        let rawBase = apiBase ?? ProcessInfo.processInfo.environment["LUCENT_NOTION_API_BASE"] ?? defaultBase
        self.apiBase = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
    }

    private func request(method: String, path: String, body: [String: Any]? = nil, timeout: Double = 4.5) throws -> [String: Any] {
        guard let url = URL(string: "\(apiBase)\(path)") else {
            throw NotionAPIError(status: 0, code: "invalid_url", message: "无效的 Notion API 地址")
        }
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let resp = SyncHTTPClient.request(
            url: url, method: method,
            headers: ["Authorization": ["Bearer", token].joined(separator: " "), "Notion-Version": notionVersion, "Content-Type": "application/json"],
            body: bodyData, timeoutSeconds: timeout
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
        return (rawTitle.isEmpty ? "Notion 书签库" : rawTitle, resolveSchemaMap((db["properties"] as? [String: Any]) ?? [:]))
    }

    func queryAllBookmarks(maxPages: Int = 3) throws -> [BookmarkItem] {
        var items: [BookmarkItem] = [], cursor: String? = nil
        for _ in 0..<maxPages {
            var payload: [String: Any] = ["page_size": 100]
            if let cursor { payload["start_cursor"] = cursor }
            let res = try request(method: "POST", path: "/databases/\(databaseID)/query", body: payload)
            for page in (res["results"] as? [[String: Any]]) ?? [] where (page["archived"] as? Bool) != true {
                items.append(transformPage(page))
            }
            guard (res["has_more"] as? Bool) == true, let next = res["next_cursor"] as? String, !next.isEmpty else { break }
            cursor = next
        }
        return sortBookmarks(items)
    }

    func createBookmark(payload: [String: Any], schemaMap: [String: (name: String, type: String)]) throws -> BookmarkItem {
        let props = buildNotionProperties(payload: payload, schemaMap: schemaMap)
        return transformPage(try request(method: "POST", path: "/pages", body: ["parent": ["database_id": databaseID], "properties": props]))
    }

    func updateBookmark(pageID: String, payload: [String: Any], schemaMap: [String: (name: String, type: String)]) throws -> BookmarkItem {
        let props = buildNotionProperties(payload: payload, schemaMap: schemaMap)
        return transformPage(try request(method: "PATCH", path: "/pages/\(pageID)", body: ["properties": props]))
    }

    func archiveBookmark(pageID: String) throws {
        _ = try request(method: "PATCH", path: "/pages/\(pageID)", body: ["archived": true])
    }
}
