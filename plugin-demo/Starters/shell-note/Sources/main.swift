import Foundation
import PluginKit

struct NoteEntry {
    var id: String
    var done: Bool
    var pinned: Bool
    var ts: String
    var body: String
}

private let lineRe = try! NSRegularExpression(
    pattern: #"^- \[([ xX])\] (⭐ )?\[([^\]]+)\] (.*?)(?:\s*<!--\s*id:([a-f0-9]+)\s*-->)?$"#
)
private let tagRe = try! NSRegularExpression(pattern: #"#([\w\u4e00-\u9fff-]+)"#)

private func extractTags(from text: String, includeHash: Bool) -> [String] {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return tagRe.matches(in: text, range: range).compactMap { m in
        let grp = includeHash ? 0 : 1
        guard let r = Range(m.range(at: grp), in: text) else { return nil }
        return String(text[r])
    }
}

private func parseNotes(at url: URL) -> (header: [String], notes: [NoteEntry]) {
    guard FileManager.default.fileExists(atPath: url.path),
          let raw = try? String(contentsOf: url, encoding: .utf8) else {
        return (["# Lumakey Quick Capture Inbox", ""], [])
    }
    var header: [String] = []
    var notes: [NoteEntry] = []
    for rawLine in raw.components(separatedBy: .newlines) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let m = lineRe.firstMatch(in: trimmed, range: nsRange),
           let doneR = Range(m.range(at: 1), in: trimmed),
           let tsR = Range(m.range(at: 3), in: trimmed),
           let bodyR = Range(m.range(at: 4), in: trimmed) {
            let done = trimmed[doneR].lowercased() == "x"
            let pinned = m.range(at: 2).location != NSNotFound
            let ts = trimmed[tsR].trimmingCharacters(in: .whitespaces)
            let body = trimmed[bodyR].trimmingCharacters(in: .whitespaces)
            let nid: String
            if m.range(at: 5).location != NSNotFound, let idR = Range(m.range(at: 5), in: trimmed) {
                nid = String(trimmed[idR])
            } else {
                nid = String(DigestUtils.sha1Hex("\(ts):\(body)").prefix(8))
            }
            notes.append(NoteEntry(id: nid, done: done, pinned: pinned, ts: ts, body: body))
        } else if notes.isEmpty {
            header.append(rawLine)
        }
    }
    while let last = header.last, last.isEmpty, header.count > 2 {
        header.removeLast()
    }
    if header.isEmpty {
        header = ["# Lumakey Quick Capture Inbox", ""]
    }
    return (header, notes)
}

private func encodeReaderLink(for fileURL: URL) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?#")
    let encoded = fileURL.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileURL.path
    return "lumakey://reader?path=\(encoded)"
}

private func saveNotes(at mdURL: URL, header: [String], notes: [NoteEntry], dataDir: String) {
    let fm = FileManager.default
    try? fm.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var lines = header
    if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
        lines.append("")
    }
    for n in notes {
        let mark = n.done ? "x" : " "
        let pin = n.pinned ? "⭐ " : ""
        lines.append("- [\(mark)] \(pin)[\(n.ts)] \(n.body) <!-- id:\(n.id) -->")
    }
    let outText = lines.joined(separator: "\n") + "\n"
    try? outText.write(to: mdURL, atomically: true, encoding: .utf8)

    if !dataDir.isEmpty {
        let readerURL = encodeReaderLink(for: mdURL)
        let idxItems: [SearchIndexItem] = notes.prefix(60).map { n in
            SearchIndexItem(
                id: n.id,
                title: (n.pinned ? "⭐ " : "") + n.body,
                subtitle: "\(n.ts) · \(n.done ? "已完成" : "待办速记")",
                url: readerURL,
                copyText: n.body,
                icon: n.done ? "checkmark.circle.fill" : (n.pinned ? "pin.fill" : "note.text"),
                tags: extractTags(from: n.body, includeHash: false),
                pinned: n.pinned,
                priority: n.pinned ? 60 : 15
            )
        }
        PluginOutput.writeSearchIndex(idxItems, to: dataDir)
        PluginOutput.writeRuntimeStatus(summary: "\(notes.count) notes", badge: "\(notes.count)", to: dataDir)
    }
}

