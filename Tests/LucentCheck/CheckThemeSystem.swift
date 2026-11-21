import Foundation
import LucentCore

func testV085BuiltInThemes() throws {
    let all = AppThemeID.allCases
    check(all.count == 2, "exactly 2 built-in themes")
    check(all == [.pureFrost, .prismPulse], "built-in theme order is pureFrost then prismPulse")

    // Verify fresh brand names (no legacy placeholder terms)
    let forbidden = ["清简", "ios", "多彩", "青春"]
    for theme in all {
        let lowerTitle = theme.title.lowercased()
        let lowerBadge = theme.englishBadge.lowercased()
        for word in forbidden {
            check(!lowerTitle.contains(word) && !lowerBadge.contains(word),
                  "theme '\(theme.title)' avoids legacy placeholder word '\(word)'")
        }
    }
    check(AppThemeID.pureFrost.title == "晴霜浅色" && AppThemeID.pureFrost.englishBadge == "LIGHT FROST" && AppThemeID.pureFrost.symbolName == "sun.max.fill",
          "pureFrost display metadata")
    check(AppThemeID.prismPulse.title == "曜石暗色" && AppThemeID.prismPulse.englishBadge == "OBSIDIAN DARK" && AppThemeID.prismPulse.symbolName == "moon.stars.fill",
          "prismPulse display metadata")
    check(AppThemeID.pureFrost.rawValue == "pure-frost" && AppThemeID.prismPulse.rawValue == "prism-pulse",
          "AppThemeID rawValues remain backward-compatible")
    check(AppThemeID.pureFrost.next == .prismPulse && AppThemeID.prismPulse.next == .pureFrost,
          "AppThemeID.next cycles cleanly")

    let tmp = try makeTempDir("v085-themes")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cfgURL = tmp.appendingPathComponent("theme-config.json")

    // Missing file falls back to pureFrost + followSystemAppearance = false
    let defaultCfg = AppThemeConfig.load(from: cfgURL)
    check(defaultCfg.selectedTheme == .pureFrost && !defaultCfg.followSystemAppearance, "default theme is pureFrost with followSystemAppearance=false")

    // Persist prismPulse + followSystemAppearance = true and reload
    AppThemeConfig(selectedTheme: .prismPulse, followSystemAppearance: true).save(to: cfgURL)
    let reloadedCfg = AppThemeConfig.load(from: cfgURL)
    check(reloadedCfg.selectedTheme == .prismPulse && reloadedCfg.followSystemAppearance, "saved prismPulse + followSystemAppearance reloads cleanly")

    // Legacy JSON without followSystemAppearance decodes cleanly to false
    try Data(#"{"selectedTheme":"prism-pulse"}"#.utf8).write(to: cfgURL)
    let legacyCfg = AppThemeConfig.load(from: cfgURL)
    check(legacyCfg.selectedTheme == .prismPulse && !legacyCfg.followSystemAppearance, "legacy theme-config.json defaults followSystemAppearance to false")

    // Corrupted theme value gracefully falls back to pureFrost
    try Data(#"{"selectedTheme":"unknown-future-theme"}"#.utf8).write(to: cfgURL)
    check(AppThemeConfig.load(from: cfgURL).selectedTheme == .pureFrost, "unknown theme value falls back safely")

    // Global search command matching (new & legacy aliases)
    let cycleHits = UnitAndCommandEngine.matchCommands(query: "主题", volumes: [])
    check(cycleHits.contains(where: { $0.command == .cycleTheme }), "query '主题' matches .cycleTheme")
    for alias in ["晴霜", "浅色", "凝霜", "light", "frost"] {
        let hits = UnitAndCommandEngine.matchCommands(query: alias, volumes: [])
        check(hits.contains(where: { $0.command == .switchTheme(.pureFrost) }), "query '\(alias)' matches .switchTheme(.pureFrost)")
    }
    for alias in ["曜石", "暗色", "深色", "霓彩", "obsidian", "dark", "prism"] {
        let hits = UnitAndCommandEngine.matchCommands(query: alias, volumes: [])
        check(hits.contains(where: { $0.command == .switchTheme(.prismPulse) }), "query '\(alias)' matches .switchTheme(.prismPulse)")
    }

    // Verify BackupArchiveService captures and restores theme-config.json automatically
    let supportSrc = tmp.appendingPathComponent("SupportSrc", isDirectory: true)
    let supportDst = tmp.appendingPathComponent("SupportDst", isDirectory: true)
    try FileManager.default.createDirectory(at: supportSrc, withIntermediateDirectories: true)
    AppThemeConfig(selectedTheme: .prismPulse, followSystemAppearance: true).save(to: supportSrc.appendingPathComponent("theme-config.json"))
    let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: supportSrc)
    let report = try BackupArchiveService.restoreBackupData(archive, appSupportDirectory: supportDst)
    check(report.restoredConfigFileNames.contains("theme-config.json"), "backup archive includes theme-config.json")
    let restoredTheme = AppThemeConfig.load(from: supportDst.appendingPathComponent("theme-config.json"))
    check(restoredTheme.selectedTheme == .prismPulse && restoredTheme.followSystemAppearance,
          "restored theme-config.json preserves selectedTheme = prismPulse & followSystemAppearance = true")

    // Verify LauncherSelectionAnchor prevents background refreshes from snapping selection back to 0
    let c0 = LauncherCandidate(id: "app:wechat", score: 9000, kind: .calculator(expression: "1", resultText: "1", badgeLabel: "A"))
    let c1 = LauncherCandidate(id: "app:webstorm", score: 8500, kind: .calculator(expression: "2", resultText: "2", badgeLabel: "B"))
    let c2 = LauncherCandidate(id: "app:welcome", score: 8000, kind: .calculator(expression: "3", resultText: "3", badgeLabel: "C"))
    let initial = [c0, c1, c2]

    // 1) User has NOT moved selection -> stays at index 0 even if a higher-scoring hit arrives at top
    let topNew = LauncherCandidate(id: "file:top", score: 9500, kind: .calculator(expression: "0", resultText: "0", badgeLabel: "Top"))
    let unmoved = LauncherSelectionAnchor.resolve(
        candidates: [topNew] + initial, currentIndex: 0, userMovedSelection: false, anchoredID: nil
    )
    check(unmoved.index == 0 && unmoved.anchoredID == nil, "unmoved selection stays at index 0")

    // 2) User moved down to index 1 (app:webstorm); background index inserts 2 items above it -> follows app:webstorm to index 3!
    let f1 = LauncherCandidate(id: "file:1", score: 8800, kind: .calculator(expression: "f1", resultText: "f1", badgeLabel: "F"))
    let afterBgMerge = [topNew, c0, f1, c1, c2]
    let anchored = LauncherSelectionAnchor.resolve(
        candidates: afterBgMerge, currentIndex: 1, userMovedSelection: true, anchoredID: "app:webstorm"
    )
    check(anchored.index == 3 && anchored.anchoredID == "app:webstorm",
          "user-moved selection stays anchored on app:webstorm across background insertion (got \(anchored))")

    // 3) If anchored candidate disappears, clamps cleanly to currentIndex instead of jumping to 0
    let afterRemoval = [c0, c2]
    let clamped = LauncherSelectionAnchor.resolve(
        candidates: afterRemoval, currentIndex: 1, userMovedSelection: true, anchoredID: "app:webstorm"
    )
    check(clamped.index == 1 && clamped.anchoredID == "app:welcome",
          "removed anchor clamps to valid index instead of resetting to 0")

    // Verify Lucent.entitlements is valid plist & CodeSigningInspector has zero repo-script prompt leaks
    let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let entURL = repoRoot.appendingPathComponent("apps/macos/Lucent.entitlements")
    if FileManager.default.fileExists(atPath: entURL.path) {
        let entData = try Data(contentsOf: entURL)
        let entObj = try PropertyListSerialization.propertyList(from: entData, format: nil) as? [String: Any]
        check(entObj?["com.apple.security.automation.apple-events"] as? Bool == true,
              "Lucent.entitlements declares apple-events")
        check(entObj?["com.apple.security.device.audio-input"] as? Bool == true,
              "Lucent.entitlements declares audio-input")
    }
    let unSignedProbe = CodeSigningInspector.inspect(bundleURL: tmp)
    check(!unSignedProbe.explanation.contains("setup-local-signing") && !unSignedProbe.explanation.contains("/Volumes/"),
          "CodeSigningInspector user-facing copy contains zero developer repo path leaks")

    // Verify native first-party copywriting (no 'QQ', 'Mos ', 'Raycast', 'uTools' brand borrowings in visible titles/descriptions)
    let brandLeaks = ["QQ", "Mos ", "Raycast", "uTools"]
    for desc in PluginBuiltinRegistry.descriptors() {
        for brand in brandLeaks {
            check(!desc.manifest.name.contains(brand) && !desc.manifest.description.contains(brand),
                  "builtin plugin '\(desc.id)' avoids third-party brand '\(brand)' in manifest copy")
        }
        for cmd in desc.declaredCommands {
            for brand in brandLeaks {
                check(!cmd.title.contains(brand) && !cmd.subtitle.contains(brand),
                      "builtin command '\(cmd.id)' avoids third-party brand '\(brand)' in copy")
            }
        }
    }
    for hk in HotKeyActionID.allCases {
        for brand in brandLeaks + ["Everything"] {
            check(!hk.title.contains(brand), "HotKeyActionID '\(hk.rawValue)' title avoids '\(brand)'")
        }
    }
    for suggestion in UnitAndCommandEngine.matchCommands(query: "", volumes: []) + UnitAndCommandEngine.matchCommands(query: "鼠标", volumes: []) {
        for brand in brandLeaks + ["Everything"] {
            check(!suggestion.title.contains(brand) && suggestion.badgeLabel != "Mos",
                  "CommandSuggestion '\(suggestion.id)' avoids third-party brand '\(brand)'")
        }
    }

    print("[ok] v0.8.5 Built-in Dual Themes + LauncherSelectionAnchor + Distribution Signing + Clean Copy")
}
