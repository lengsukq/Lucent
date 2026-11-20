import Foundation
import Testing
@testable import LucentCore

@Suite("Floating Window Session Persistence & Launch Intro Presentation Policy")
struct LucentFloatingSessionAndLaunchTests {
    @Test("FloatingWindowSessionStore persists, caps, filters oversized inline HTML, and prunes orphan pin files")
    func floatingSessionStorePersistenceAndPruning() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-float-sess-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let sessionURL = FloatingWindowSessionStore.defaultURL(appSupportDirectory: tmp)
        let pinDir = FloatingWindowSessionStore.pinnedSessionDirectory(appSupportDirectory: tmp)
        try FileManager.default.createDirectory(at: pinDir, withIntermediateDirectories: true)

        // 1. Plugin custom windows: valid relative htmlPath persists with x/y stripped; oversized inline HTML is rejected.
        let validSpec = PluginCustomWindowSpec(
            pluginID: "antigravity-pulse",
            windowID: "antigravity-pulse-hud",
            title: "Antigravity Pulse",
            htmlPath: "ui/widget.html",
            width: 180,
            height: 96,
            resizable: false,
            chrome: .frameless,
            transparent: true,
            pinOnTop: true,
            clickThrough: false,
            showInDock: false,
            opacity: 0.96,
            x: 1600,
            y: 660
        )
        let hugeInlineSpec = PluginCustomWindowSpec(
            pluginID: "oversized-demo",
            windowID: "main",
            html: String(repeating: "A", count: PersistedPluginCustomWindow.maxInlineHTMLBytes + 128)
        )
        let validEntry = PersistedPluginCustomWindow(
            pluginID: validSpec.pluginID,
            windowID: validSpec.windowID,
            spec: validSpec
        )
        let hugeEntry = PersistedPluginCustomWindow(
            pluginID: hugeInlineSpec.pluginID,
            windowID: hugeInlineSpec.windowID,
            spec: hugeInlineSpec
        )
        #expect(validEntry.isPersistable == true)
        #expect(validEntry.spec.x == nil)
        #expect(validEntry.spec.y == nil)
        #expect(hugeEntry.isPersistable == false)

        FloatingWindowSessionStore.replacePluginCustomWindows([validEntry, hugeEntry], at: sessionURL)
        let loadedAfterCustom = FloatingWindowSessionStore.load(from: sessionURL)
        #expect(loadedAfterCustom.pluginCustomWindows.count == 1)
        #expect(loadedAfterCustom.pluginCustomWindows.first?.pluginID == "antigravity-pulse")
        #expect(loadedAfterCustom.pluginCustomWindows.first?.windowID == "antigravity-pulse-hud")
        #expect(loadedAfterCustom.pluginCustomWindows.first?.spec.showInDock == false)

        // 2. Plugin native floating panels: upsert deduplicates by pluginID and remove deletes cleanly.
        let panelA = PluginFloatingPanelRequest(pluginID: "gold-monitor", pinOnTop: true, refreshIntervalSeconds: 30)
        let panelAUpdated = PluginFloatingPanelRequest(pluginID: "gold-monitor", pinOnTop: false, refreshIntervalSeconds: 60)
        let panelB = PluginFloatingPanelRequest(pluginID: "quick-remind", pinOnTop: true, refreshIntervalSeconds: 15)
        FloatingWindowSessionStore.upsertPluginFloatingPanel(panelA, at: sessionURL)
        FloatingWindowSessionStore.upsertPluginFloatingPanel(panelB, at: sessionURL)
        FloatingWindowSessionStore.upsertPluginFloatingPanel(panelAUpdated, at: sessionURL)

        let loadedPanels = FloatingWindowSessionStore.load(from: sessionURL).pluginFloatingPanels
        #expect(loadedPanels.count == 2)
        #expect(loadedPanels.first(where: { $0.pluginID == "gold-monitor" })?.refreshIntervalSeconds == 60)
        #expect(loadedPanels.first(where: { $0.pluginID == "gold-monitor" })?.pinOnTop == false)

        FloatingWindowSessionStore.removePluginFloatingPanel(pluginID: "quick-remind", at: sessionURL)
        #expect(FloatingWindowSessionStore.load(from: sessionURL).pluginFloatingPanels.map(\.pluginID) == ["gold-monitor"])

