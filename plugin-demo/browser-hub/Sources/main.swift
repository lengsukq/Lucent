import Foundation
import PluginKit

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
        forcedBrowser = argv[idx + 1].lowercased(); idx += 2; continue
    }
    if arg == "--kind", idx + 1 < argv.count {
        forcedKind = argv[idx + 1].lowercased(); idx += 2; continue
    }
    if arg == "--sync" {
        forceRefresh = true; didSync = true; idx += 1; continue
    }
    if arg == "--toggle-pin", idx + 1 < argv.count {
        let pinnedNow = togglePinnedURL(dataDir: dataDir, targetURL: argv[idx + 1])
        forceRefresh = true
        toastMsg = isEn ? (pinnedNow ? "Pinned to top" : "Unpinned") : (pinnedNow ? "已星标置顶该网页" : "已取消置顶")
        idx += 2; continue
    }
    if arg == "--open-in", idx + 2 < argv.count {
        let bTarget = argv[idx + 1].lowercased(), targetURL = argv[idx + 2]
        let ok = openURLInBrowser(browserKey: bTarget, targetURL: targetURL)
        let bName = browserSpecs[bTarget]?.label ?? bTarget
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2, title: isEn ? "Opened in \(bName)" : "已在 \(bName) 中打开",
            subtitle: targetURL, badge: ok ? "OPENED" : "ERROR", items: [],
            effect: PostActionEffect(
                toast: ok ? (isEn ? "Opened in \(bName)" : "已调用 \(bName) 打开链接") : (isEn ? "Failed to launch browser" : "调用浏览器打开失败"),
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
    enabledBrowsers: enabledBrowsers, historyDays: historyDays,
    ttlSeconds: ttlSeconds, dataDir: dataDir, forceRefresh: forceRefresh
)

if didSync {
    toastMsg = safariDenied
        ? (isEn ? "Full Disk Access needed for Safari; Chrome/Edge synced" : "Chrome/Edge 已同步；Safari 需授予「完全磁盘访问权限」才能读取")
        : (isEn ? "Browser search index refreshed" : "已同步刷新三端浏览器免前缀检索索引")
}

var bFilter = forcedBrowser, kFilter = forcedKind, folderTags: [String] = [], textTokens: [String] = []
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
        title: isEn ? "Grant Full Disk Access to Unlock Safari Bookmarks & History" : "授予「完全磁盘访问权限」以解锁 Safari 书签与历史记录",
        subtitle: isEn ? "macOS protects ~/Library/Safari via TCC. Edge & Chrome work without extra permissions." : "macOS 对 ~/Library/Safari 启用了隐私保护（Edge 与 Chrome 已正常直连，无需额外权限）",
        icon: "lock.shield.fill", badge: "SAFARI TCC",
        openURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    ))
}

for it in filtered.prefix(maxRows) {
    let bLabel = browserSpecs[it.primaryBrowser]?.label ?? it.primaryBrowser
    let domain = fallbackTitle(it.url)
    let profilesTxt = it.profiles.prefix(2).joined(separator: " / ")
    let folderTxt = it.folders.first.map { "📁 \($0)" } ?? ""
    let visitsTxt = (it.hasHistory && it.visitCount > 1) ? (isEn ? "\(it.visitCount) visits" : "访问 \(it.visitCount) 次") : ""
    let timeTxt = formatRelativeTime(it.timestamp, isEn: isEn)
    let subParts = [profilesTxt, folderTxt, domain, visitsTxt, timeTxt].filter { !$0.isEmpty }
    let kindTag = (it.hasBookmark && it.hasHistory) ? "BM+HIS" : (it.hasBookmark ? "BM" : "HIS")
    let icon = it.pinned ? "pin.fill" : (it.hasBookmark ? "bookmark.fill" : (browserSpecs[it.primaryBrowser]?.icon ?? "globe"))

    rows.append(ViewItem(
        id: "bh-\(it.id)", title: (it.pinned ? "⭐ " : "") + String(it.title.prefix(88)),
        subtitle: subParts.joined(separator: " · "), icon: icon, badge: "\(bLabel) · \(kindTag)",
        copyText: it.url, openURL: openInSource ? nil : it.url,
        commandArgs: openInSource ? ["--open-in", it.primaryBrowser, it.url] : nil,
        actions: [
            ViewAction(id: "open-src-\(it.id)", label: isEn ? "Open in \(bLabel)" : "用 \(bLabel) 打开", style: "primary", commandArgs: ["--open-in", it.primaryBrowser, it.url]),
            ViewAction(id: "pin-\(it.id)", label: isEn ? (it.pinned ? "Unpin" : "Pin") : (it.pinned ? "取消置顶" : "星标置顶"), commandArgs: ["--toggle-pin", it.url])
        ]
    ))
}

if rows.isEmpty {
    rows.append(ViewItem(
        id: "empty-browser-hits",
        title: isEn ? "No matching bookmarks or history found" : "未匹配到符合条件的书签或历史记录",
        subtitle: isEn ? "Tip: use @edge, @chrome, @safari, @bm, @his, or #FolderName to filter" : "提示：可使用 @edge / @chrome / @safari / @bm / @his 或 #收藏夹名 组合筛选",
        icon: "magnifyingglass", badge: "EMPTY", commandArgs: ["--sync"]
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
    schemaVersion: 2, title: isEn ? "Browser Bookmarks & History Hub" : "三端浏览器书签与历史中枢",
    subtitle: subtitle, badge: bFilter.isEmpty ? "3 BROWSERS" : bFilter.uppercased(),
    metrics: [
        KeyValue(key: isEn ? "Bookmarks" : "书签总数", value: String(bmTotal)),
        KeyValue(key: isEn ? "History" : "近期历史", value: String(hisTotal)),
        KeyValue(key: "Edge / Chrome", value: "\(bCounts["edge"] ?? 0) / \(bCounts["chrome"] ?? 0)"),
        KeyValue(key: "Safari", value: safariDenied ? (isEn ? "Need FDA" : "待授磁盘权限") : String(bCounts["safari"] ?? 0))
    ],
    items: rows,
    effect: PostActionEffect(toast: toastMsg, reloadSearchIndex: true, statusSummary: statusSummary, statusBadge: String(items.count))
))
