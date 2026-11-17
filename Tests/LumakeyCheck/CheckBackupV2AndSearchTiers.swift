import Foundation
import LumakeyCore

func testV092TieredGlobalSearchAndBackupV2() throws {
    try verifyTieredPluginGlobalSearchRegistrationAndOverrides()
    try verifyBackupV2PluginDataCompressionSecretsAndCacheReload()
    print("[ok] v0.9.2 Tiered Global Search Registration + Backup v2 (PluginData / LZFSE / Encrypted Secrets / Cache Reload)")
}

private func verifyTieredPluginGlobalSearchRegistrationAndOverrides() throws {
    let tmp = try makeTempDir("v092-search-tiers")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pluginsRoot = tmp.appendingPathComponent("Plugins", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginsRoot, withIntermediateDirectories: true)

    // 1. Register plugin with main entry OFF, searchIndex OFF, cmd-expose ON, cmd-scoped OFF
    let created = try PluginSystem.scaffoldPlugin(
        id: "tiered-plug",
        name: "Tiered Assistant",
        keywords: ["tplug"],
        description: "Manifest-level search control",
        mode: .view,
        includeInGlobalSearch: false,
        searchIndexInGlobalSearch: false,
        capabilities: [],
        resourceScopes: [],
        commands: [
            PluginCommandSpec(
                id: "cmd-expose",
                title: "全局暴露子功能",
                subtitle: "主入口隐藏时仍可全局检索",
                keywords: ["texpose"],
                arguments: ["--expose"],
                includeInGlobalSearch: true
            ),
            PluginCommandSpec(
                id: "cmd-scoped",
                title: "仅热键与域内子功能",
                subtitle: "默认不污染顶层搜索",
                keywords: ["tscoped"],
                hotkey: "⌃⌥T",
                arguments: ["--scoped"],
                silentWhenHotKeyTriggered: true,
                includeInGlobalSearch: false
            )
        ],
        in: pluginsRoot
    )

    let dataDir = PluginDataPaths.ensureDataDirectory(for: "tiered-plug", pluginsRoot: pluginsRoot)!
    try Data("""
    {"items":[
      {"id":"idx-pub","title":"Top Pinned Note","pinned":true,"includeInGlobalSearch":true},
      {"id":"idx-priv","title":"Archived Deep Note","pinned":false,"includeInGlobalSearch":false}
    ]}
    """.utf8).write(to: dataDir.appendingPathComponent("search-index.json"))

    let plugins1 = [created]
    let entries1 = PluginSearchIndex.loadEntries(for: plugins1, in: pluginsRoot)
    check(!created.includeInGlobalSearch && !created.searchIndexInGlobalSearch, "manifest defaults respected")
    check(entries1.count == 2 && entries1.allSatisfy { !$0.includeInGlobalSearch }, "index pool OFF suppresses all entries in .all")

    // Main entry hidden in .all, visible in .plugins
    let mainAll = LauncherEngine.rankCandidates(query: "tplug", filter: .all, apps: [], plugins: plugins1, pluginSearchEntries: entries1)
    check(!mainAll.contains(where: { if case .plugin(let p) = $0.kind { return p.id == "tiered-plug" }; return false }),
          "manifest includeInGlobalSearch=false hides main entry from .all")
    let mainPlugTab = LauncherEngine.rankCandidates(query: "tplug", filter: .plugins, apps: [], plugins: plugins1, pluginSearchEntries: entries1)
    check(mainPlugTab.contains(where: { if case .plugin(let p) = $0.kind { return p.id == "tiered-plug" }; return false }),
          "main entry remains visible in .plugins tab")

    // Command with includeInGlobalSearch=true IS searchable in .all despite main entry being false!
    let exposeHits = LauncherEngine.rankCandidates(query: "texpose", filter: .all, apps: [], plugins: plugins1, pluginSearchEntries: entries1)
    check(exposeHits.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.id == "tiered-plug::cmd-expose" }; return false }),
          "cmd-expose with includeInGlobalSearch=true appears in .all independently of main entry")

    // Command with includeInGlobalSearch=false is hidden in .all, visible in .plugins & scoped mode
    let scopedAll = LauncherEngine.rankCandidates(query: "tscoped", filter: .all, apps: [], plugins: plugins1, pluginSearchEntries: entries1)
    check(!scopedAll.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.id == "tiered-plug::cmd-scoped" }; return false }),
          "cmd-scoped with includeInGlobalSearch=false is hidden from .all")
    let scopedTab = LauncherEngine.rankCandidates(query: "tscoped", filter: .plugins, apps: [], plugins: plugins1, pluginSearchEntries: entries1)
    check(scopedTab.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.id == "tiered-plug::cmd-scoped" }; return false }),
          "cmd-scoped remains searchable in .plugins tab")

    // 2. Recording usage count does NOT clobber manifest includeInGlobalSearch=false
    PluginSystem.recordPluginUsage(id: "tiered-plug", in: pluginsRoot)
    let afterUsage = PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot)
    check(!afterUsage.includeInGlobalSearch && afterUsage.overrides.launchCount == 1,
          "recordPluginUsage preserves nil tri-state override and manifest false default")

    // 3. User overrides: enable cmd-scoped & index pool in Global Search
    try PluginSystem.setPluginCommandSearchEnabled(pluginID: "tiered-plug", commandID: "cmd-scoped", enabled: true, in: pluginsRoot)
    try PluginSystem.setPluginSearchIndexGlobalEnabled(pluginID: "tiered-plug", enabled: true, in: pluginsRoot)
    let overridden = PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot)
    let entries2 = PluginSearchIndex.loadEntries(for: [overridden], in: pluginsRoot)

    let scopedNowInAll = LauncherEngine.rankCandidates(query: "tscoped", filter: .all, apps: [], plugins: [overridden], pluginSearchEntries: entries2)
    check(scopedNowInAll.contains(where: { if case .pluginCommand(let c) = $0.kind { return c.id == "tiered-plug::cmd-scoped" }; return false }),
          "user override enables manifest-disabled command in .all")

    // Item-level includeInGlobalSearch inside search-index.json: idx-pub true, idx-priv false
    let pubItemHits = LauncherEngine.rankCandidates(query: "Pinned", filter: .all, apps: [], plugins: [overridden], pluginSearchEntries: entries2)
    check(pubItemHits.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "idx-pub" }; return false }),
          "index pool override ON exposes item with includeInGlobalSearch=true")
    let privItemHits = LauncherEngine.rankCandidates(query: "Archived", filter: .all, apps: [], plugins: [overridden], pluginSearchEntries: entries2)
    check(!privItemHits.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "idx-priv" }; return false }),
          "item with includeInGlobalSearch=false stays out of .all even when index pool is ON")
    let privScopedHits = LauncherEngine.rankCandidates(
        query: "Archived", filter: .plugins, apps: [], plugins: [overridden],
        pluginSearchEntries: entries2, scopedPluginID: "tiered-plug"
    )
    check(privScopedHits.contains(where: { if case .pluginItem(let e) = $0.kind { return e.itemID == "idx-priv" }; return false }),
          "item with includeInGlobalSearch=false remains searchable inside scoped plugin mode")

    // 4. Reset overrides restores manifest registration defaults
    try PluginSystem.resetPluginOverrides(id: "tiered-plug", in: pluginsRoot)
    let resetDesc = PluginSystem.loadPlugin(at: created.directoryURL, in: pluginsRoot)
    check(!resetDesc.includeInGlobalSearch && !resetDesc.searchIndexInGlobalSearch, "reset restores manifest false defaults")
    let resetCmds = PluginCommandRegistry.registeredCommands(for: [resetDesc])
    check(resetCmds.first(where: { $0.command.id == "cmd-expose" })?.isSearchEnabled == true, "reset restores cmd-expose=true")
    check(resetCmds.first(where: { $0.command.id == "cmd-scoped" })?.isSearchEnabled == false, "reset restores cmd-scoped=false")
}

