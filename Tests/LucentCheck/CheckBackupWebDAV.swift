import CoreGraphics
import Foundation
import LucentCore

func testV070BackupAndWebDAV() throws {
    let root = try makeTempDir("v070-backup")
    defer { try? FileManager.default.removeItem(at: root) }

    let srcSupport = root.appendingPathComponent("src-support", isDirectory: true)
    let srcPlugins = srcSupport.appendingPathComponent("Plugins", isDirectory: true)
    let dstSupport = root.appendingPathComponent("dst-support", isDirectory: true)
    let dstPlugins = dstSupport.appendingPathComponent("Plugins", isDirectory: true)
    let dstClipDir = root.appendingPathComponent("dst-clip", isDirectory: true)
    try FileManager.default.createDirectory(at: srcPlugins, withIntermediateDirectories: true)

    let customMos = MosConfig(
        enabled: true, reverseWheelDirection: false, smoothScroll: true,
        stepPixels: 54.0, smoothness: 0.28, shiftHorizontal: true, optionBoost: false,
        excludedBundleIDs: ["com.valve.steam"]
    )
    customMos.save(to: srcSupport.appendingPathComponent("mos-config.json"))

    var customPulse = SystemMonitorConfig()
    customPulse.floatingEnabled = true
    customPulse.showInMenuBar = true
    customPulse.displayMode = .alwaysExpanded
    customPulse.menuShowFreq = true
    customPulse.save(to: srcSupport.appendingPathComponent("telemetry-v2.json"))

    try #"{"launcher":"opt+space"}"#.write(to: srcSupport.appendingPathComponent("hotkeys.json"), atomically: true, encoding: .utf8)
    try #"[{"keyword":";hi","body":"Hello"}]"#.write(to: srcSupport.appendingPathComponent("snippets.json"), atomically: true, encoding: .utf8)
    try #"{"serverURL":"https://dav.jianguoyun.com/dav/","username":"alice@example.com","password":"PLAIN_SECRET_MUST_NOT_LEAK"}"#
        .write(to: srcSupport.appendingPathComponent("webdav-config.json"), atomically: true, encoding: .utf8)

    let smallImgURL = root.appendingPathComponent("small-pin.png")
    try renderTextPNG(text: "BACKUP PIN", to: smallImgURL)
    let hugeImgURL = root.appendingPathComponent("huge-pin.png")
    try Data(repeating: 0xAB, count: 2_200_000).write(to: hugeImgURL)

    let clipItems: [ClipboardEntry] = [
        ClipboardEntry(title: "kubectl", subtitle: "文本", textValue: "kubectl get pods -A", isPinned: true, payloadKind: .text),
        ClipboardEntry(title: "#38BDF8", subtitle: "色值", textValue: "#38BDF8", isPinned: true, payloadKind: .colorHex("#38BDF8")),
        ClipboardEntry(title: "小尺寸钉图", subtitle: "small", fileURL: smallImgURL, isPinned: true, payloadKind: .image(smallImgURL, CGSize(width: 480, height: 140))),
        ClipboardEntry(title: "超2MB大图", subtitle: "huge", fileURL: hugeImgURL, isPinned: true, payloadKind: .image(hugeImgURL, CGSize(width: 2400, height: 1600))),
        ClipboardEntry(title: "未收藏临时文本", subtitle: "transient", textValue: "ignore-me", isPinned: false, payloadKind: .text)
    ]

    _ = try PluginSystem.scaffoldPlugin(
        id: "backup-echo", name: "Backup Echo", keywords: ["becho"],
        description: "Test backup plugin", mode: .script, in: srcPlugins
    )
    let nestedAsset = srcPlugins.appendingPathComponent("backup-echo/assets/note.txt")
    try FileManager.default.createDirectory(at: nestedAsset.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "asset-ok".write(to: nestedAsset, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nestedAsset.path)

    let archiveData = try BackupArchiveService.exportBackupData(
        appSupportDirectory: srcSupport, pluginsDirectory: srcPlugins, clipboardEntries: clipItems
    )
    let archiveString = String(data: archiveData, encoding: .utf8) ?? ""
    check(!archiveString.contains("PLAIN_SECRET_MUST_LEAK") && !archiveString.contains("PLAIN_SECRET_MUST_NOT_LEAK"), "WebDAV plaintext password stripped on export")
    check(!archiveString.contains("ignore-me"), "Unpinned clipboard entry excluded from export")

    let summary = try BackupArchiveService.inspectBackupData(archiveData)
    check(summary.schemaVersion == BackupEnvelope.currentSchemaVersion, "BackupEnvelope schemaVersion == \(BackupEnvelope.currentSchemaVersion)")
    check(summary.configCount == 5 && summary.pinnedClipboardCount == 4 && summary.skippedLargeImageCount == 1, "Backup summary counts verified")
    check(summary.pluginIDs == ["backup-echo"], "Exported plugin bundle backup-echo")

    let tamperedText = archiveString.replacingOccurrences(of: "kubectl get pods -A", with: "kubectl get pods -X")
    var caughtTamper = false
    do { _ = try BackupArchiveService.inspectBackupData(Data(tamperedText.utf8)) } catch BackupArchiveError.checksumMismatch { caughtTamper = true }
    check(caughtTamper, "Tampered payload bytes caught by SHA-256 checksum verification")

    var maliciousEnv = try JSONDecoder().decode(BackupEnvelope.self, from: archiveData)
    maliciousEnv.payload.plugins = [
        BackupPluginBundle(id: "backup-echo", files: [
            BackupPluginFileRecord(relativePath: "../../escape.sh", contentBase64: Data("echo pwn".utf8).base64EncodedString(), posixPermissions: 0o755, isExecutable: true)
        ])
    ]
    maliciousEnv.payloadSHA256 = try BackupArchiveService.computePayloadSHA256(maliciousEnv.payload)
    var caughtTraversal = false
    do {
        _ = try BackupArchiveService.restoreBackupData(try JSONEncoder().encode(maliciousEnv), appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins)
    } catch BackupArchiveError.unsafePath { caughtTraversal = true }
    check(caughtTraversal, "Malicious ../ plugin path traversal rejected before write")

    var badIDEnv = try JSONDecoder().decode(BackupEnvelope.self, from: archiveData)
    badIDEnv.payload.plugins = [BackupPluginBundle(id: "../Bad_ID", files: [])]
    badIDEnv.payloadSHA256 = try BackupArchiveService.computePayloadSHA256(badIDEnv.payload)
    var caughtBadID = false
    do {
        _ = try BackupArchiveService.restoreBackupData(try JSONEncoder().encode(badIDEnv), appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins)
    } catch BackupArchiveError.unsafePluginID { caughtBadID = true }
    check(caughtBadID, "Invalid plugin ID rejected by PluginSystem.isSafePluginID")

    let report = try BackupArchiveService.restoreBackupData(
        archiveData, appSupportDirectory: dstSupport, pluginsDirectory: dstPlugins, clipboardImagesDirectory: dstClipDir
    )
    check(MosConfig.load(from: dstSupport.appendingPathComponent("mos-config.json")) == customMos, "Restored MosConfig matches")
    check(SystemMonitorConfig.load(from: dstSupport.appendingPathComponent("telemetry-v2.json")) == customPulse, "Restored SystemMonitorConfig matches")
    check(FileManager.default.fileExists(atPath: dstSupport.appendingPathComponent("hotkeys.json").path), "Restored hotkeys.json")
    check(FileManager.default.fileExists(atPath: dstSupport.appendingPathComponent("snippets.json").path), "Restored snippets.json")
    check(report.restoredClipboardEntries.count == 3 && report.skippedClipboardCount == 1, "Restored 3 valid pinned clipboard entries")

    let restoredImgEntry = report.restoredClipboardEntries.first {
        if case .image = $0.payloadKind { return true }
        return false
    }
    check(restoredImgEntry?.fileURL.flatMap { MediaClassifier.readImageDimensions(at: $0) } == CGSize(width: 480, height: 140), "Restored embedded PNG dimensions intact")

    let restoredPluginDir = dstPlugins.appendingPathComponent("backup-echo")
    let loadedPlugin = PluginSystem.loadPlugin(at: restoredPluginDir)
    check(loadedPlugin.isValid, "Restored plugin passes validation: \(loadedPlugin.validationIssues)")
    let scriptPath = restoredPluginDir.appendingPathComponent("run.sh").path
    let perms = (try FileManager.default.attributesOfItem(atPath: scriptPath)[.posixPermissions] as? Int) ?? 0
    check((perms & 0o777) == 0o755 && FileManager.default.isExecutableFile(atPath: scriptPath), "Restored script has 0o755 executable permission")
    let execRes = try PluginSystem.runScriptPlugin(loadedPlugin, query: "hello")
    check(execRes.exitCode == 0 && execRes.stdout.contains("[backup-echo] ok:"), "Restored executable plugin runs cleanly")

    let testKeychainService = "app.lucent.macos.webdav.check.\(UUID().uuidString)"
    defer { try? WebDAVKeychainStore.deletePassword(account: "alice@example.com", service: testKeychainService) }
    try WebDAVKeychainStore.savePassword("app-pass-1", account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == "app-pass-1", "Keychain initial save/load")
    try WebDAVKeychainStore.savePassword("app-pass-2", account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == "app-pass-2", "Keychain SecItemUpdate")
    try WebDAVKeychainStore.deletePassword(account: "alice@example.com", service: testKeychainService)
    check(try WebDAVKeychainStore.loadPassword(account: "alice@example.com", service: testKeychainService) == nil, "Keychain SecItemDelete")

    let upperCaseXML = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response><D:href>/dav/LucentBackups/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/dav/LucentBackups/readme.txt</D:href><D:propstat><D:prop><D:getcontentlength>12</D:getcontentlength></D:prop></D:propstat></D:response>
      <D:response><D:href>/dav/LucentBackups/lucent-backup-20261113-090000.lucentbackup</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>1024</D:getcontentlength><D:getlastmodified>Fri, 13 Nov 2026 09:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response>
      <dav:response xmlns:dav="DAV:"><dav:href>/dav/LucentBackups/lucent-backup-20261113-113000.lucentbackup</dav:href><dav:propstat><dav:prop><dav:resourcetype/><dav:getcontentlength>2048</dav:getcontentlength><dav:getlastmodified>Fri, 13 Nov 2026 11:30:00 GMT</dav:getlastmodified></dav:prop></dav:propstat></dav:response>
    </D:multistatus>
    """.utf8)
    let parsedItems = try WebDAVMultiStatusParser.parse(
        xmlData: upperCaseXML, baseURL: URL(string: "https://nas.local:5006/dav/LucentBackups/")!
    )
    check(parsedItems.count == 2 && parsedItems[0].fileName == "lucent-backup-20261113-113000.lucentbackup" && parsedItems[0].sizeBytes == 2048, "207 XML parser verified")

    try verifyWebDAVClientWithMockProtocol(archiveData: archiveData, expectedSHA256: summary.payloadSHA256)
    print("[ok] v0.7.0 BackupArchiveService (SHA-256 + Path Security + Plugins/Clipboard) & Native WebDAVClient + Keychain")
}
