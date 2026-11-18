import Foundation
import Testing
@testable import LucentCore

@Suite("General Preferences, Launch at Login, Clipboard Privacy & Excluded Index Paths")
struct LucentGeneralPreferencesTests {
    @Test("GeneralPreferences persistence, partial JSON schema tolerance & Backup v2 automatic inclusion")
    func generalPreferencesPersistenceAndBackup() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-prefs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let cfgURL = GeneralPreferences.defaultConfigURL(appSupportDirectory: tmp)
        let partialJSON = Data(#"{"showDockIcon": true, "clipboardMaxUnpinned": 200}"#.utf8)
        try partialJSON.write(to: cfgURL)

        var prefs = GeneralPreferences.load(from: cfgURL)
        #expect(prefs.showDockIcon == true)
        #expect(prefs.clipboardMaxUnpinned == 200)
        #expect(prefs.launchSilentlyInMenuBar == false)
        #expect(prefs.showLaunchIntroAnimation == true)
        #expect(prefs.queryClearPolicy == .afterIdle30s)
        #expect(prefs.overlayScreenTarget == .cursorScreen)

        prefs.launchSilentlyInMenuBar = true
        prefs.showLaunchIntroAnimation = false
        prefs.defaultEverythingScope = .volume(name: "DataSSD", mountPath: "/Volumes/DataSSD")
        prefs.overlayScreenTarget = .focusedWindowScreen
        prefs.savedOverlayTopCenter = PersistedOverlayAnchor(x: 720, y: 900)
        prefs.menuBarIconStyle = .prism3D
        prefs.clipboardRetentionTTL = .days7
        prefs.toggleExcludedApp(bundleID: "com.apple.Terminal")
        prefs.toggleExcludedApp(bundleID: "com.googlecode.iterm2")
        prefs.quickSaveCaptureWithoutDialog = true
        prefs.screenshotExcludeWindowShadow = true
        prefs.gifDefaultOptions = GifRecordingOptions(fps: 20, maxDimension: 1280)
        prefs.addExcludedIndexPath("/Volumes/DataSSD/LargeCache")
        prefs.save(to: cfgURL, notify: false)

        let reloaded = GeneralPreferences.load(from: cfgURL)
        #expect(reloaded == prefs)
        #expect(reloaded.isAppExcludedFromClipboard(bundleID: "COM.APPLE.TERMINAL") == true)
        #expect(reloaded.excludedIndexPaths == ["/Volumes/DataSSD/LargeCache"])

        // Verify BackupArchiveService automatically includes general-preferences.json
        let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let summary = try BackupArchiveService.inspectBackupData(archive)
        #expect(summary.configFileNames.contains(GeneralPreferences.fileName))

        let status = LaunchAtLoginService.currentStatus()
        #expect([LaunchAtLoginStatus.enabled, .notRegistered, .requiresApproval, .notFound].contains(status))
        #expect(LaunchAtLoginService.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/Applications/Lucent.app")) == true)
        #expect(LaunchAtLoginService.isInstalledInApplications(bundleURL: URL(fileURLWithPath: "/tmp/Lucent.app")) == false)
    }

    @Test("ClipboardService app exclusion, unpinned capacity cap & TTL expiration preserve pinned entries")
    func clipboardPrivacyBlacklistCapacityAndTTL() throws {
        let excluded = ["com.apple.Terminal", "com.tencent.xinWeChat"]
        #expect(ClipboardService.shouldIgnoreSourceApp(bundleIdentifier: "com.apple.terminal", excludedBundleIDs: excluded) == true)
        #expect(ClipboardService.shouldIgnoreSourceApp(bundleIdentifier: "com.apple.Safari", excludedBundleIDs: excluded) == false)
        #expect(ClipboardService.shouldIgnoreSourceApp(bundleIdentifier: nil, excludedBundleIDs: excluded) == false)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiredPinned = ClipboardEntry(
            title: "Pinned Secret Note", subtitle: "Pinned", textValue: "pinned-forever",
            capturedAt: now.addingTimeInterval(-86_400 * 90), isPinned: true, payloadKind: .text
        )
        let expiredUnpinned = ClipboardEntry(
            title: "Old Copy", subtitle: "Old", textValue: "expired-text",
            capturedAt: now.addingTimeInterval(-86_400 * 2), isPinned: false, payloadKind: .text
        )
        let fresh1 = ClipboardEntry(
            title: "Fresh 1", subtitle: "Recent", textValue: "fresh-1",
            capturedAt: now.addingTimeInterval(-600), isPinned: false, payloadKind: .text
        )
        let fresh2 = ClipboardEntry(
            title: "Fresh 2", subtitle: "Recent", textValue: "fresh-2",
            capturedAt: now.addingTimeInterval(-300), isPinned: false, payloadKind: .text
        )
        let fresh3 = ClipboardEntry(
            title: "Fresh 3", subtitle: "Recent", textValue: "fresh-3",
            capturedAt: now, isPinned: false, payloadKind: .text
        )

        var list: [ClipboardEntry] = [expiredPinned, fresh2, fresh1, expiredUnpinned]
        list = ClipboardService.insert(fresh3, into: list, maxUnpinned: 2, ttl: .hours24, now: now)

        #expect(list.contains(where: { $0.textValue == "pinned-forever" && $0.isPinned }))
        #expect(!list.contains(where: { $0.textValue == "expired-text" }))
        #expect(!list.contains(where: { $0.textValue == "fresh-1" }))
        #expect(list.filter { !$0.isPinned }.map(\.textValue) == ["fresh-3", "fresh-2"])
    }

    @Test("EverythingIndex custom excluded directory paths work on initial build and FSEvents updates")
    func everythingIndexCustomExcludedPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-idx-excl-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keepDir = root.appendingPathComponent("Projects", isDirectory: true)
        let skipDir = root.appendingPathComponent("HeavyArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skipDir, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: keepDir.appendingPathComponent("readme.md"))
        try Data("skip".utf8).write(to: skipDir.appendingPathComponent("secret-dump.bin"))

        let excluded: Set<String> = [skipDir.standardizedFileURL.path]
        let idx = try EverythingIndex.build(rootURL: root, excludedPaths: excluded)
        let hitsKeep = idx.search(queryText: "readme.md", limit: 10)
        let hitsSkip = idx.search(queryText: "secret-dump", limit: 10)
        #expect(hitsKeep.count == 1)
        #expect(hitsSkip.isEmpty)

        // Verify FSEvents incremental update also honors excludedPaths
        try Data("new".utf8).write(to: skipDir.appendingPathComponent("later-added.bin"))
        try Data("new-keep".utf8).write(to: keepDir.appendingPathComponent("notes.txt"))
        let updated = idx.applyingFSEventDirectories(
            [keepDir.path, skipDir.path],
            excludedPaths: excluded
        )
        #expect(updated.search(queryText: "notes.txt", limit: 10).count == 1)
        #expect(updated.search(queryText: "later-added", limit: 10).isEmpty)
    }
}