        // 3. Pinned image windows + orphan file pruning.
        let keepFile = pinDir.appendingPathComponent("pin-keep.png")
        let orphanFile = pinDir.appendingPathComponent("pin-orphan.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: keepFile)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: orphanFile)

        let pinRecord = PersistedPinnedImageWindow(
            id: "keep",
            imagePath: keepFile.path,
            isManagedSessionCopy: true,
            isCutout: false,
            x: 120,
            y: 240,
            width: 360,
            height: 220,
            opacity: 0.85,
            isClickThrough: true
        )
        FloatingWindowSessionStore.replacePinnedImages([pinRecord], at: sessionURL)
        let loadedPins = FloatingWindowSessionStore.load(from: sessionURL).pinnedImages
        #expect(loadedPins.count == 1)
        #expect(loadedPins.first?.isClickThrough == true)
        #expect(loadedPins.first?.opacity == 0.85)

        FloatingWindowSessionStore.pruneOrphanPinnedFiles(keeping: [keepFile.path], in: pinDir)
        #expect(FileManager.default.fileExists(atPath: keepFile.path) == true)
        #expect(FileManager.default.fileExists(atPath: orphanFile.path) == false)

        // 4. File shelf plugin IDs persist, deduplicate, reject unsafe IDs, and remove cleanly.
        FloatingWindowSessionStore.upsertFileShelf(pluginID: "file-shelf", at: sessionURL)
        FloatingWindowSessionStore.upsertFileShelf(pluginID: "file-shelf", at: sessionURL)
        FloatingWindowSessionStore.upsertFileShelf(pluginID: "../escape", at: sessionURL)
        #expect(FloatingWindowSessionStore.load(from: sessionURL).fileShelfPluginIDs == ["file-shelf"])
        FloatingWindowSessionStore.removeFileShelf(pluginID: "file-shelf", at: sessionURL)
        #expect(FloatingWindowSessionStore.load(from: sessionURL).fileShelfPluginIDs.isEmpty)
    }

    @Test("GeneralPreferences.restoreFloatingWindowsOnLaunch defaults true and decodes legacy JSON safely")
    func generalPreferencesRestoreFloatingFlagCompatibility() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-restore-flag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let url = GeneralPreferences.defaultConfigURL(appSupportDirectory: tmp)
        let legacyJSON = Data(#"{"launchSilentlyInMenuBar": true, "showLaunchIntroAnimation": true}"#.utf8)
        try legacyJSON.write(to: url)

        var loaded = GeneralPreferences.load(from: url)
        #expect(loaded.restoreFloatingWindowsOnLaunch == true)

        loaded.restoreFloatingWindowsOnLaunch = false
        loaded.save(to: url, notify: false)
        #expect(GeneralPreferences.load(from: url).restoreFloatingWindowsOnLaunch == false)
    }

    @Test("LaunchPresentationPolicy plays intro on cold launch whenever enabled, independent of silent menu-bar mode")
    func launchPresentationPolicyTruthTable() {
        // Intro enabled + normal launch -> play intro then show launcher
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: false,
                showLaunchIntroAnimation: true,
                reduceMotion: false
            ) == .playIntroThenShowLauncher
        )

        // Intro enabled + silent menu-bar mode -> still play intro on cold launch, then stay in menu bar
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: true,
                showLaunchIntroAnimation: true,
                reduceMotion: false
            ) == .playIntroThenStaySilent
        )

        // Intro disabled + silent menu-bar mode -> fully silent
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: true,
                showLaunchIntroAnimation: false,
                reduceMotion: false
            ) == .silent
        )

        // Intro disabled + normal launch -> show launcher immediately
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: false,
                showLaunchIntroAnimation: false,
                reduceMotion: false
            ) == .showLauncherImmediately
        )

        // System Reduce Motion disables intro while honoring silent menu-bar preference
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: true,
                showLaunchIntroAnimation: true,
                reduceMotion: true
            ) == .silent
        )
        #expect(
            LaunchPresentationPolicy.resolve(
                launchSilentlyInMenuBar: false,
                showLaunchIntroAnimation: true,
                reduceMotion: true
            ) == .showLauncherImmediately
        )
    }
}
