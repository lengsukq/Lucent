import Foundation
import LumakeyCore

func testV083PluginV4CustomizationAndFusion() throws {
    try verifyUserOverridesAndLauncherScopedFusion()
    try verifyRichConfigValidationAndDemoManifest()
    try verifyContextMatcherAndStdinContextInjection()
    try verifyDataInspectorAutoRefreshAndMCPOverrides()
    try verifyPluginSubCommandsAndDefaultOffQuickButtons()
    print("[ok] v0.8.4 Plugin Deep Fusion + Sub-Command Global Search & Default-Off Quick Buttons")
}

private func verifyUserOverridesAndLauncherScopedFusion() throws {
    let tmp = try makeTempDir("v4-overrides")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let created = try PluginSystem.scaffoldPlugin(
        id: "bm-pro", name: "Bookmarks Pro", keywords: ["bm"],
        description: "Bookmark sync", mode: .view, hotkey: "⌥B",
        capabilities: [], resourceScopes: [], accepts: [.url, .text],
        in: pluginsRoot
    )
    check(created.effectiveKeywords == ["bm"] && created.effectiveHotKey == "⌥B", "initial manifest defaults")

    try PluginSystem.updatePluginOverrides(id: "bm-pro", in: pluginsRoot) {
        $0.customKeywords = ["nb", "mark"]
        $0.customHotKey = "⌥⇧N"
        $0.pinnedInOverlay = true
        $0.includeInGlobalSearch = false
        $0.priorityBoost = 150
    }
    PluginSystem.recordPluginUsage(id: "bm-pro", in: pluginsRoot)
    let customized = PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot)
    check(customized.effectiveKeywords == ["nb", "mark"], "customKeywords override applied")
    check(customized.effectiveHotKey == "⌥⇧N", "customHotKey override applied")
    check(customized.pinnedInOverlay && !customized.includeInGlobalSearch, "pin & global search flags persisted")
    check(customized.effectiveRankingBoost >= 390, "pinned + priorityBoost + usage count boosts score")

    try PluginSystem.updatePluginOverrides(id: "bm-pro", in: pluginsRoot) { $0.customHotKey = "" }
    check(PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot).effectiveHotKey == nil,
          "explicitly cleared customHotKey suppresses manifest default hotkey")

    let dataDir = PluginDataPaths.ensureDataDirectory(for: "bm-pro", pluginsRoot: pluginsRoot)!
    try Data("""
    {"items":[
      {"id":"1","title":"Swift Concurrency Guide","subtitle":"apple.com","url":"https://developer.apple.com","pinned":true,"priority":80},
      {"id":"2","title":"Rust Async Book","subtitle":"rust-lang.org","url":"https://rust-lang.org","pinned":false,"priority":20}
    ]}
    """.utf8).write(to: dataDir.appendingPathComponent("search-index.json"))

    let entries = PluginSearchIndex.loadEntries(for: [customized], in: pluginsRoot)
    check(entries.count == 2 && entries.allSatisfy { !$0.includeInGlobalSearch }, "entries inherit includeInGlobalSearch=false")

    // When includeInGlobalSearch == false, plugin & its items are hidden in .all, but visible in .plugins
    let globalHiddenHits = LauncherEngine.rankCandidates(query: "nb", filter: .all, apps: [], plugins: [customized], pluginSearchEntries: entries)
    check(!globalHiddenHits.contains(where: { if case .plugin(let p) = $0.kind { return p.id == "bm-pro" }; return false }),
          "includeInGlobalSearch=false hides plugin from .all filter")

    let pluginAliasHits = LauncherEngine.rankCandidates(query: "nb", filter: .plugins, apps: [], plugins: [customized], pluginSearchEntries: entries)
    check(pluginAliasHits.contains(where: { if case .plugin(let p) = $0.kind { return p.id == "bm-pro" }; return false }),
          "LauncherEngine matches custom keyword alias 'nb' in .plugins")

    let scopedEmpty = LauncherEngine.rankCandidates(query: "", filter: .plugins, apps: [], plugins: [customized], pluginSearchEntries: entries, scopedPluginID: "bm-pro")
    check(scopedEmpty.count == 3, "scopedPluginID empty query lists 2 indexed items + 1 live run row")
    if case .pluginItem(let topItem) = scopedEmpty.first?.kind {
        check(topItem.itemID == "1", "pinned item ranks first in scoped plugin list")
    } else {
        check(false, "expected top candidate in scoped mode to be pinned pluginItem")
    }

    try PluginSystem.resetPluginOverrides(id: "bm-pro", in: pluginsRoot)
    let afterReset = PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot)
    check(afterReset.effectiveKeywords == ["bm"] && afterReset.effectiveHotKey == "⌥B" && afterReset.overrides.launchCount == 1,
          "resetPluginOverrides restores manifest defaults while keeping usage count")
}

