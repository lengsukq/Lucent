import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation

@Suite("Plugin Tiered Global Search Registration & Backup v2 Verification")
struct LucentBackupV2AndSearchTierTests {
    private func makeIsolatedDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-v092-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Manifest global search flags control main entry, sub-commands, and search-index independently with tri-state user overrides")
    func tieredGlobalSearchRegistrationAndOverrides() throws {
        let root = try makeIsolatedDir("search-tiers")
        defer { try? FileManager.default.removeItem(at: root) }
        let pluginsDir = root.appendingPathComponent("Plugins", isDirectory: true)

        let plugin = try PluginSystem.scaffoldPlugin(
            id: "focus-notes",
            name: "Focus Notes",
            keywords: ["fnotes"],
            description: "Scoped notes",
            mode: .view,
            includeInGlobalSearch: false,
            searchIndexInGlobalSearch: false,
            capabilities: [],
            resourceScopes: [],
            commands: [
                PluginCommandSpec(id: "quick-capture", title: "Quick Capture", subtitle: "Global", keywords: ["fcap"], includeInGlobalSearch: true),
                PluginCommandSpec(id: "maint-gc", title: "Internal GC", subtitle: "Scoped", keywords: ["fgc"], includeInGlobalSearch: false)
            ],
            in: pluginsDir
        )

        let dataDir = try #require(PluginDataPaths.ensureDataDirectory(for: "focus-notes", pluginsRoot: pluginsDir))
        try Data("""
        {"items":[
          {"id":"idx-pub","title":"Top Pinned Note","pinned":true,"includeInGlobalSearch":true},
          {"id":"idx-priv","title":"Archived Deep Note","pinned":false,"includeInGlobalSearch":false}
        ]}
        """.utf8).write(to: dataDir.appendingPathComponent("search-index.json"))

        #expect(!plugin.includeInGlobalSearch && !plugin.searchIndexInGlobalSearch)
        let entries1 = PluginSearchIndex.loadEntries(for: [plugin], in: pluginsDir)
        #expect(entries1.count == 2 && entries1.allSatisfy { !$0.includeInGlobalSearch })

        let mainHits = LauncherEngine.rankCandidates(query: "fnotes", filter: .all, apps: [], plugins: [plugin], pluginSearchEntries: entries1)
        #expect(!mainHits.contains { if case .plugin(let p) = $0.kind { return p.id == "focus-notes" }; return false })

        let capHits = LauncherEngine.rankCandidates(query: "fcap", filter: .all, apps: [], plugins: [plugin], pluginSearchEntries: entries1)
        #expect(capHits.contains { if case .pluginCommand(let c) = $0.kind { return c.id == "focus-notes::quick-capture" }; return false })

        let gcHits = LauncherEngine.rankCandidates(query: "fgc", filter: .all, apps: [], plugins: [plugin], pluginSearchEntries: entries1)
        #expect(!gcHits.contains { if case .pluginCommand(let c) = $0.kind { return c.id == "focus-notes::maint-gc" }; return false })

        PluginSystem.recordPluginUsage(id: "focus-notes", in: pluginsDir)
        let afterUsage = PluginSystem.loadPlugin(at: plugin.directoryURL, in: pluginsDir)
        #expect(!afterUsage.includeInGlobalSearch && afterUsage.overrides.launchCount == 1)

        try PluginSystem.setPluginCommandSearchEnabled(pluginID: "focus-notes", commandID: "maint-gc", enabled: true, in: pluginsDir)
        try PluginSystem.setPluginSearchIndexGlobalEnabled(pluginID: "focus-notes", enabled: true, in: pluginsDir)
        let reloaded = PluginSystem.loadPlugin(at: plugin.directoryURL, in: pluginsDir)
        let entries2 = PluginSearchIndex.loadEntries(for: [reloaded], in: pluginsDir)

        let gcAfterOverride = LauncherEngine.rankCandidates(query: "fgc", filter: .all, apps: [], plugins: [reloaded], pluginSearchEntries: entries2)
        #expect(gcAfterOverride.contains { if case .pluginCommand(let c) = $0.kind { return c.id == "focus-notes::maint-gc" }; return false })

        let pubItemHits = LauncherEngine.rankCandidates(query: "Pinned", filter: .all, apps: [], plugins: [reloaded], pluginSearchEntries: entries2)
        #expect(pubItemHits.contains { if case .pluginItem(let e) = $0.kind { return e.itemID == "idx-pub" }; return false })
        let privItemHits = LauncherEngine.rankCandidates(query: "Archived", filter: .all, apps: [], plugins: [reloaded], pluginSearchEntries: entries2)
        #expect(!privItemHits.contains { if case .pluginItem(let e) = $0.kind { return e.itemID == "idx-priv" }; return false })

        try PluginSystem.resetPluginOverrides(id: "focus-notes", in: pluginsDir)
        let resetDesc = PluginSystem.loadPlugin(at: plugin.directoryURL, in: pluginsDir)
        #expect(!resetDesc.includeInGlobalSearch && !resetDesc.searchIndexInGlobalSearch)
    }

