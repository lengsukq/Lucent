import Foundation
import Testing
@testable import LucentCore

@Suite("Quick Scripts Library, Two-Way Sync, SVG Icons, Custom Shebang & Backup")
struct LucentScriptLibraryTests {
    @Test("SVG icon safety validation, two-way directory sync & magic comment parsing")
    func svgValidationAndTwoWayDirectorySync() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-scripts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let store = ScriptLibraryStore(
            scriptsDirectory: ScriptLibraryStore.defaultScriptsDirectory(appSupportDirectory: tmp),
            indexFileURL: ScriptLibraryStore.defaultIndexFileURL(appSupportDirectory: tmp)
        )

        // First access seeds starter templates cleanly
        let starters = store.allScripts()
        #expect(starters.count == 3)
        #expect(starters.contains(where: { $0.id == "pretty-clipboard-json" && $0.customIconURL(in: store.scriptsDirectory) != nil }))

        // Watcher with watchDataRoot: false must NOT create .lucent-plugin-data inside Scripts/
        let watcher = PluginDirectoryWatcher(directoryURL: store.scriptsDirectory, debounceInterval: 0.2, watchDataRoot: false) {}
        watcher?.stop()
        #expect(!FileManager.default.fileExists(atPath: store.scriptsDirectory.appendingPathComponent(".lucent-plugin-data").path))

        // Regression test: UI/MCP metadata edits on a script containing # @lucent.* comments must NOT be reverted on syncWithDisk()
        var jsonStarter = try #require(starters.first(where: { $0.id == "pretty-clipboard-json" }))
        let originalCode = store.readCode(for: jsonStarter)
        #expect(originalCode.contains("# @lucent.title: 美化剪贴板 JSON"))
        jsonStarter.title = "JSON 极速缩进美化"
        jsonStarter.outputMode = .inlinePreview
        jsonStarter.keywords = ["!json2", "fmtjson"]
        _ = try store.upsert(jsonStarter, code: originalCode, notifyInProcess: false)
        let afterResync = store.syncWithDisk()
        let updatedJsonStarter = try #require(afterResync.first(where: { $0.id == "pretty-clipboard-json" }))
        #expect(updatedJsonStarter.title == "JSON 极速缩进美化")
        #expect(updatedJsonStarter.outputMode == .inlinePreview)
        #expect(updatedJsonStarter.keywords == ["!json2", "fmtjson"])
        #expect(updatedJsonStarter.customIconURL(in: store.scriptsDirectory) != nil)
        #expect(store.readCode(for: updatedJsonStarter).contains("# @lucent.title: JSON 极速缩进美化"))

        // Genuine external file edit on disk MUST still sync back into the store
        let externallyEdited = store.readCode(for: updatedJsonStarter)
            .replacingOccurrences(of: "# @lucent.title: JSON 极速缩进美化", with: "# @lucent.title: 外部编辑器改名 JSON")
        try Data(externallyEdited.utf8).write(to: store.scriptURL(for: updatedJsonStarter), options: .atomic)
        let afterExternalEdit = store.syncWithDisk()
        #expect(afterExternalEdit.first(where: { $0.id == "pretty-clipboard-json" })?.title == "外部编辑器改名 JSON")