private func verifyRichConfigValidationAndDemoManifest() throws {
    let tmp = try makeTempDir("v4-config")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let badManifest = PluginManifest(
        schemaVersion: 3, id: "bad-num", name: "BadNum", version: "1.0.0", description: "x",
        mode: .view, keywords: ["bn"], entry: "run.sh",
        config: [PluginConfigField(key: "port", label: "Port", type: .number, minValue: 500, maxValue: 100)],
        capabilities: [], resourceScopes: [], accepts: ["invalidKind"],
        commands: [
            PluginCommandSpec(id: "dup", title: "A", subtitle: "a"),
            PluginCommandSpec(id: "dup", title: "", subtitle: "b")
        ]
    )
    let issues = PluginSystem.validate(manifest: badManifest, in: tmp)
    check(issues.contains(where: { $0.contains("minValue") })
            && issues.contains(where: { $0.contains("invalidKind") })
            && issues.contains(where: { $0.contains("重复的子功能") }),
          "validate rejects minValue > maxValue, unknown accepts, and duplicate command IDs")

    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let notionDir = repoRoot.appendingPathComponent("plugin-demo/notion-bookmarks", isDirectory: true)
    if FileManager.default.fileExists(atPath: notionDir.appendingPathComponent("plugin.json").path) {
        let notionDesc = PluginSystem.loadPlugin(at: notionDir, in: tmp, includeSecrets: false, allowKeychainInteraction: false)
        check(notionDesc.isValid, "plugin-demo/notion-bookmarks validates cleanly: \(notionDesc.validationIssues)")
        check(notionDesc.declaredContextKinds == [.url, .text], "notion-bookmarks declares url & text context hooks")
        check(notionDesc.declaredCommands.map(\.id) == ["add-clipboard", "refresh-bookmarks", "list-bookmarks"],
              "notion-bookmarks declares 3 Global Search sub-commands")
    }
}

private func verifyContextMatcherAndStdinContextInjection() throws {
    let tmp = try makeTempDir("v4-ctx")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let plugDir = pluginsRoot.appendingPathComponent("ctx-echo", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try "#!/bin/zsh\ncat\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "ctx-echo", name: "CtxEcho", version: "1.0.0", description: "ctx",
        mode: .script, keywords: ["ce"], entry: "run.sh",
        capabilities: [], resourceScopes: [], accepts: ["url", "image"]
    )).write(to: plugDir.appendingPathComponent("plugin.json"))

    let desc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot)
    let urlClip = ClipboardEntry(title: "Link", subtitle: "URL", textValue: "https://apple.com/macos", payloadKind: .text)
    let urlCtx = PluginContextMatcher.payloadFromClipboard(urlClip)
    check(urlCtx?.kind == .url && urlCtx?.url == "https://apple.com/macos", "payloadFromClipboard classifies https text as .url")
    check(PluginContextMatcher.matchingPlugins(in: [desc], for: urlCtx!).map(\.id) == ["ctx-echo"],
          "PluginContextMatcher matches url plugin in memory")

    let plainClip = ClipboardEntry(title: "Note", subtitle: "Text", textValue: "just some text", payloadKind: .text)
    let textCtx = PluginContextMatcher.payloadFromClipboard(plainClip)!
    check(textCtx.kind == .text && PluginContextMatcher.matchingPlugins(in: [desc], for: textCtx).isEmpty,
          "PluginContextMatcher skips non-matching text context")

    let out = try PluginSystem.runPluginSync(desc, query: urlCtx!.primaryQuery, contextPayload: urlCtx, in: pluginsRoot)
    check(out.execution.stdout.contains("\"source\":\"clipboard\"") && (out.execution.stdout.contains("https:\\/\\/apple.com\\/macos") || out.execution.stdout.contains("https://apple.com/macos")),
          "stdin.context JSON injected cleanly on context execution")
}