    @Test("Backup v2 compresses LZFSE, bundles PluginData & includeInBackup paths, seals optional secrets, and reloads singletons")
    func backupV2EndToEndEncryptionAndRestore() throws {
        let root = try makeIsolatedDir("backup-v2")
        defer { try? FileManager.default.removeItem(at: root) }
        let srcSupport = root.appendingPathComponent("src-support", isDirectory: true)
        let srcPlugins = srcSupport.appendingPathComponent("Plugins", isDirectory: true)
        let srcHome = root.appendingPathComponent("src-home", isDirectory: true)
        let dstSupport = root.appendingPathComponent("dst-support", isDirectory: true)
        let dstPlugins = dstSupport.appendingPathComponent("Plugins", isDirectory: true)
        let dstHome = root.appendingPathComponent("dst-home", isDirectory: true)
        try FileManager.default.createDirectory(at: srcHome.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dstSupport, withIntermediateDirectories: true)

        let mismatchPayload = BackupPayload(
            mosConfig: MosConfig(), telemetryConfig: SystemMonitorConfig(),
            rawConfigFiles: [:], pinnedClipboardItems: [], plugins: []
        )
        let mismatchEnv = BackupEnvelope(
            schemaVersion: 1, createdAtISO8601: "2026-11-01T00:00:00Z",
            appVersion: "0.9.0", hostName: "test-mac",
            payloadSHA256: try BackupArchiveService.computePayloadSHA256(mismatchPayload),
            payload: mismatchPayload
        )
        #expect(throws: BackupArchiveError.unsupportedSchemaVersion(1)) {
            _ = try BackupArchiveService.inspectBackupData(try JSONEncoder().encode(mismatchEnv))
        }

        try "# Inbox\nHello v2".write(to: srcHome.appendingPathComponent("Notes/inbox.md"), atomically: true, encoding: .utf8)
        _ = try PluginSystem.scaffoldPlugin(
            id: "note-box",
            name: "Note Box",
            keywords: ["nbox"],
            description: "Notes",
            mode: .view,
            backupExclude: ["skip-dir/*"],
            config: [
                PluginConfigField(key: "secretKey", label: "Key", type: .secret),
                PluginConfigField(key: "mdPath", label: "Path", type: .path, defaultValue: "~/Notes/inbox.md", includeInBackup: true)
            ],
            capabilities: [],
            resourceScopes: [.filesystem],
            in: srcPlugins
        )
        try PluginSystem.updatePluginConfig(id: "note-box", values: ["secretKey": "TOP_SECRET_V2", "mdPath": "~/Notes/inbox.md"], in: srcPlugins)

        let pDataDir = try #require(PluginDataPaths.ensureDataDirectory(for: "note-box", pluginsRoot: srcPlugins))
        try Data(#"{"items":[{"id":"1","title":"Memo"}]}"#.utf8).write(to: pDataDir.appendingPathComponent("search-index.json"))
        let skipDir = pDataDir.appendingPathComponent("skip-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: skipDir, withIntermediateDirectories: true)
        try Data("ignored".utf8).write(to: skipDir.appendingPathComponent("raw.dat"))
        try Data("log".utf8).write(to: pDataDir.appendingPathComponent("debug.log"))

        MosConfig().save(to: dstSupport.appendingPathComponent("mos-config.json"))
        let archive = try BackupArchiveService.exportBackupData(
            appSupportDirectory: srcSupport, pluginsDirectory: srcPlugins, homeDirectory: srcHome,
            encryptionPassphrase: "unit-test-passphrase", compress: true
        )
        #expect(BackupArchiveService.isCompressedArchive(archive))
        #expect(archive.range(of: Data("TOP_SECRET_V2".utf8)) == nil)
        let summary = try BackupArchiveService.inspectBackupData(archive)
        #expect(summary.schemaVersion == 2 && summary.isCompressed && summary.hasEncryptedSecrets)
        #expect(summary.pluginDataFileCount == 1 && summary.externalFileCount == 1)

        #expect(throws: BackupArchiveError.passwordRequired) {
            _ = try BackupArchiveService.restoreBackupData(
                archive, options: BackupRestoreOptions(decryptionPassphrase: nil),
                appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
            )
        }
        #expect(throws: BackupArchiveError.invalidPassword) {
            _ = try BackupArchiveService.restoreBackupData(
                archive, options: BackupRestoreOptions(decryptionPassphrase: "bad-pass"),
                appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
            )
        }

