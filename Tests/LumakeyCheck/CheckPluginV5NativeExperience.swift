import Carbon
import Foundation
import LumakeyCore

func testV088PluginNativeExperience() throws {
    try verifyCustomIconsAccentAndSliderValidation()
    try verifyBilingualManifestAndRuntimeLocaleTheme()
    try verifyDeepLinksRuntimeStatusAndCommandHotKeys()
    try verifySymmetricBuiltinAndExternalScoping()
    print("[ok] v0.8.8 Native External Plugin Experience (Icons/Bilingual/Slider/DeepLinks/CommandHotKeys/SymmetricScope)")
}

private func verifyCustomIconsAccentAndSliderValidation() throws {
    let tmp = try makeTempDir("v5-icons")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    let plugDir = pluginsRoot.appendingPathComponent("brand-plug", isDirectory: true)
    try FileManager.default.createDirectory(at: plugDir.appendingPathComponent("assets"), withIntermediateDirectories: true)

    let svgURL = plugDir.appendingPathComponent("assets/logo.svg")
    try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\"></svg>".utf8).write(to: svgURL)
    let scriptURL = plugDir.appendingPathComponent("run.sh")
    try "#!/bin/zsh\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let validManifest = PluginManifest(
        schemaVersion: 3,
        id: "brand-plug",
        name: "品牌书签",
        version: "1.0.0",
        description: "自定义包内图标与滑块",
        mode: .view,
        keywords: ["bp"],
        entry: "run.sh",
        icon: "assets/logo.svg",
        accentColor: "#14B8A6",
        categoryTag: "书签",
        config: [
            PluginConfigField(key: "ttl", label: "缓存秒数", type: .number, control: .slider, defaultValue: "60", minValue: 0, maxValue: 600, stepValue: 30)
        ],
        capabilities: [],
        resourceScopes: []
    )
    try JSONEncoder().encode(validManifest).write(to: plugDir.appendingPathComponent("plugin.json"))

    let loaded = PluginSystem.loadPlugin(at: plugDir, in: pluginsRoot, includeSecrets: false)
    check(loaded.isValid, "plugin with valid relative bundle icon & slider validates cleanly: \(loaded.validationIssues)")
    check(loaded.customIconURL?.standardizedFileURL == svgURL.standardizedFileURL, "customIconURL resolves to bundle SVG")
    check(loaded.displayCategoryBadge == "书签", "displayCategoryBadge uses natural categoryTag instead of raw VIEW")

    // Reject escaping icon path & invalid slider bounds
    let escapeManifest = PluginManifest(
        schemaVersion: 3, id: "bad-icon", name: "Bad", version: "1.0.0", description: "x",
        mode: .view, keywords: ["bi"], entry: "run.sh", icon: "../outside.png",
        config: [PluginConfigField(key: "badSlider", label: "S", type: .text, control: .slider)],
        capabilities: [], resourceScopes: []
    )
    let badIssues = PluginSystem.validate(manifest: escapeManifest, in: plugDir)
    check(badIssues.contains(where: { $0.contains("icon") }) && badIssues.contains(where: { $0.contains("滑块") }),
          "validate rejects escaping icon path and non-number/unbounded slider")

    // Item icon inside PluginData resolves cleanly while path traversal is rejected
    let dataDir = PluginDataPaths.ensureDataDirectory(for: "brand-plug", pluginsRoot: pluginsRoot)!
    let favURL = dataDir.appendingPathComponent("fav.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: favURL)
    check(PluginIconResolver.resolveItemIconURL(rawIcon: "fav.png", bundleDirectory: plugDir, dataDirectory: dataDir)?.standardizedFileURL == favURL.standardizedFileURL,
          "item icon resolves inside PluginData directory")
    check(PluginIconResolver.resolveItemIconURL(rawIcon: "../secret.png", bundleDirectory: plugDir, dataDirectory: dataDir) == nil,
          "item icon rejects .. path traversal")
}