private func verifyDataInspectorAutoRefreshAndMCPOverrides() throws {
    let tmp = try makeTempDir("v4-data-mcp")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let plugDir = pluginsRoot.appendingPathComponent("sync-plug", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir, withIntermediateDirectories: true)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try "#!/bin/zsh\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    let manifest = PluginManifest(
        schemaVersion: 3, id: "sync-plug", name: "SyncPlug", version: "1.0.0", description: "s",
        mode: .script, keywords: ["sp"], entry: "run.sh",
        config: [PluginConfigField(key: "tok", label: "Token", type: .secret, required: true)],
        capabilities: [], resourceScopes: [], accepts: ["text"], refreshIntervalSeconds: 60,
        commands: [PluginCommandSpec(id: "force-sync", title: "立即同步缓存", subtitle: "强制刷新", keywords: ["spsync"], arguments: ["--sync"])]
    )
    try JSONEncoder().encode(manifest).write(to: plugDir.appendingPathComponent("plugin.json"))

    let missingSecretDesc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot, includeSecrets: false, allowKeychainInteraction: false)
    let status1 = PluginDataInspector.inspect(missingSecretDesc, in: pluginsRoot)
    check(status1.missingRequiredSecretKeys == ["tok"] && !status1.needsAutoRefresh,
          "missing required secret reported and suppresses auto-refresh")

    let configuredDesc: PluginDescriptor
    if (try? PluginSystem.updatePluginConfig(id: "sync-plug", values: ["tok": "SECRET_OK"], in: pluginsRoot)) != nil {
        configuredDesc = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot, allowKeychainInteraction: false)
    } else {
        configuredDesc = PluginDescriptor(
            id: "sync-plug", directoryURL: plugDir, manifest: manifest,
            validationIssues: [], isEnabled: true, userConfig: ["tok": "SECRET_OK"]
        )
    }
    defer { try? PluginSystem.removePlugin(id: "sync-plug", in: pluginsRoot) }

    let status2 = PluginDataInspector.inspect(configuredDesc, in: pluginsRoot)
    check(status2.missingRequiredSecretKeys.isEmpty && status2.needsAutoRefresh,
          "configured plugin without search-index.json triggers needsAutoRefresh")

    let dataDir = PluginDataPaths.ensureDataDirectory(for: "sync-plug", pluginsRoot: pluginsRoot)!
    try Data("cache".utf8).write(to: dataDir.appendingPathComponent("temp.bin"))
    try Data(#"{"items":[{"id":"1","title":"Cached"}]}"#.utf8).write(to: dataDir.appendingPathComponent("search-index.json"))
    let status3 = PluginDataInspector.inspect(configuredDesc, in: pluginsRoot)
    check(status3.searchIndexEntryCount == 1 && status3.cacheFileCount == 2 && !status3.needsAutoRefresh,
          "fresh search-index.json clears needsAutoRefresh")

    PluginDataInspector.clearPluginData(for: "sync-plug", in: pluginsRoot, preserveSearchIndex: true)
    let status4 = PluginDataInspector.inspect(configuredDesc, in: pluginsRoot)
    check(status4.searchIndexEntryCount == 1 && status4.cacheFileCount == 1,
          "clearPluginData(preserveSearchIndex:true) keeps search-index.json while removing cache files")

    let binDir = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
    let proc = Process()
    proc.executableURL = binDir.appendingPathComponent("lumakey-mcp")
    proc.arguments = ["--plugins-dir", pluginsRoot.path]
    let inPipe = Pipe(); let outPipe = Pipe()
    proc.standardInput = inPipe; proc.standardOutput = outPipe
    try proc.run()
    let reqs = [
        #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lumakey_update_plugin_overrides","arguments":{"id":"sync-plug","customKeywords":["sp2"],"quickButtonCommandIDs":["force-sync"]}}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lumakey_validate_plugin","arguments":{"id":"sync-plug"}}}"#
    ]
    try inPipe.fileHandleForWriting.write(contentsOf: Data((reqs.joined(separator: "\n") + "\n").utf8))
    try inPipe.fileHandleForWriting.close()
    proc.waitUntilExit()
    let mcpOut = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    check(mcpOut.contains("sp2") && mcpOut.contains("force-sync") && mcpOut.contains("declaredCommands"),
          "MCP lumakey_update_plugin_overrides & validate expose declaredCommands and quickButtonCommandIDs")
}