        let report = try BackupArchiveService.restoreBackupData(
            archive, options: BackupRestoreOptions(decryptionPassphrase: "unit-test-passphrase"),
            appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, homeDirectory: dstHome
        )
        #expect(report.safetySnapshotURL != nil && FileManager.default.fileExists(atPath: report.safetySnapshotURL!.path))
        #expect(report.restoredPluginDataIDs == ["note-box"] && report.restoredExternalFileCount == 1)
        #expect(report.restoredSecretPluginIDs == ["note-box"])
        #expect(try String(contentsOf: dstHome.appendingPathComponent("Notes/inbox.md"), encoding: .utf8).contains("Hello v2"))

        let loaded = PluginSystem.loadPlugin(at: dstPlugins.appendingPathComponent("note-box"), in: dstPlugins)
        #expect(loaded.userConfig["secretKey"] == "TOP_SECRET_V2")

        let snipURL = root.appendingPathComponent("snippets-reload.json")
        let snipStore = SnippetStore(fileURL: snipURL)
        _ = try snipStore.upsert(SnippetItem(title: "Old", keyword: ";old", content: "OLD"))
        try JSONEncoder().encode([SnippetItem(title: "Restored", keyword: ";restored", content: "NEW")]).write(to: snipURL, options: .atomic)
        snipStore.reloadFromDisk()
        #expect(snipStore.allSnippets().map(\.keyword) == [";restored"])

        let usageURL = root.appendingPathComponent("usage-reload.json")
        let usageSvc = AppUsageService(storageURL: usageURL, debounceNanoseconds: 5_000_000_000)
        usageSvc.setPinned(true, appID: "/Applications/OldApp.app")
        let usageEnc = JSONEncoder(); usageEnc.dateEncodingStrategy = .iso8601
        try usageEnc.encode(AppUsageState(pinnedAppIDs: ["/Applications/RestoredApp.app"], records: [:])).write(to: usageURL, options: .atomic)
        usageSvc.discardPendingAndReloadFromDisk()
        #expect(usageSvc.pinnedAppIDs == ["/Applications/RestoredApp.app"])
    }

    @Test("LumaLinkNetworkResolver prioritizes physical LAN over tunnel interfaces, filters Fake-IPs, and supports manual selection")
    func lumaLinkNetworkResolverAndManualOverride() {
        #expect(LumaLinkNetworkResolver.classifyInterface(name: "utun2", ipv4: "198.18.0.1") == nil)
        #expect(LumaLinkNetworkResolver.classifyInterface(name: "awdl0", ipv4: "192.168.1.9") == nil)
        #expect(LumaLinkNetworkResolver.classifyInterface(name: "en0", ipv4: "169.254.10.20") == nil)

        let tunnel = LumaLinkNetworkResolver.classifyInterface(name: "utun4", ipv4: "100.88.12.34")!
        let wifi = LumaLinkNetworkResolver.classifyInterface(name: "en0", ipv4: "192.168.31.66")!
        #expect(tunnel.kind == .tunnel && wifi.kind == .lan && wifi.priority > tunnel.priority)

        let ordered = [wifi, tunnel]
        let autoResolved = LumaLinkNetworkResolver.resolveConnectHost(config: LumaLinkConfig(), candidates: ordered)
        #expect(autoResolved.host == "192.168.31.66" && !autoResolved.isCustomHost)

        let tunnelCfg = LumaLinkConfig(preferredInterface: tunnel.id)
        let pickedTunnel = LumaLinkNetworkResolver.resolveConnectHost(config: tunnelCfg, candidates: ordered)
        #expect(pickedTunnel.host == "100.88.12.34" && pickedTunnel.activeCandidate?.id == tunnel.id)

        let customCfg = LumaLinkConfig(preferredInterface: tunnel.id, customConnectHost: "mac-studio.local")
        let pickedCustom = LumaLinkNetworkResolver.resolveConnectHost(config: customCfg, candidates: ordered)
        #expect(pickedCustom.host == "mac-studio.local" && pickedCustom.isCustomHost)

        let snap = LumaLinkServer.shared.currentSnapshot()
        #expect(snap.pairingPin.count == 6 && snap.pairingPin.allSatisfy(\.isNumber))
    }
}