private func verifyBilingualManifestAndRuntimeLocaleTheme() throws {
    let prevLang = L10n.current
    defer { L10n.setCurrent(prevLang) }

    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let notionDir = repoRoot.appendingPathComponent("plugin-demo/notion-bookmarks", isDirectory: true)
    let tmp = try makeTempDir("v5-bilingual")
    defer { try? FileManager.default.removeItem(at: tmp) }

    if FileManager.default.fileExists(atPath: notionDir.appendingPathComponent("plugin.json").path) {
        L10n.setCurrent(.zhHans)
        let zhDesc = PluginSystem.loadPlugin(at: notionDir, in: tmp, includeSecrets: false)
        check(zhDesc.isValid && zhDesc.customIconURL != nil, "upgraded notion-bookmarks has valid custom icon.svg")
        check(zhDesc.displayName == "Notion 书签收藏" && zhDesc.displayCategoryBadge == "书签", "zh-Hans localized name & category")

        L10n.setCurrent(.english)
        let enDesc = PluginSystem.loadPlugin(at: notionDir, in: tmp, includeSecrets: false)
        check(enDesc.displayName == "Notion Bookmarks" && enDesc.displayCategoryBadge == "Bookmarks", "English locale switches manifest name & categoryTag")
        let addCmd = enDesc.declaredCommands.first(where: { $0.id == "add-clipboard" })!
        check(enDesc.manifest.localizedCommandTitle(addCmd) == "Save Clipboard URL to Notion", "English locale switches command title")
        let ttlField = enDesc.manifest.config!.first(where: { $0.key == "cacheTtlSeconds" })!
        check(ttlField.control == .slider && enDesc.manifest.localizedFieldLabel(ttlField) == "Local Cache TTL (seconds)",
              "English locale switches config label & preserves slider control")

        // Search matches both Chinese and English localized titles regardless of active UI language
        let enCmdHits = LauncherEngine.rankCandidates(query: "Save Clipboard", filter: .all, apps: [], plugins: [enDesc])
        check(enCmdHits.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.command.id == "add-clipboard" }; return false }),
              "LauncherEngine matches English localized sub-command title")
    }

    // Verify stdin JSON and env vars carry locale and theme
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    let echoDir = pluginsRoot.appendingPathComponent("env-echo", isDirectory: true)
    try FileManager.default.createDirectory(at: echoDir, withIntermediateDirectories: true)
    let scriptURL = echoDir.appendingPathComponent("run.sh")
    try """
    #!/bin/zsh
    STDIN_JSON="$(cat)"
    echo "ENV_LOCALE=${LUMAKEY_LOCALE} ENV_THEME=${LUMAKEY_THEME} STDIN=${STDIN_JSON}"
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "env-echo", name: "EnvEcho", version: "1.0.0", description: "e",
        mode: .script, keywords: ["ee"], entry: "run.sh", capabilities: [], resourceScopes: []
    )).write(to: echoDir.appendingPathComponent("plugin.json"))

    L10n.setCurrent(.english)
    let echoDesc = PluginSystem.loadPlugin(at: echoDir, in: pluginsRoot)
    let out = try PluginSystem.runPluginSync(echoDesc, query: "hi", in: pluginsRoot)
    check(out.execution.stdout.contains("ENV_LOCALE=en") && out.execution.stdout.contains("\"locale\":\"en\"") && out.execution.stdout.contains("\"theme\":"),
          "subprocess receives LUMAKEY_LOCALE, LUMAKEY_THEME, stdin.locale & stdin.theme")
}

private func verifyDeepLinksRuntimeStatusAndCommandHotKeys() throws {
    let tmp = try makeTempDir("v5-deeplink-status")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    let mdFile = tmp.appendingPathComponent("report.md")
    try "# Report\n\n| Col | Val |\n| --- | --- |\n| A | 1 |".write(to: mdFile, atomically: true, encoding: .utf8)
    let imgFile = tmp.appendingPathComponent("pin.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imgFile)

    let encodedMD = mdFile.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    let encodedImg = imgFile.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!

    check(PluginDeepLinkParser.parse(URL(string: "lumakey://reader?path=\(encodedMD)")!) == .documentReader(mdFile.standardizedFileURL),
          "lumakey://reader?path= parses into .documentReader")
    check(PluginDeepLinkParser.parse(URL(string: "lumakey://image?path=\(encodedImg)&pin=1")!) == .imageViewer(imgFile.standardizedFileURL, pinOnTop: true),
          "lumakey://image?path=&pin=1 parses into pinned .imageViewer")
    check(PluginDeepLinkParser.parse(URL(string: "lumakey://pin?path=\(encodedImg)")!) == .pinImage(imgFile.standardizedFileURL),
          "lumakey://pin?path= parses into .pinImage")
    if case .documentReader(let inlineDoc)? = PluginDeepLinkParser.parse(URL(string: "lumakey://reader?title=QuickNote&markdown=%23%20Hello")!) {
        check(FileManager.default.fileExists(atPath: inlineDoc.path), "inline markdown lumakey://reader materializes temp markdown file")
    } else {
        check(false, "expected inline markdown lumakey://reader to succeed")
    }

    // Verify effect.statusSummary auto-persists to status.json and updates effectiveStatusSummary
    let statusDir = pluginsRoot.appendingPathComponent("status-plug", isDirectory: true)
    try FileManager.default.createDirectory(at: statusDir, withIntermediateDirectories: true)
    let scriptURL = statusDir.appendingPathComponent("run.sh")
    try """
    #!/bin/zsh
    cat <<'EOF'
    {"title":"Notion 书签","effect":{"statusSummary":"已同步 42 条书签 · 刚刚","statusBadge":"已同步"}}
    EOF
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    try JSONEncoder().encode(PluginManifest(
        schemaVersion: 3, id: "status-plug", name: "StatusPlug", version: "1.0.0", description: "默认简介",
        mode: .view, keywords: ["st"], entry: "run.sh", capabilities: [], resourceScopes: [],
        commands: [PluginCommandSpec(id: "quick-save", title: "快速收藏", subtitle: "s", keywords: ["qs"], hotkey: "⌥⇧S")]
    )).write(to: statusDir.appendingPathComponent("plugin.json"))

    let beforeRun = PluginSystem.loadPlugin(at: statusDir, in: pluginsRoot)
    check(beforeRun.effectiveStatusSummary == "默认简介", "before run uses manifest description")
    check(beforeRun.effectiveCommandHotKey(for: "quick-save") == "⌥⇧S", "manifest command default hotkey")

    _ = try PluginSystem.runPluginSync(beforeRun, query: "", in: pluginsRoot)
    let afterRun = PluginSystem.loadPlugin(at: statusDir, in: pluginsRoot)
    check(afterRun.effectiveStatusSummary == "已同步 42 条书签 · 刚刚" && afterRun.displayCategoryBadge == "已同步",
          "effect.statusSummary & statusBadge persist to status.json for zero-subprocess display")

    // Command hotkey user override + conflict detection integration
    try PluginSystem.setPluginCommandHotKey(pluginID: "status-plug", commandID: "quick-save", hotKey: "⌥A", in: pluginsRoot)
    let rebound = PluginSystem.loadPlugin(at: statusDir, in: pluginsRoot)
    check(rebound.effectiveCommandHotKey(for: "quick-save") == "⌥A", "commandHotKeys overrides command hotkey")

    let cmdChord = HotKeyChord.parse("⌥A")!
    let report = HotKeyConflictDetector.analyzeChord(
        cmdChord,
        for: .screenshotPin,
        config: .defaultConfig,
        pluginHotKeys: [ExternalPluginHotKey(pluginID: "status-plug", commandID: "quick-save", pluginName: "StatusPlug · 快速收藏", chord: cmdChord)],
        probeExternalProcesses: false
    )
    check(report.hasConflict && report.issues.contains(where: { $0.sourceTitle.contains("快速收藏") }),
          "HotKeyConflictDetector catches conflict against sub-command hotkey")

    try PluginSystem.setPluginCommandHotKey(pluginID: "status-plug", commandID: "quick-save", hotKey: "", in: pluginsRoot)
    check(PluginSystem.loadPlugin(at: statusDir, in: pluginsRoot).effectiveCommandHotKey(for: "quick-save") == nil,
          "empty commandHotKey clears manifest default command hotkey")
}

private func verifySymmetricBuiltinAndExternalScoping() throws {
    let builtins = PluginBuiltinRegistry.descriptors()
    let scopedMos = LauncherEngine.rankCandidates(
        query: "",
        filter: .plugins,
        apps: [],
        plugins: builtins,
        scopedPluginID: BuiltinPluginID.mos.rawValue
    )
    check(scopedMos.count == 4, "scoped builtin-mos lists 3 sub-commands + 1 live status item (got \(scopedMos.count))")
    if case .pluginCommand(let topCmd) = scopedMos.first?.kind {
        check(topCmd.pluginID == BuiltinPluginID.mos.rawValue, "builtin sub-commands rank at top of scoped builtin list")
    } else {
        check(false, "expected top candidate of scoped builtin-mos to be .pluginCommand")
    }
}