private func verifyBackupV2PluginDataCompressionSecretsAndCacheReload() throws {
    let root = try makeTempDir("v092-backup-v2")
    defer { try? FileManager.default.removeItem(at: root) }

    let srcSupport = root.appendingPathComponent("src-support", isDirectory: true)
    let srcPlugins = srcSupport.appendingPathComponent("Plugins", isDirectory: true)
    let srcHome = root.appendingPathComponent("src-home", isDirectory: true)
    let dstSupport = root.appendingPathComponent("dst-support", isDirectory: true)
    let dstPlugins = dstSupport.appendingPathComponent("Plugins", isDirectory: true)
    let dstHome = root.appendingPathComponent("dst-home", isDirectory: true)
    try FileManager.default.createDirectory(at: srcPlugins, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: srcHome.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dstHome, withIntermediateDirectories: true)

    // 1. Verify v1 schema archive backward compatibility
    let v1Payload = BackupPayload(
        mosConfig: MosConfig(), telemetryConfig: SystemMonitorConfig(),
        rawConfigFiles: [:], pinnedClipboardItems: [], plugins: []
    )
    let v1SHA = try BackupArchiveService.computePayloadSHA256(v1Payload)
    let v1Env = BackupEnvelope(
        schemaVersion: 1, createdAtISO8601: "2026-11-01T00:00:00Z",
        appVersion: "0.7.0", hostName: "legacy-mac", payloadSHA256: v1SHA, payload: v1Payload
    )
    let v1Bytes = try JSONEncoder().encode(v1Env)
    let v1Summary = try BackupArchiveService.inspectBackupData(v1Bytes)
    check(v1Summary.schemaVersion == 1 && !v1Summary.isCompressed && v1Summary.pluginDataFileCount == 0,
          "v1 archive inspects cleanly under v2 service")

    // 2. Create plugin with secret field, backupExclude, PluginData files, and external path file
    let extNoteURL = srcHome.appendingPathComponent("Documents/Lumakey-Notes.md")
    try "- [ ] [2026-11-16 09:00] Test external note backup\n".write(to: extNoteURL, atomically: true, encoding: .utf8)

    _ = try PluginSystem.scaffoldPlugin(
        id: "vault-notes",
        name: "Vault Notes",
        keywords: ["vnotes"],
        description: "Plugin with data, external path & secret",
        mode: .view,
        backupExclude: ["raw-dump/*"],
        config: [
            PluginConfigField(key: "apiToken", label: "API Token", type: .secret, required: true),
            PluginConfigField(key: "notesPath", label: "Notes Path", type: .path, defaultValue: "~/Documents/Lumakey-Notes.md", includeInBackup: true)
        ],
        capabilities: [],
        resourceScopes: [.filesystem],
        in: srcPlugins
    )
    try PluginSystem.updatePluginConfig(
        id: "vault-notes",
        values: ["apiToken": "sk-super-secret-token-2026", "notesPath": "~/Documents/Lumakey-Notes.md"],
        in: srcPlugins
    )

    let dataDir = PluginDataPaths.ensureDataDirectory(for: "vault-notes", pluginsRoot: srcPlugins)!
    try Data(#"{"items":[{"id":"n1","title":"Saved Index Item"}]}"#.utf8).write(to: dataDir.appendingPathComponent("search-index.json"))
    try Data(#"{"summary":"12 items","badge":"12"}"#.utf8).write(to: dataDir.appendingPathComponent("status.json"))
    try Data(repeating: 0x41, count: 4096).write(to: dataDir.appendingPathComponent("bookmarks.sqlite"))
    // Noise files that MUST be skipped automatically
    let tmpSub = dataDir.appendingPathComponent(".tmp-abc123", isDirectory: true)
    let cacheSub = dataDir.appendingPathComponent("cache", isDirectory: true)
    let excludedSub = dataDir.appendingPathComponent("raw-dump", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpSub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cacheSub, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: excludedSub, withIntermediateDirectories: true)
    try Data("tmp".utf8).write(to: tmpSub.appendingPathComponent("scratch.bin"))
    try Data("cache".utf8).write(to: cacheSub.appendingPathComponent("http.json"))
    try Data("excluded".utf8).write(to: excludedSub.appendingPathComponent("big.bin"))
    try Data("log".utf8).write(to: dataDir.appendingPathComponent("debug.log"))

    // 3. Export compressed + passphrase-encrypted v2 archive
    let uncompressed = try BackupArchiveService.exportBackupData(
        appSupportDirectory: srcSupport, pluginsDirectory: srcPlugins, homeDirectory: srcHome,
        encryptionPassphrase: nil, compress: false
    )
    let compressedEncrypted = try BackupArchiveService.exportBackupData(
        appSupportDirectory: srcSupport, pluginsDirectory: srcPlugins, homeDirectory: srcHome,
        encryptionPassphrase: "correct-horse-battery", compress: true
    )
    check(BackupArchiveService.isCompressedArchive(compressedEncrypted), "LZFSE magic header LMKYBK02 present")
    check(compressedEncrypted.count < uncompressed.count, "LZFSE compressed archive smaller than raw JSON (\(compressedEncrypted.count) < \(uncompressed.count))")
    check(String(data: uncompressed, encoding: .utf8)?.contains("sk-super-secret-token-2026") == false,
          "secret never exported when passphrase is nil")
    check(compressedEncrypted.range(of: Data("sk-super-secret-token-2026".utf8)) == nil,
          "plaintext secret never present in compressed encrypted archive bytes")

    let v2Summary = try BackupArchiveService.inspectBackupData(compressedEncrypted)
    check(v2Summary.schemaVersion == 2 && v2Summary.isCompressed && v2Summary.hasEncryptedSecrets, "v2 summary flags")
    check(v2Summary.pluginDataPluginIDs == ["vault-notes"] && v2Summary.pluginDataFileCount == 3,
          "collected 3 persistent PluginData files and filtered out .tmp/cache/log/backupExclude (got \(v2Summary.pluginDataFileCount))")
    check(v2Summary.externalFileCount == 1, "collected 1 external ~/Documents file")

    // 4. Pre-populate dstSupport to test pre-restore safety snapshot + wrong password rejection
    MosConfig().save(to: dstSupport.appendingPathComponent("mos-config.json"))

    var caughtNeedPass = false
    do {
        _ = try BackupArchiveService.restoreBackupData(
            compressedEncrypted, options: BackupRestoreOptions(decryptionPassphrase: nil),
            appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
        )
    } catch BackupArchiveError.passwordRequired { caughtNeedPass = true }
    check(caughtNeedPass, "missing passphrase throws .passwordRequired before overwrite")

    var caughtWrongPass = false
    do {
        _ = try BackupArchiveService.restoreBackupData(
            compressedEncrypted, options: BackupRestoreOptions(decryptionPassphrase: "wrong-pass"),
            appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
        )
    } catch BackupArchiveError.invalidPassword { caughtWrongPass = true }
    check(caughtWrongPass, "wrong passphrase throws .invalidPassword without corrupting target")

    // 5. Restore with correct passphrase into dstSupport & dstHome
    var okOpts = BackupRestoreOptions.all
    okOpts.decryptionPassphrase = "correct-horse-battery"
    let report = try BackupArchiveService.restoreBackupData(
        compressedEncrypted, options: okOpts,
        appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
    )
    check(report.safetySnapshotURL != nil && FileManager.default.fileExists(atPath: report.safetySnapshotURL!.path),
          "pre-restore safety snapshot written before overwrite")
    check(report.restoredPluginDataIDs == ["vault-notes"] && report.restoredExternalFileCount == 1,
          "restored PluginData & external ~/Documents file")
    check(report.restoredSecretPluginIDs == ["vault-notes"], "restored encrypted plugin secret")

    let dstDataDir = PluginDataPaths.dataDirectory(for: "vault-notes", pluginsRoot: dstPlugins)!
    check(FileManager.default.fileExists(atPath: dstDataDir.appendingPathComponent("search-index.json").path), "restored search-index.json")
    check(FileManager.default.fileExists(atPath: dstDataDir.appendingPathComponent("bookmarks.sqlite").path), "restored bookmarks.sqlite")
    check(!FileManager.default.fileExists(atPath: dstDataDir.appendingPathComponent("debug.log").path), "noise debug.log not restored")

    let dstNoteText = try String(contentsOf: dstHome.appendingPathComponent("Documents/Lumakey-Notes.md"), encoding: .utf8)
    check(dstNoteText.contains("Test external note backup"), "restored external path file into new home directory")

    let restoredPlugin = PluginSystem.loadPlugin(at: dstPlugins.appendingPathComponent("vault-notes"), in: dstPlugins, allowKeychainInteraction: false)
    check(restoredPlugin.userConfig["apiToken"] == "sk-super-secret-token-2026",
          "restored secret decrypted into destination scoped LocalSecretVault")

    // 6. Verify SnippetStore & AppUsageService hot-reload after disk file replacement
    let snipURL = root.appendingPathComponent("snippets-reload.json")
    let snipStore = SnippetStore(fileURL: snipURL)
    _ = try snipStore.upsert(SnippetItem(title: "Old", keyword: ";old", content: "OLD"))
    check(snipStore.allSnippets().contains(where: { $0.keyword == ";old" }), "initial snippet cached")
    let replacedSnips = [SnippetItem(title: "Restored", keyword: ";restored", content: "NEW_FROM_BACKUP")]
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    try enc.encode(replacedSnips).write(to: snipURL, options: .atomic)
    snipStore.reloadFromDisk()
    check(snipStore.allSnippets().map(\.keyword) == [";restored"], "SnippetStore.reloadFromDisk refreshes cached items immediately")

    let usageURL = root.appendingPathComponent("usage-reload.json")
    let usageSvc = AppUsageService(storageURL: usageURL, debounceNanoseconds: 5_000_000_000)
    usageSvc.setPinned(true, appID: "/Applications/OldApp.app")
    let restoredUsage = AppUsageState(pinnedAppIDs: ["/Applications/RestoredApp.app"], records: [:])
    let usageEnc = JSONEncoder(); usageEnc.dateEncodingStrategy = .iso8601
    try usageEnc.encode(restoredUsage).write(to: usageURL, options: .atomic)
    usageSvc.discardPendingAndReloadFromDisk()
    check(usageSvc.pinnedAppIDs == ["/Applications/RestoredApp.app"],
          "AppUsageService.discardPendingAndReloadFromDisk cancels pending write and loads restored state")
}
