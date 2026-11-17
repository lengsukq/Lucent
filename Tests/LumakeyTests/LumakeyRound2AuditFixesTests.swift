import CoreGraphics
import Foundation
import Testing
@testable import LumakeyCore
@testable import LumakeyFoundation

@Suite("Round 2 Architecture, Security & LumaLink Store Demo Verification")
struct LumakeyRound2AuditFixesTests {
    private func makeIsolatedDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-r2-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("ProcessSupervisor handles >192KB bidirectional stdin/stdout without deadlock and drains truncated stdout without SIGPIPE")
    func processSupervisorNoDeadlockAndNoSigpipe() throws {
        let largePayload = Data(repeating: 0x5A, count: 196_608)
        let echoRes = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            stdinData: largePayload,
            timeoutSeconds: 5,
            maxOutputBytes: 262_144
        )
        #expect(echoRes.exitCode == 0 && !echoRes.timedOut)
        #expect(echoRes.stdout.utf8.count == largePayload.count)

        let finiteChatty = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "30000"],
            timeoutSeconds: 5,
            maxOutputBytes: 4_096
        )
        #expect(finiteChatty.exitCode == 0 && !finiteChatty.timedOut)
        #expect(finiteChatty.stdout.utf8.count == 4_096)
    }

    @Test("LumaLink lives in plugin-demo store registry (not BUILTIN or hardcoded starter) with encrypted tokens")
    func lumaLinkStoreDemoAndSecurityHardening() async throws {
        let dir = try makeIsolatedDir("lumalink-store")
        defer { try? FileManager.default.removeItem(at: dir) }

        let builtinIDs = Set(PluginBuiltinRegistry.descriptors().map(\.id))
        #expect(!builtinIDs.contains("builtin-lumalink"))
        #expect(builtinIDs == ["builtin-mos", "builtin-system-pulse"])
        #expect(PluginStarterGallery.templates.map(\.id) == ["sys-ip-dns", "port-killer", "shell-note"])

        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let demoStoreDir = repoRoot.appendingPathComponent("plugin-demo", isDirectory: true)
        let resolvedSource = try await PluginStoreSniffer.resolveSource(from: demoStoreDir.path)
        guard case .storeRegistry(let demoStore) = resolvedSource else {
            Issue.record("Expected plugin-demo directory to resolve as a PluginStoreSubscription")
            return
        }
        let storeIDs = Set(demoStore.manifest.plugins.map(\.id))
        #expect(storeIDs == [
            "ai-quota", "browser-hub", "lumalink-companion", "mac-pilot", "notion-bookmarks",
            "quick-remind", "screen-shield", "translate-hub"
        ])

        let browserItem = try #require(demoStore.manifest.plugins.first { $0.id == "browser-hub" })
        let installedBrowserHub = try await PluginStoreService.installStoreItem(browserItem, from: demoStore, in: dir)
        #expect(installedBrowserHub.isValid)
        #expect(installedBrowserHub.declaredCommands.count == 6)
        #expect(installedBrowserHub.customIconURL != nil)

        for newID in ["ai-quota", "translate-hub", "mac-pilot", "quick-remind", "screen-shield"] {
            let item = try #require(demoStore.manifest.plugins.first { $0.id == newID })
            let inst = try await PluginStoreService.installStoreItem(item, from: demoStore, in: dir)
            #expect(inst.isValid)
            #expect(!inst.declaredCommands.isEmpty)
            #expect(inst.customIconURL != nil)
        }

        let storeItem = try #require(demoStore.manifest.plugins.first { $0.id == LumaLinkServer.companionPluginID })
        let installed = try await PluginStoreService.installStoreItem(storeItem, from: demoStore, in: dir)
        #expect(installed.isValid)
        #expect(installed.declaredCapabilities == [.lumaLinkStatus])
        #expect(installed.declaredResourceScopes.isEmpty)
        #expect(installed.declaredCommands.count == 9)

        let cfgURL = dir.appendingPathComponent("lumalink-config.json")
        let vaultDir = dir.appendingPathComponent(".vault", isDirectory: true)
        let device = LumaLinkPairedDevice(id: "dev-1", name: "Phone", token: "paired-dev-tok-99")
        let cfg = LumaLinkConfig(enabled: false, preferredPort: 59480, pairedDevices: [device])
        cfg.save(to: cfgURL, vaultDirectory: vaultDir)

        let diskJSON = try String(contentsOf: cfgURL, encoding: .utf8)
        #expect(!diskJSON.contains("paired-dev-tok-99"))
        let reloaded = LumaLinkConfig.load(from: cfgURL, vaultDirectory: vaultDir)
        #expect(reloaded.pairedDevices.first?.token == "paired-dev-tok-99")

        let inlineTokenJSON = """
        {"enabled":false,"preferredPort":59480,"autoRestoreDisplayOnDisconnect":true,"muteMacWhenCurtainEnabled":false,"rdpEnabled":false,"rdpPort":3389,"pairedDevices":[{"id":"unsealed-1","name":"Pad","token":"INLINE_RAW_TOK","pairedAt":1000}]}
        """
        let inlineURL = dir.appendingPathComponent("unsealed-lumalink.json")
        try inlineTokenJSON.write(to: inlineURL, atomically: true, encoding: .utf8)
        let loadedUnsealed = LumaLinkConfig.load(from: inlineURL, vaultDirectory: vaultDir)
        #expect(loadedUnsealed.pairedDevices.first?.token == "")

        try inlineTokenJSON.write(to: dir.appendingPathComponent("lumalink-config.json"), atomically: true, encoding: .utf8)
        let backupBytes = try BackupArchiveService.exportBackupData(appSupportDirectory: dir)
        let backupText = String(data: backupBytes, encoding: .utf8) ?? ""
        #expect(!backupText.contains("INLINE_RAW_TOK"))
    }

    @Test("ClipboardPersistenceStore persists pinned entries and migrates transient clipboard media across restarts")
    func clipboardPinnedPersistenceAndMediaMigration() throws {
        let dir = try makeIsolatedDir("clip-persist")
        defer { try? FileManager.default.removeItem(at: dir) }

        let tempClipRoot = ClipboardPasteboardIO.clipboardTempDirectory()
        try FileManager.default.createDirectory(at: tempClipRoot, withIntermediateDirectories: true)
        let tempFile = tempClipRoot.appendingPathComponent("transient-\(UUID().uuidString).txt")
        try Data("hello-pinned".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entries: [ClipboardEntry] = [
            ClipboardEntry(title: "Pinned Command", subtitle: "Text", textValue: "swift test", isPinned: true, payloadKind: .text),
            ClipboardEntry(title: "#0EA5E9", subtitle: "Color", textValue: "#0EA5E9", isPinned: true, payloadKind: .colorHex("#0EA5E9")),
            ClipboardEntry(title: "Pinned Temp File", subtitle: "File", fileURL: tempFile, isPinned: true, payloadKind: .file(tempFile)),
            ClipboardEntry(title: "Unpinned Ephemeral", subtitle: "Text", textValue: "ephemeral-drop", isPinned: false, payloadKind: .text)
        ]

        let savedList = ClipboardPersistenceStore.savePinnedEntries(entries, appSupportDirectory: dir)
        let migratedFileEntry = savedList.first { $0.title == "Pinned Temp File" }
        #expect(migratedFileEntry?.fileURL?.path.contains("ClipboardPinned/pinned-") == true)
        try? FileManager.default.removeItem(at: tempFile)

        let restored = ClipboardPersistenceStore.loadPinnedEntries(appSupportDirectory: dir)
        #expect(restored.count == 3 && restored.allSatisfy(\.isPinned))
        #expect(restored.contains { $0.title == "Pinned Temp File" && FileManager.default.fileExists(atPath: $0.fileURL?.path ?? "") })
    }

    @Test("WebDAVClient blocks cleartext HTTP to public hosts while allowing HTTPS and RFC1918 LAN hosts")
    func webdavCleartextPublicHttpGuard() throws {
        func buildURL(_ scheme: String, _ host: String, _ path: String) -> String {
            var c = URLComponents()
            c.scheme = scheme; c.host = host; c.path = path
            return c.string ?? ""
        }
        let pubHost = "dav.cloud-storage.example"
        let lanHost = "192.168.1.20"
        let pubHttp = WebDAVClient(config: WebDAVConfig(serverURL: buildURL("http", pubHost, "/dav/"), username: "u"), password: "pw")
        #expect(throws: WebDAVError.insecureCleartextHTTP(pubHost)) {
            _ = try pubHttp.normalizedServerBaseURL()
        }
        let lanHttp = WebDAVClient(config: WebDAVConfig(serverURL: buildURL("http", lanHost, "/dav"), username: "u"), password: "pw")
        #expect(try lanHttp.normalizedServerBaseURL().host == lanHost)
        let pubHttps = WebDAVClient(config: WebDAVConfig(serverURL: buildURL("https", pubHost, "/dav"), username: "u"), password: "pw")
        #expect(try pubHttps.normalizedServerBaseURL().scheme == "https")
    }

    @Test("PluginDeepLinkParser isolates markdown temp notes with 0700/0600 permissions and content digest suffix")
    func pluginDeepLinkMarkdownNoteHardening() throws {
        var c1 = URLComponents(); c1.scheme = "lumakey"; c1.host = "reader"
        c1.queryItems = [URLQueryItem(name: "title", value: "Note:Draft/Alpha*1"), URLQueryItem(name: "markdown", value: "Hello One")]
        var c2 = c1
        c2.queryItems = [URLQueryItem(name: "title", value: "Note:Draft/Alpha*1"), URLQueryItem(name: "markdown", value: "Hello Two")]

        guard let u1 = c1.url, let u2 = c2.url,
              case .documentReader(let f1) = PluginDeepLinkParser.parse(u1),
              case .documentReader(let f2) = PluginDeepLinkParser.parse(u2) else {
            Issue.record("Expected documentReader deep link targets")
            return
        }
        defer { try? FileManager.default.removeItem(at: f1); try? FileManager.default.removeItem(at: f2) }
        #expect(f1.path != f2.path)
        let filePerm = (try FileManager.default.attributesOfItem(atPath: f1.path)[.posixPermissions] as? Int) ?? 0
        let dirPerm = (try FileManager.default.attributesOfItem(atPath: f1.deletingLastPathComponent().path)[.posixPermissions] as? Int) ?? 0
        #expect((filePerm & 0o777) == 0o600 && (dirPerm & 0o777) == 0o700)
    }

    @Test("PluginStoreDefaults seeds official GitHub demo store, respects unsubscribe, and resolves bundled archive fallback")
    func officialDemoStoreSeedingAndFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-demo-seed-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let demoDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugin-demo", isDirectory: true)
        let seeded = PluginStoreDefaults.ensureDefaultDemoStoreSeeded(appSupportDirectory: dir, bundledDirectory: demoDir)
        #expect(seeded.stores.count == 1)
        #expect(seeded.stores.first?.id == PluginStoreDefaults.officialDemoStoreID)
        #expect(seeded.stores.first?.sourceURL == PluginStoreDefaults.officialDemoSourceURL)
        #expect(seeded.stores.first?.resolvedRegistryURL == PluginStoreDefaults.officialDemoRegistryURL)
        #expect((seeded.stores.first?.manifest.plugins.count ?? 0) >= 3)

        let removed = try PluginStoreService.removeStore(storeID: PluginStoreDefaults.officialDemoStoreID, appSupportDirectory: dir)
        #expect(removed.stores.isEmpty)
        let reloadAfterUnsubscribe = PluginStoreDefaults.ensureDefaultDemoStoreSeeded(appSupportDirectory: dir, bundledDirectory: demoDir)
        #expect(reloadAfterUnsubscribe.stores.isEmpty)

        let rawZip = URL(string: "\(PluginStoreDefaults.officialDemoRawBaseURL)dist/browser-hub.zip")!
        #expect(PluginStoreDefaults.bundledDemoArchiveURL(for: rawZip, bundledDirectory: demoDir) != nil)
    }

    @Test("PluginDeepLinkParser parses lumakey://panel live floating requests and PluginNotificationService records effects safely")
    func pluginFloatingPanelDeepLinkAndNotificationEffect() throws {
        let panelURL = try #require(URL(string: "lumakey://panel/ai-quota?pin=1&interval=15&arg=--dashboard&query=codex"))
        guard case .pluginPanel(let req) = PluginDeepLinkParser.parse(panelURL) else {
            Issue.record("Expected .pluginPanel target from lumakey://panel/ai-quota")
            return
        }
        #expect(req.pluginID == "ai-quota")
        #expect(req.pinOnTop == true)
        #expect(req.refreshIntervalSeconds == 15)
        #expect(req.arguments == ["--dashboard"])
        #expect(req.query == "codex")

        let manualURL = try #require(URL(string: "lumakey://panel/quick-remind?pin=0&interval=0"))
        guard case .pluginPanel(let manualReq) = PluginDeepLinkParser.parse(manualURL) else {
            Issue.record("Expected .pluginPanel target for manual interval=0")
            return
        }
        #expect(manualReq.pinOnTop == false && manualReq.refreshIntervalSeconds == 0)

        let unsafeURL = try #require(URL(string: "lumakey://panel/..%2Fbad"))
        #expect(PluginDeepLinkParser.parse(unsafeURL) == nil)

        let rawCardJSON = """
        {
          "schemaVersion": 2,
          "title": "AI Quota Radar",
          "effect": {
            "openFloatingPanel": true,
            "floatingPanelPinOnTop": true,
            "floatingPanelIntervalSeconds": 45,
            "floatingPanelArgs": ["--dashboard"],
            "notification": {
              "title": "AI 额度雷达已刷新",
              "body": "Codex: 5h 78% · DS: ¥128.50",
              "sound": false
            }
          },
          "items": []
        }
        """
        let parsedPayload = try #require(PluginViewPayload.parse(from: rawCardJSON))
        let eff = try #require(parsedPayload.effect)
        #expect(eff.openFloatingPanel == true)
        #expect(eff.floatingPanelPinOnTop == true)
        #expect(eff.floatingPanelIntervalSeconds == 45)
        #expect(eff.floatingPanelArgs == ["--dashboard"])

        PluginNotificationService.shared.clearHistory()
        let noteSpec = try #require(eff.notification)
        let rec = try #require(PluginNotificationService.shared.post(
            noteSpec,
            pluginID: "ai-quota",
            pluginName: "AI 额度雷达"
        ))
        #expect(rec.pluginID == "ai-quota")
        #expect(rec.payload.title == "AI 额度雷达已刷新")
        #expect(rec.payload.subtitle == "AI 额度雷达")
        #expect(rec.payload.body.contains("¥128.50"))
        #expect(PluginNotificationService.shared.recentRecords(limit: 5).first?.id == rec.id)
    }
}
