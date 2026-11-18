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
        return "\(String(h[0..<8]))-\(String(h[8..<12]))-\(String(h[12..<16]))-\(String(h[16..<20]))-\(String(h[20..<32]))"
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
    return String(trimmed[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?，。；！？"))
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
    for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "] {
        out = out.replacingOccurrences(of: k, with: v)
    }
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
            return decodeHTMLEntities(String(body[r]))
                .replacingOccurrences(of: "\r", with: " ")
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
            "User-Agent": "LucentNotionBookmarks/1.0",
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
