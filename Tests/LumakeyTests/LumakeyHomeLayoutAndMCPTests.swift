import Foundation
import Testing
@testable import LumakeyCore

@Suite("Customizable Launcher Home Layout, Multi-Scene Profiles, Security & Backup")
struct LumakeyHomeLayoutAndMCPTests {
    @Test("HomeLaunchTarget flat JSON serialization & HomeLaunchSecurity scheme/path whitelist")
    func launchTargetSerializationAndSecurity() throws {
        let validItems: [HomeLaunchItem] = [
            HomeLaunchItem(id: "b1", target: .builtin(.fileWorkspace)),
            HomeLaunchItem(id: "a1", target: .nativeApp(path: "/System/Applications/Calculator.app", bundleID: "com.apple.calculator")),
            HomeLaunchItem(id: "p1", target: .plugin(pluginID: "quick-remind", behavior: .openWindow)),
            HomeLaunchItem(id: "c1", target: .pluginCommand(pluginID: "notion-bookmarks", commandID: "add-clipboard", arguments: ["--sync"])),
            HomeLaunchItem(id: "u1", target: .bookmark(url: "https://github.com/lengsukq/Lumakey", browserAppPath: "/Applications/Safari.app", sourcePluginID: "browser-hub")),
            HomeLaunchItem(id: "u2", target: .bookmark(url: "vscode://file/Users/demo/project")),
            HomeLaunchItem(id: "l1", target: .localPath(path: "/Users/demo/Documents")),
            HomeLaunchItem(id: "q1", target: .queryChip(query: "ext:swift", filter: "files"))
        ]

        for item in validItems {
            #expect(HomeLaunchSecurity.validateItem(item) == nil)
        }

        let encoded = try JSONEncoder().encode(validItems)
        let decoded = try JSONDecoder().decode([HomeLaunchItem].self, from: encoded)
        #expect(decoded == validItems)

        // Reject unsafe schemes, non-.app bundles, path traversal plugin IDs & invalid filters
        let jsBookmark = HomeLaunchItem(id: "bad-js", target: .bookmark(url: "javascript:alert(1)"))
        #expect(HomeLaunchSecurity.validateItem(jsBookmark) != nil)

        let fileSchemeBookmark = HomeLaunchItem(id: "bad-file", target: .bookmark(url: "file:///etc/passwd"))
        #expect(HomeLaunchSecurity.validateItem(fileSchemeBookmark) != nil)

        let badApp = HomeLaunchItem(id: "bad-app", target: .nativeApp(path: "/usr/bin/curl"))
        #expect(HomeLaunchSecurity.validateItem(badApp) != nil)

        let badPlugin = HomeLaunchItem(id: "bad-plug", target: .plugin(pluginID: "../escape"))
        #expect(HomeLaunchSecurity.validateItem(badPlugin) != nil)

        let badChipFilter = HomeLaunchItem(id: "bad-chip", target: .queryChip(query: "hello", filter: "unknown"))
        #expect(HomeLaunchSecurity.validateItem(badChipFilter) != nil)
    }

    @Test("Multi-scene HomeProfile lifecycle, presets, item reordering, undo & Backup v2 round-trip")
    func multiProfilePresetsUndoAndBackupRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let cfgURL = HomeLayoutConfig.defaultConfigURL(appSupportDirectory: tmp)
        var cfg = HomeLayoutConfig.loadOrBootstrap(
            from: cfgURL,
            legacyPinnedAppIDs: ["/System/Applications/Calculator.app", "/System/Library/CoreServices/Finder.app"]
        )
        #expect(cfg.profiles.count == 1)
        #expect(cfg.activeProfile.dockItems.count == 2)
        #expect(cfg.migratedLegacyPinnedApps == true)

        // Cannot delete the last remaining profile
        #expect(throws: HomeLayoutError.cannotDeleteLastProfile) {
            _ = try cfg.deleteProfile(id: cfg.activeProfileID)
        }

        // Create a second "work" profile with developer preset
        let work = try cfg.createProfile(id: "work", name: "工作模式", symbol: "hammer.fill", preset: .developer, activate: true)
        #expect(cfg.activeProfileID == "work")
        #expect(work.pillShelves.contains(where: { $0.id == "dev-bookmarks" }))

        // Upsert mixed items into Bento, Dock, and a new custom shelf
        let customPluginTile = HomeLaunchItem(
            id: "tile-quick-remind",
            target: .plugin(pluginID: "quick-remind", behavior: .openWindow),
            customTitle: "闪电提醒看板",
            accentColor: "mint"
        )
        try cfg.upsertItem(customPluginTile, in: .bento, at: 0)
        #expect(cfg.activeProfile.bentoItems.first?.id == "tile-quick-remind")

        let moved = cfg.moveItem(id: "tile-quick-remind", in: .bento, offset: 1)
        #expect(moved == true)
        #expect(cfg.activeProfile.bentoItems[1].id == "tile-quick-remind")

        let docBookmark = HomeLaunchItem(
            id: "bm-docs",
            target: .bookmark(url: "https://developer.apple.com/documentation/swift"),
            customTitle: "Swift Docs",
            accentColor: "orange"
        )
        try cfg.upsertItem(docBookmark, in: .shelf("team-links"), shelfTitle: "团队书签")
        #expect(cfg.activeProfile.pillShelves.contains(where: { $0.id == "team-links" && $0.title == "团队书签" }))

        // Apply minimal preset & verify undo restores previous profile state
        let countBeforePreset = cfg.activeProfile.bentoItems.count
        cfg.applyPreset(.minimal, preserveDockItems: true)
        #expect(!cfg.activeProfile.isSectionVisible(.bentoGrid))
        #expect(cfg.activeProfile.dockRows == 2)
        #expect(cfg.undoLastChange() == true)
        #expect(cfg.activeProfile.isSectionVisible(.bentoGrid))
        #expect(cfg.activeProfile.bentoItems.count == countBeforePreset)

        cfg.save(to: cfgURL, notifyInProcess: false, notifyCrossProcess: false)

        // Verify BackupArchiveService automatically includes & restores home-layout.json
        let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let summary = try BackupArchiveService.inspectBackupData(archive)
        #expect(summary.configFileNames.contains(HomeLayoutConfig.fileName))

        let dst = tmp.appendingPathComponent("RestoredSupport", isDirectory: true)
        let report = try BackupArchiveService.restoreBackupData(archive, appSupportDirectory: dst)
        #expect(report.restoredConfigFileNames.contains(HomeLayoutConfig.fileName))

        let restoredCfg = HomeLayoutConfig.loadOrBootstrap(from: HomeLayoutConfig.defaultConfigURL(appSupportDirectory: dst))
        #expect(restoredCfg.activeProfileID == "work")
        #expect(restoredCfg.profiles.count == 2)
        #expect(restoredCfg.activeProfile.pillShelves.contains(where: { $0.id == "team-links" }))
    }
}