        // Unsafe SVG payloads must be rejected
        #expect(throws: LucentError.self) {
            _ = try ScriptHeaderParser.validateSafeSVG("<svg><script>alert(1)</script></svg>")
        }
        #expect(throws: LucentError.self) {
            _ = try ScriptHeaderParser.validateSafeSVG("<svg onload=\"evil()\"></svg>")
        }

        // Upsert a custom Shebang script with a bespoke SVG icon, bilingual titles & huge clipboard E2BIG guard
        let validSVG = """
        <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
          <rect x="4" y="4" width="56" height="56" rx="14" fill="#0EA5E9"/>
          <circle cx="32" cy="32" r="14" fill="#FFFFFF"/>
        </svg>
        """
        let customShebangCode = """
        #!/usr/bin/env python3
        import os
        q = os.environ.get("LUCENT_QUERY", "")
        clip = os.environ.get("LUCENT_CLIPBOARD", "")
        print(f"SHEBANG_OK:{q}:{len(clip.encode('utf-8'))}")
        """
        let draft = ScriptRecord(
            id: "shebang-echo",
            title: "自定义解释器回显",
            englishTitle: "Custom Shebang Echo",
            subtitle: "测试任意 #! Shebang 运行时与剪贴板注入",
            keywords: ["!sbecho"],
            category: "开发",
            fileName: "shebang-echo.xpy",
            runtime: .customShebang,
            outputMode: .copyToClipboard,
            passClipboard: true
        )
        let saved = try store.upsert(draft, code: customShebangCode, iconSvg: validSVG, notifyInProcess: false)
        #expect(saved.icon == "icons/shebang-echo.svg")
        #expect(saved.customIconURL(in: store.scriptsDirectory) != nil)
        #expect(store.readCustomIconSVG(for: saved)?.contains("#0EA5E9") == true)

        // 120 KB multi-byte UTF-8 clipboard must be safely truncated on scalar boundary without E2BIG failure
        let hugeClipboard = String(repeating: "流光🚀", count: 16_000)
        let runOutcome = try ScriptRunner.runSync(saved, query: "hello", clipboardText: hugeClipboard, store: store)
        #expect(runOutcome.exitCode == 0)
        let outLine = runOutcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(outLine.hasPrefix("SHEBANG_OK:hello:"))
        let cappedBytes = Int(outLine.split(separator: ":").last ?? "0") ?? 0
        #expect(cappedBytes > 40_000 && cappedBytes <= ScriptRunner.maxEnvPayloadUTF8Bytes)

        // AppleScript pure computation execution check
        let osaDraft = ScriptRecord(
            id: "osa-math",
            title: "AppleScript 算术测试",
            fileName: "osa-math.applescript",
            runtime: .appleScript,
            outputMode: .toast
        )
        let osaSaved = try store.upsert(osaDraft, code: "return (21 * 2) as text\n", notifyInProcess: false)
        let osaRes = try ScriptRunner.runSync(osaSaved, store: store)
        #expect(osaRes.exitCode == 0)
        #expect(osaRes.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")

        // Drop a new raw script directly into Scripts/ and verify two-way auto-discovery
        let droppedURL = store.scriptsDirectory.appendingPathComponent("drop-tool.sh")
        let droppedCode = """
        #!/bin/zsh
        # @lucent.title: 目录投递脚本
        # @lucent.title.en: Dropped Folder Script
        # @lucent.keywords: !drop, droptool
        # @lucent.output: toast
        # @lucent.color: orange
        echo "dropped"
        """
        try Data(droppedCode.utf8).write(to: droppedURL, options: .atomic)
        let synced = store.syncWithDisk()
        let droppedRec = synced.first(where: { $0.fileName == "drop-tool.sh" })
        #expect(droppedRec?.title == "目录投递脚本")
        #expect(droppedRec?.englishTitle == "Dropped Folder Script")
        #expect(droppedRec?.outputMode == .toast)
        #expect(droppedRec?.accentColor == "orange")

        // Removing the file on disk removes it on next sync
        try FileManager.default.removeItem(at: droppedURL)
        let afterDelete = store.syncWithDisk()
        #expect(!afterDelete.contains(where: { $0.fileName == "drop-tool.sh" }))
    }

    @Test("LauncherEngine script ranking, Plugins tab tiering, HomeLaunchTarget.script, MCP prompt & Backup v2 round-trip")
    func launcherHomeBackupAndMCPPromptIntegration() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-script-bk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let store = ScriptLibraryStore(
            scriptsDirectory: ScriptLibraryStore.defaultScriptsDirectory(appSupportDirectory: tmp),
            indexFileURL: ScriptLibraryStore.defaultIndexFileURL(appSupportDirectory: tmp)
        )
        var pool = store.allScripts(includeDisabled: false)

        // LauncherEngine keyword + trailing query matching
        let kwCandidates = LauncherEngine.rankCandidates(
            query: "!json {\"a\":1}",
            filter: .all,
            apps: [],
            plugins: [],
            scripts: pool
        )
        let firstScriptHit = kwCandidates.compactMap { cand -> ScriptMatch? in
            if case .script(let m) = cand.kind { return m }
            return nil
        }.first
        #expect(firstScriptHit?.script.id == "pretty-clipboard-json")
        #expect(firstScriptHit?.trailingQuery == "{\"a\":1}")

        // Script with includeInGlobalSearch = false is hidden from .all but visible in .plugins tab
        pool[0].includeInGlobalSearch = false
        let hiddenInAll = LauncherEngine.rankCandidates(query: "!json", filter: .all, apps: [], plugins: [], scripts: pool)
        #expect(!hiddenInAll.contains(where: { $0.id == "script:pretty-clipboard-json" }))
        let visibleInPluginsEmpty = LauncherEngine.rankCandidates(query: "", filter: .plugins, apps: [], plugins: [], scripts: pool)
        #expect(visibleInPluginsEmpty.contains(where: { $0.id == "script:pretty-clipboard-json" }))

        // HomeLaunchTarget.script serialization & validation
        let homeItem = HomeLaunchItem(id: "tile-json", target: .script(scriptID: "pretty-clipboard-json"))
        #expect(HomeLaunchSecurity.validateItem(homeItem) == nil)
        let badScriptItem = HomeLaunchItem(id: "tile-bad", target: .script(scriptID: "../escape"))
        #expect(HomeLaunchSecurity.validateItem(badScriptItem) != nil)

        // MCPAgentPromptBuilder bilingual prompt includes scripts-v1 & iconSvg guidance
        let zhPrompt = MCPAgentPromptBuilder.buildAgentPrompt(executablePath: "/Applications/Lucent.app/Contents/MacOS/lucent-mcp", language: .zhHans)
        let enPrompt = MCPAgentPromptBuilder.buildAgentPrompt(executablePath: "/Applications/Lucent.app/Contents/MacOS/lucent-mcp", language: .english)
        #expect(zhPrompt.contains("lucent://specs/scripts-v1") && zhPrompt.contains("iconSvg"))
        #expect(enPrompt.contains("lucent://specs/scripts-v1") && enPrompt.contains("iconSvg"))

        // Backup v2 archive preserves scripts-library.json, Scripts/*.py, and Scripts/icons/*.svg
        let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let restoredDir = tmp.appendingPathComponent("RestoredAppSupport", isDirectory: true)
        let report = try BackupArchiveService.restoreBackupData(archive, appSupportDirectory: restoredDir)
        #expect(report.restoredConfigFileNames.contains(ScriptLibraryStore.indexFileName))

        let restoredStore = ScriptLibraryStore(
            scriptsDirectory: ScriptLibraryStore.defaultScriptsDirectory(appSupportDirectory: restoredDir),
            indexFileURL: ScriptLibraryStore.defaultIndexFileURL(appSupportDirectory: restoredDir)
        )
        let restoredList = restoredStore.allScripts()
        #expect(restoredList.count == 3)
        let restoredJsonScript = restoredList.first(where: { $0.id == "pretty-clipboard-json" })
        #expect(restoredJsonScript?.customIconURL(in: restoredStore.scriptsDirectory) != nil)
    }
}
