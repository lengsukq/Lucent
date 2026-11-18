import Foundation
import LucentCore

func testV070Wave2Integration() throws {
    let appA = InstalledAppItem(name: "Safari", englishName: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
    let appB = InstalledAppItem(name: "Slack", englishName: "Slack", url: URL(fileURLWithPath: "/Applications/Slack.app"))
    let boosts: [String: Int] = [appA.id: 120, appB.id: 660]
    let rankedApps = LauncherEngine.rankCandidates(
        query: "s",
        filter: .all,
        apps: [appA, appB],
        plugins: [],
        usageBoosts: boosts
    )
    if case .app(let topApp) = rankedApps.first?.kind {
        check(topApp.id == appB.id, "Wave 2 LauncherEngine ranks pinned/high-usage app first")
    } else {
        check(false, "Wave 2 expected top candidate to be .app")
    }

    let tmpPlugDir = try makeTempDir("v070-w2-plug")
    defer { try? FileManager.default.removeItem(at: tmpPlugDir) }
    let enabledDesc = try PluginSystem.scaffoldPlugin(id: "w2-on", name: "W2 Enabled", keywords: ["w2plug"], description: "enabled", in: tmpPlugDir)
    _ = try PluginSystem.scaffoldPlugin(id: "w2-off", name: "W2 Disabled", keywords: ["w2plug"], description: "disabled", in: tmpPlugDir)
    try PluginSystem.setPluginEnabled(id: "w2-off", isEnabled: false, in: tmpPlugDir)
    let allPlugs = PluginSystem.listPlugins(in: tmpPlugDir, includeDisabled: true)
    let plugHits = LauncherEngine.rankCandidates(query: "w2plug", filter: .all, apps: [], plugins: allPlugs)
    check(plugHits.count == 1 && plugHits.first?.id == "plugin:\(enabledDesc.id)", "Wave 2 LauncherEngine filters out disabled plugins")

    // Verify plugin search-index.json loading & prefix-free LauncherEngine matching (title, pinyin, #tag, URL)
    let idxPayload = """
    {"version":1,"items":[{"id":"bm-1","title":"开源导航测试","subtitle":"github.com · #开发","url":"https://github.com/lengsukq/Lucent","copyText":"https://github.com/lengsukq/Lucent","icon":"bookmark.fill","badge":"开发","tags":["开发","Swift"],"pinned":true,"priority":10,"commandArgs":["--detail","bm-1"]}]}
    """
    let onDataDir = PluginDataPaths.ensureDataDirectory(for: "w2-on", pluginsRoot: tmpPlugDir)!
    let offDataDir = PluginDataPaths.ensureDataDirectory(for: "w2-off", pluginsRoot: tmpPlugDir)!
    try idxPayload.write(to: onDataDir.appendingPathComponent(PluginSearchIndex.defaultIndexFileName), atomically: true, encoding: .utf8)
    try idxPayload.write(to: offDataDir.appendingPathComponent(PluginSearchIndex.defaultIndexFileName), atomically: true, encoding: .utf8)
    let searchEntries = PluginSearchIndex.loadEntries(for: allPlugs, in: tmpPlugDir)
    check(searchEntries.count == 1 && searchEntries.first?.pluginID == "w2-on", "PluginSearchIndex loads enabled plugin search-index.json and skips disabled")
    let bmByPinyin = LauncherEngine.rankCandidates(query: "kydh", filter: .all, apps: [], plugins: allPlugs, pluginSearchEntries: searchEntries)
    let bmByTag = LauncherEngine.rankCandidates(query: "#swift", filter: .all, apps: [], plugins: allPlugs, pluginSearchEntries: searchEntries)
    let bmByURL = LauncherEngine.rankCandidates(query: "lengsukq", filter: .plugins, apps: [], plugins: allPlugs, pluginSearchEntries: searchEntries)
    check(bmByPinyin.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "bm-1" }; return false }), "LauncherEngine matches pluginItem by pinyin initials without prefix")
    check(bmByTag.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "bm-1" }; return false }), "LauncherEngine matches pluginItem by #tag")
    check(bmByURL.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "bm-1" }; return false }), "LauncherEngine matches pluginItem by URL in .plugins filter")

    let devHits = LauncherEngine.rankCandidates(query: "uuid", filter: .all, apps: [], plugins: [])
    check(devHits.contains(where: { if case .devTool = $0.kind { return true }; return false }), "Wave 2 LauncherEngine surfaces .devTool candidates")

    let snipHits = LauncherEngine.rankCandidates(query: ";clip", filter: .all, apps: [], plugins: [], clipboardText: "LET_X")
    let hasExpandedClip = snipHits.contains {
        if case .snippet(let m) = $0.kind { return m.expandedText.contains("LET_X") }
        return false
    }
    check(hasExpandedClip, "Wave 2 LauncherEngine surfaces .snippet candidates with expanded clipboard")

    check(UnitAndCommandEngine.matchCommands(query: "gif", volumes: []).contains(where: { $0.command == .recordGif }), "gif command wired")
    check(UnitAndCommandEngine.matchCommands(query: "录屏", volumes: []).contains(where: { $0.command == .recordGif }), "录屏 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "备份", volumes: []).contains(where: { $0.command == .openBackupSettings }), "备份 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "webdav", volumes: []).contains(where: { $0.command == .openBackupSettings }), "webdav command wired")
    check(UnitAndCommandEngine.matchCommands(query: "短语", volumes: []).contains(where: { $0.command == .openSnippetsSettings }), "短语 command wired")
    check(UnitAndCommandEngine.matchCommands(query: "snippets", volumes: []).contains(where: { $0.command == .openSnippetsSettings }), "snippets command wired")

    let tmpQR = try makeTempDir("v070-w2-qr")
    defer { try? FileManager.default.removeItem(at: tmpQR) }
    let directQR = DevToolkitEngine.generateQRCodePNG(for: "lucent://w2", pixelSize: 240, directory: tmpQR)
    check(directQR != nil && MediaClassifier.readImageDimensions(at: directQR!) == CGSize(width: 240, height: 240), "generateQRCodePNG custom size")

    let dirCache = WorkspaceDirectoryCache(maxEntries: 8)
    dirCache.store(entries: [], volumeSummary: nil, for: tmpQR, includeHidden: false, directoryMTime: nil)
    check(dirCache.lookup(for: tmpQR, includeHidden: false) != nil, "WorkspaceDirectoryCache stored")
    dirCache.invalidate(directoryURL: tmpQR)
    check(dirCache.lookup(for: tmpQR, includeHidden: false) == nil, "WorkspaceDirectoryCache invalidated")

    print("[ok] v0.7.0 Wave 2 Full-Stack Launcher + Commands + UsageBoost + DisabledPlugin Integration")
}
