import Foundation
import LumakeyCore

func testV086BilingualSystem() throws {
    let previous = L10n.current
    defer { L10n.setCurrent(previous) }

    // 1. System language auto-detection rules
    check(
        AppLanguageConfig.detectSystemLanguage(preferredLanguages: ["zh-Hans-CN", "en-US"], fallbackLocaleID: "en_US") == .zhHans,
        "zh-Hans-CN primary language resolves to .zhHans"
    )
    check(
        AppLanguageConfig.detectSystemLanguage(preferredLanguages: ["zh-Hant-HK", "en-US"], fallbackLocaleID: "en_US") == .zhHans,
        "zh-Hant-HK primary language resolves to .zhHans"
    )
    check(
        AppLanguageConfig.detectSystemLanguage(preferredLanguages: ["en-US", "zh-Hans-CN"], fallbackLocaleID: "zh_CN") == .english,
        "en-US primary language resolves to .english even if Chinese is secondary"
    )
    check(
        AppLanguageConfig.detectSystemLanguage(preferredLanguages: ["ja-JP"], fallbackLocaleID: "zh_CN") == .english,
        "non-Chinese primary language falls back to .english"
    )
    check(
        AppLanguageConfig.detectSystemLanguage(preferredLanguages: [], fallbackLocaleID: "zh_CN") == .zhHans,
        "empty preferredLanguages uses fallbackLocaleID"
    )

    // 2. First-launch bootstrap vs subsequent user override persistence
    let tmp = try makeTempDir("v086-lang")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cfgURL = tmp.appendingPathComponent("language-config.json")
    check(!AppLanguageConfig.hasSavedPreference(at: cfgURL), "fresh directory has no saved language-config.json")

    let firstOpenEN = AppLanguageConfig.loadOrBootstrap(
        from: cfgURL,
        preferredLanguages: ["en-US", "zh-Hans"],
        fallbackLocaleID: "en_US",
        persistBootstrap: true
    )
    check(firstOpenEN.selectedLanguage == .english, "first launch on English macOS selects .english")
    check(AppLanguageConfig.hasSavedPreference(at: cfgURL), "first launch persists language-config.json")

    // User switches to Chinese in Settings -> subsequent launch on English macOS keeps Chinese
    AppLanguageConfig(selectedLanguage: .zhHans).save(to: cfgURL)
    let secondOpen = AppLanguageConfig.loadOrBootstrap(
        from: cfgURL,
        preferredLanguages: ["en-US"],
        fallbackLocaleID: "en_US",
        persistBootstrap: true
    )
    check(secondOpen.selectedLanguage == .zhHans, "subsequent launch respects user-saved .zhHans over system English")

    // Also verify first launch on Chinese macOS selects .zhHans
    let cfgURL2 = tmp.appendingPathComponent("language-config-zh.json")
    let firstOpenZH = AppLanguageConfig.loadOrBootstrap(
        from: cfgURL2,
        preferredLanguages: ["zh-Hans-CN"],
        fallbackLocaleID: "zh_CN",
        persistBootstrap: true
    )
    check(firstOpenZH.selectedLanguage == .zhHans, "first launch on Chinese macOS selects .zhHans")

    // 3. Live runtime switching across Core models, Localizable.strings, and dynamic patterns
    L10n.setCurrent(.english)
    check(L10n.isEnglish, "L10n.isEnglish true after switching to .english")
    check(OmniFilter.all.title == "All" && OmniFilter.clipboard.title == "Clipboard", "OmniFilter titles localize to English")
    check(
        HotKeyActionID.launcher.title != "全局统一快捷中枢" && HotKeyActionID.launcher.title.unicodeScalars.allSatisfy(\.isASCII),
        "HotKeyActionID.launcher localizes to English (got '\(HotKeyActionID.launcher.title)')"
    )
    check(AppThemeID.pureFrost.localizedTitle.contains("Pure Frost"), "AppThemeID.localizedTitle returns English in .english mode")
    check(AppThemeID.pureFrost.title == "凝霜留白", "AppThemeID.title canonical Chinese stays intact")
    check(ClipboardCategory.pinned.localizedTitle == "Pinned", "ClipboardCategory.localizedTitle returns English")
    check(ClipboardPayloadKind.colorHex("#3478F6").badgeTitle == "Color", "ClipboardPayloadKind.badgeTitle returns English")

    let enBuiltins = PluginBuiltinRegistry.descriptors()
    check(
        enBuiltins.contains(where: { $0.id == BuiltinPluginID.mos.rawValue && $0.manifest.name.contains("Smooth Mouse") }),
        "builtin screenshot plugin localizes manifest name in English"
    )

    let enLangCmds = UnitAndCommandEngine.matchCommands(query: "chinese", volumes: [])
    check(
        enLangCmds.contains(where: { $0.command == .switchLanguage(.zhHans) }),
        "Global search 'chinese' matches .switchLanguage(.zhHans)"
    )
    let cycleLangCmds = UnitAndCommandEngine.matchCommands(query: "language", volumes: [])
    check(
        cycleLangCmds.contains(where: { $0.command == .cycleLanguage }),
        "Global search 'language' matches .cycleLanguage"
    )

    // Verify Localizable.strings table lookup + dynamic pattern translation
    let translatedStatic = L10n.translate("通用与内存", for: .english)
    check(translatedStatic == "General & Memory", "Localizable.strings translates '通用与内存' -> 'General & Memory' (got '\(translatedStatic)')")
    let translatedDynamic = L10n.translate("已复制路径：README.md", for: .english)
    check(translatedDynamic == "Copied path: README.md", "LocalizationPatterns translates dynamic prefix string (got '\(translatedDynamic)')")

    L10n.setCurrent(.zhHans)
    check(!L10n.isEnglish, "L10n.isEnglish false after switching back to .zhHans")
    check(OmniFilter.all.title == "全部", "OmniFilter switches back to Chinese immediately")
    let zhLangCmds = UnitAndCommandEngine.matchCommands(query: "英文", volumes: [])
    check(
        zhLangCmds.contains(where: { $0.command == .switchLanguage(.english) }),
        "Global search '英文' matches .switchLanguage(.english)"
    )

    // 4. BackupArchiveService round-trip preserves language-config.json
    let srcSupport = tmp.appendingPathComponent("SupportSrc", isDirectory: true)
    let dstSupport = tmp.appendingPathComponent("SupportDst", isDirectory: true)
    try FileManager.default.createDirectory(at: srcSupport, withIntermediateDirectories: true)
    AppLanguageConfig(selectedLanguage: .english).save(to: srcSupport.appendingPathComponent("language-config.json"))

    let archiveData = try BackupArchiveService.exportBackupData(appSupportDirectory: srcSupport, appVersion: "0.8.6")
    let summary = try BackupArchiveService.inspectBackupData(archiveData)
    check(summary.configFileNames.contains("language-config.json"), "BackupArchiveService includes language-config.json")

    let report = try BackupArchiveService.restoreBackupData(archiveData, appSupportDirectory: dstSupport)
    check(report.restoredConfigFileNames.contains("language-config.json"), "BackupArchiveService restores language-config.json")
    let restoredLang = AppLanguageConfig.loadOrBootstrap(
        from: dstSupport.appendingPathComponent("language-config.json"),
        preferredLanguages: ["zh-Hans-CN"],
        persistBootstrap: false
    )
    check(restoredLang.selectedLanguage == .english, "Restored language-config.json preserves .english")

    print("[ok] v0.8.6 Bilingual System (First-Launch Locale Auto-Detect + Live Switch + Strings Table + Backup)")
}