private func verifyPluginSubCommandsAndDefaultOffQuickButtons() throws {
    let tmp = try makeTempDir("v4-subcmds-qb")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let created = try PluginSystem.scaffoldPlugin(
        id: "cmd-suite",
        name: "效率子功能包",
        keywords: ["csuite"],
        description: "Sub-command suite",
        mode: .script,
        capabilities: [],
        resourceScopes: [],
        commands: [
            PluginCommandSpec(
                id: "save-clip",
                title: "收藏剪贴板链接",
                subtitle: "一键保存剪贴板 URL",
                keywords: ["bmadd", "收藏书签"],
                icon: "plus.circle.fill",
                arguments: ["--add-clipboard"],
                passQuery: false
            ),
            PluginCommandSpec(
                id: "hash-text",
                title: "计算文本摘要",
                subtitle: "对传入文本计算哈希",
                keywords: ["cliphash"],
                icon: "number",
                arguments: ["--digest"],
                passQuery: true
            )
        ],
        in: pluginsRoot
    )
    let starterInstalled = try PluginStarterGallery.install(templateID: "port-killer", in: pluginsRoot)
    let allPlugins = PluginSystem.listPlugins(in: pluginsRoot, includeBuiltin: true, includeSecrets: false)

    // 1. Hard requirement: ALL plugins (builtin + external + starter) have ZERO quick buttons by default!
    check(!created.pinnedInOverlay && created.overrides.quickButtonCommandIDs.isEmpty,
          "newly scaffolded plugin has zero quick buttons by default")
    check(!starterInstalled.pinnedInOverlay && starterInstalled.overrides.quickButtonCommandIDs.isEmpty,
          "newly installed starter plugin has zero quick buttons by default")
    check(PluginCommandRegistry.enabledQuickButtons(for: allPlugins).isEmpty,
          "enabledQuickButtons is strictly empty [] across all builtin & external plugins by default")

    // 2. Sub-commands ARE registered into Global Search (.all) and match keyword, Chinese title & Pinyin initials!
    let kwHits = LauncherEngine.rankCandidates(query: "bmadd", filter: .all, apps: [], plugins: allPlugins)
    check(kwHits.contains(where: {
        if case .pluginCommand(let c) = $0.kind { return c.id == "cmd-suite::save-clip" }
        return false
    }), "Global search matches sub-command keyword 'bmadd'")

    let pinyinHits = LauncherEngine.rankCandidates(query: "scjtb", filter: .all, apps: [], plugins: allPlugins)
    check(pinyinHits.contains(where: {
        if case .pluginCommand(let c) = $0.kind { return c.id == "cmd-suite::save-clip" }
        return false
    }), "Global search matches sub-command Chinese pinyin initials 'scjtb' for '收藏剪贴板链接'")

    let builtinHits = LauncherEngine.rankCandidates(query: "滚轮反转", filter: .all, apps: [], plugins: allPlugins)
    check(builtinHits.contains(where: {
        if case .pluginCommand(let c) = $0.kind { return c.id == "builtin-mos::mos-reverse" }
        return false
    }), "Global search matches builtin Mos sub-command '滚轮反转'")

    // Trailing query extraction + script execution with sub-command arguments
    let regHash = PluginCommandRegistry.registeredCommands(for: [created]).first { $0.command.id == "hash-text" }!
    let trailing = PluginCommandRegistry.extractTrailingQuery(rawQuery: "cliphash lumakey-2026", for: regHash)
    check(trailing == "lumakey-2026", "extractTrailingQuery strips matched command keyword")
    let execOut = try PluginSystem.runPluginSync(created, query: trailing, arguments: regHash.command.arguments, in: pluginsRoot)
    check(execOut.execution.stdout.contains("args=--digest") && execOut.execution.stdout.contains("lumakey-2026"),
          "sub-command execution passes declared CLI arguments and trailing query")

    // Builtin sub-command action toggles reverseWheelDirection cleanly on isolated config path
    let mosPaths = BuiltinPluginConfigPaths(
        mosURL: tmp.appendingPathComponent("mos.json"),
        lumaLinkURL: tmp.appendingPathComponent("lumalink.json"),
        monitorURL: tmp.appendingPathComponent("monitor.json")
    )
    let beforeRev = MosConfig.load(from: mosPaths.mosURL).reverseWheelDirection
    _ = PluginBuiltinRegistry.runBuiltin(id: "builtin-mos", arguments: ["--toggle-reverse"], configPaths: mosPaths)
    check(MosConfig.load(from: mosPaths.mosURL).reverseWheelDirection == !beforeRev,
          "builtin sub-command --toggle-reverse flips Mos reverseWheelDirection")

    // 3. Opt-in Quick Button toggle & per-command Global Search toggle
    try PluginSystem.setPluginCommandQuickButton(pluginID: "cmd-suite", commandID: "save-clip", enabled: true, in: pluginsRoot)
    let afterEnablePlugins = PluginSystem.listPlugins(in: pluginsRoot, includeBuiltin: true, includeSecrets: false)
    let qbs = PluginCommandRegistry.enabledQuickButtons(for: afterEnablePlugins)
    check(qbs.count == 1 && qbs.first?.id == "qb-cmd:cmd-suite::save-clip",
          "enabling quick button mounts ONLY the chosen sub-command")

    try PluginSystem.setPluginCommandSearchEnabled(pluginID: "cmd-suite", commandID: "save-clip", enabled: false, in: pluginsRoot)
    let afterHideSearch = PluginSystem.listPlugins(in: pluginsRoot, includeBuiltin: true, includeSecrets: false)
    let hiddenGlobal = LauncherEngine.rankCandidates(query: "bmadd", filter: .all, apps: [], plugins: afterHideSearch)
    check(!hiddenGlobal.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.id == "cmd-suite::save-clip" }; return false }),
          "disabling sub-command search hides it from .all Global Search")

    try PluginSystem.setPluginCommandQuickButton(pluginID: "cmd-suite", commandID: "save-clip", enabled: false, in: pluginsRoot)
    let afterDisableQB = PluginSystem.listPlugins(in: pluginsRoot, includeBuiltin: true, includeSecrets: false)
    check(PluginCommandRegistry.enabledQuickButtons(for: afterDisableQB).isEmpty,
          "disabling quick button returns enabledQuickButtons to empty []")
}