let input = PluginInput.read()
let isEn = input.isEnglish
var query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let ctxText = (input.context?.url ?? input.context?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
let dataDir = input.dataDir

let expandedPath = input.cfgExpandedPath("notesPath", default: "~/Documents/Lumakey-Notes.md")
let mdURL = URL(fileURLWithPath: expandedPath).standardizedFileURL

var defTag = input.cfgString("defaultTag", default: "#idea")
if !defTag.isEmpty && !defTag.hasPrefix("#") {
    defTag = "#" + defTag
}
let maxItems = input.cfgInt("maxShownNotes", default: 15, min: 1, max: 100)
let args = input.arguments

var (header, notes) = parseNotes(at: mdURL)
var toast: String? = nil
var openReader = false

if args.contains("--open-reader") {
    if !FileManager.default.fileExists(atPath: mdURL.path) {
        saveNotes(at: mdURL, header: header, notes: notes, dataDir: dataDir)
    }
    openReader = true
} else if args.count >= 2 && args[0] == "--pin" {
    let targetID = args[1]
    for i in notes.indices where notes[i].id == targetID {
        notes[i].pinned.toggle()
        toast = isEn ? "Updated pin state" : (notes[i].pinned ? "已置顶该条速记" : "已取消置顶")
    }
    saveNotes(at: mdURL, header: header, notes: notes, dataDir: dataDir)
} else if args.count >= 2 && args[0] == "--done" {
    let targetID = args[1]
    for i in notes.indices where notes[i].id == targetID {
        notes[i].done.toggle()
        toast = isEn ? "Toggled completion" : (notes[i].done ? "已标记完成" : "已恢复为未完成")
    }
    saveNotes(at: mdURL, header: header, notes: notes, dataDir: dataDir)
} else if args.count >= 2 && args[0] == "--delete" {
    let before = notes.count
    notes.removeAll { $0.id == args[1] }
    if notes.count != before {
        toast = isEn ? "Deleted note" : "已删除该条速记"
        saveNotes(at: mdURL, header: header, notes: notes, dataDir: dataDir)
    }
} else if !args.contains("--browse") {
    var captureBody = ""
    if query.hasPrefix("+") {
        captureBody = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if !ctxText.isEmpty && query.isEmpty {
        captureBody = ctxText
    } else if !query.isEmpty && !query.hasPrefix("?") && !query.hasPrefix("#") {
        captureBody = query
    }
    if !captureBody.isEmpty {
        var clean = captureBody.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !defTag.isEmpty && !clean.contains("#") {
            clean = "\(defTag) \(clean)"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        let ts = df.string(from: Date())
        let nid = String(DigestUtils.sha1Hex("\(ts):\(clean):\(notes.count)").prefix(8))
        notes.insert(NoteEntry(id: nid, done: false, pinned: false, ts: ts, body: clean), at: 0)
        saveNotes(at: mdURL, header: header, notes: notes, dataDir: dataDir)
        toast = isEn ? "Saved to Markdown Inbox" : "已写入灵感收件箱并同步免前缀索引"
        query = ""
    }
}

let shouldFilter = args.contains("--browse") || query.hasPrefix("?") || query.hasPrefix("#")
let filterQ = shouldFilter
    ? query.trimmingCharacters(in: CharacterSet(charactersIn: "?")).trimmingCharacters(in: .whitespaces).lowercased()
    : ""

var ordered = notes.enumerated().sorted { lhs, rhs in
    let a = lhs.element, b = rhs.element
    let pinA = a.pinned ? 0 : 1, pinB = b.pinned ? 0 : 1
    if pinA != pinB { return pinA < pinB }
    let doneA = a.done ? 1 : 0, doneB = b.done ? 1 : 0
    if doneA != doneB { return doneA < doneB }
    return lhs.offset < rhs.offset
}.map(\.element)

if !filterQ.isEmpty {
    ordered = ordered.filter {
        $0.body.lowercased().contains(filterQ) || $0.ts.lowercased().contains(filterQ)
    }
}

let readerLink = encodeReaderLink(for: mdURL)
var items: [ViewItem] = [
    ViewItem(
        id: "open-inbox-file",
        title: isEn ? "Open Full Markdown Inbox in Reader" : "在原生 Markdown 阅读窗打开完整收件箱",
        subtitle: mdURL.path,
        icon: "book.pages",
        badge: "READER",
        openURL: readerLink
    )
]

for n in ordered.prefix(maxItems) {
    let prefix = n.pinned ? "⭐ " : ""
    items.append(ViewItem(
        id: "note-\(n.id)",
        title: "\(prefix)\(n.body)",
        subtitle: isEn ? "\(n.ts) · \(n.done ? "Done" : "Inbox")" : "\(n.ts) · \(n.done ? "已完成" : "收件箱")",
        icon: n.done ? "checkmark.circle.fill" : (n.pinned ? "pin.circle.fill" : "note.text"),
        badge: n.done ? "DONE" : (n.pinned ? "PIN" : "NOTE"),
        copyText: n.body,
        actions: [
            ViewAction(
                id: "done-\(n.id)",
                label: isEn ? (n.done ? "Undo" : "Done") : (n.done ? "取消完成" : "完成"),
                commandArgs: ["--done", n.id]
            ),
            ViewAction(
                id: "pin-\(n.id)",
                label: isEn ? (n.pinned ? "Unpin" : "Pin") : (n.pinned ? "取消置顶" : "置顶"),
                commandArgs: ["--pin", n.id]
            ),
            ViewAction(
                id: "del-\(n.id)",
                label: isEn ? "Delete" : "删除",
                style: "destructive",
                commandArgs: ["--delete", n.id],
                confirmMessage: isEn ? "Delete this note from your Markdown inbox?" : "确认从 Markdown 收件箱中删除这条速记吗？"
            )
        ]
    ))
}

let pinnedCnt = notes.filter(\.pinned).count
let openCnt = notes.filter { !$0.done }.count
var allTags = Set<String>()
for n in notes {
    for t in extractTags(from: n.body, includeHash: true) { allTags.insert(t) }
}

let effect = PostActionEffect(
    toast: toast,
    reloadSearchIndex: true,
    statusSummary: "\(notes.count) notes",
    statusBadge: "\(notes.count)",
    openReaderPath: openReader ? mdURL.path : nil
)

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Quick Capture & Markdown Inbox" : "灵感速记与 Markdown 收件箱",
    subtitle: isEn
        ? "Direct input appends note · Prefix '?' or '#tag' filters (\(ordered.count)/\(notes.count))"
        : "直接输入即追加速记 · 以 ? 或 #标签 开头可检索筛选（\(ordered.count)/\(notes.count) 条）",
    badge: "\(notes.count) NOTES",
    metrics: [
        KeyValue(key: isEn ? "Total" : "累计速记", value: String(notes.count)),
        KeyValue(key: isEn ? "Open" : "待处理", value: String(openCnt)),
        KeyValue(key: isEn ? "Pinned" : "置顶星标", value: String(pinnedCnt)),
        KeyValue(key: isEn ? "Tags" : "活跃标签", value: String(allTags.count))
    ],
    items: items,
    effect: effect
))
