import Foundation
import Testing
@testable import LucentCore

@Suite("Adaptive Search Frequency & Query Affinity Ranking (Smarter Every Click)")
struct LucentSearchAffinityTests {
    @Test("SearchAffinityStore ranks more-clicked and more-recent items higher with exact and prefix query affinity")
    func frecencyAndQueryAffinityScoring() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-affinity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let url = SearchAffinityStore.defaultStorageURL(appSupportDirectory: tmp)
        let store = SearchAffinityStore(storageURL: url, debounceNanoseconds: 0)

        let baseTime = Date(timeIntervalSince1970: 1_800_000_000)
        let appA = InstalledAppItem(name: "GoldNote", englishName: "GoldNote", url: URL(fileURLWithPath: "/Applications/GoldNote.app"))
        let appB = InstalledAppItem(name: "GoldStudio", englishName: "GoldStudio", url: URL(fileURLWithPath: "/Applications/GoldStudio.app"))
        let candA = LauncherCandidate(id: appA.id, score: 9_150, kind: .app(appA))
        let candB = LauncherCandidate(id: appB.id, score: 9_150, kind: .app(appB))

        // Click appB multiple times under query "gold"
        store.recordSelection(candidate: candB, query: "gold", now: baseTime)
        store.recordSelection(candidate: candB, query: "gold", now: baseTime.addingTimeInterval(60))
        store.recordSelection(candidate: candB, query: "gold", now: baseTime.addingTimeInterval(120))
        // Click appA once 30 days ago under query "gold"
        store.recordSelection(candidate: candA, query: "gold", now: baseTime.addingTimeInterval(-30 * 86_400))

        let exactBoosts = store.boosts(forQuery: "gold", now: baseTime.addingTimeInterval(180))
        let keyA = try #require(SearchAffinityStore.affinityKey(for: candA))
        let keyB = try #require(SearchAffinityStore.affinityKey(for: candB))
        #expect((exactBoosts[keyB] ?? 0) > (exactBoosts[keyA] ?? 0))
        #expect((exactBoosts[keyB] ?? 0) <= SearchAffinityStore.maxTotalBoost)

        // Prefix generalization: typing "go" still boosts appB learned under "gold"
        let prefixBoosts = store.boosts(forQuery: "go", now: baseTime.addingTimeInterval(180))
        #expect((prefixBoosts[keyB] ?? 0) > (prefixBoosts[keyA] ?? 0))

        // Persistence round-trip + Backup v2 automatic inclusion
        store.flush()
        let reloaded = SearchAffinityStore(storageURL: url, debounceNanoseconds: 0)
        #expect(reloaded.learnedItemCount == 2)
        #expect(reloaded.clickCount(for: candB) == 3)

        let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let summary = try BackupArchiveService.inspectBackupData(archive)
        #expect(summary.configFileNames.contains(SearchAffinityStore.fileName))

        // Reset single item & clear all
        reloaded.resetItem(for: candB)
        #expect(reloaded.clickCount(for: candB) == 0)
        #expect(reloaded.clickCount(for: candA) == 1)
        reloaded.clearAll()
        #expect(reloaded.learnedItemCount == 0)
        #expect(reloaded.learnedQueryCount == 0)
    }

    @Test("LauncherEngine promotes frequently clicked candidates across types when affinityBoosts are supplied")
    func launcherEnginePromotesClickedCandidates() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-affinity-rank-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let store = SearchAffinityStore(
            storageURL: SearchAffinityStore.defaultStorageURL(appSupportDirectory: tmp),
            debounceNanoseconds: 0
        )

        let appAlpha = InstalledAppItem(name: "AlphaNote", englishName: "AlphaNote", url: URL(fileURLWithPath: "/Applications/AlphaNote.app"))
        let appZeta = InstalledAppItem(name: "AlphaZeta", englishName: "AlphaZeta", url: URL(fileURLWithPath: "/Applications/AlphaZeta.app"))

        let baseline = LauncherEngine.rankCandidates(
            query: "alpha",
            filter: .all,
            apps: [appAlpha, appZeta],
            plugins: []
        )
        #expect(baseline.first?.id == appAlpha.id)

        // Click AlphaZeta twice under "alpha" -> it should jump ahead of AlphaNote!
        let zetaCand = LauncherCandidate(id: appZeta.id, score: 0, kind: .app(appZeta))
        let now = Date()
        store.recordSelection(candidate: zetaCand, query: "alpha", now: now)
        store.recordSelection(candidate: zetaCand, query: "alpha", now: now.addingTimeInterval(5))

        let boosted = LauncherEngine.rankCandidates(
            query: "alpha",
            filter: .all,
            apps: [appAlpha, appZeta],
            plugins: [],
            affinityBoosts: store.boosts(forQuery: "alpha", now: now.addingTimeInterval(10))
        )
        #expect(boosted.first?.id == appZeta.id)

        // Prefix "al" also promotes AlphaZeta
        let prefixBoosted = LauncherEngine.rankCandidates(
            query: "al",
            filter: .all,
            apps: [appAlpha, appZeta],
            plugins: [],
            affinityBoosts: store.boosts(forQuery: "al", now: now.addingTimeInterval(10))
        )
        #expect(prefixBoosted.first?.id == appZeta.id)
    }

    @Test("Privacy boundaries exclude clipboard, calculator, dev tools, and dynamic commands from learning")
    func privacyExclusionsAndLegacyPreferenceDefault() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-affinity-priv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let store = SearchAffinityStore(
            storageURL: SearchAffinityStore.defaultStorageURL(appSupportDirectory: tmp),
            debounceNanoseconds: 0
        )

        let calcCand = LauncherCandidate(
            id: "calc:2+2",
            score: 10_000,
            kind: .calculator(expression: "2+2", resultText: "4", badgeLabel: "Math")
        )
        let clipEntry = ClipboardEntry(
            title: "Secret Paste",
            subtitle: "Text",
            textValue: "super-secret-value",
            payloadKind: .text
        )
        let clipCand = LauncherCandidate(id: "clip:\(clipEntry.id.uuidString)", score: 9_300, kind: .clipboard(clipEntry))
        let webCmd = CommandSuggestion(
            id: "web:google:hello",
            score: 7_000,
            title: "Search Google",
            subtitle: "hello",
            badgeLabel: "Web",
            symbol: "magnifyingglass",
            command: .webSearch(engine: "Google", url: URL(string: "https://example.com")!)
        )
        let webCand = LauncherCandidate(id: webCmd.id, score: webCmd.score, kind: .command(webCmd))
        let staticCmd = CommandSuggestion(
            id: "cmd:settings",
            score: 8_200,
            title: "Settings",
            subtitle: "Open Settings",
            badgeLabel: "System",
            symbol: "gearshape",
            command: .openSettings
        )
        let staticCand = LauncherCandidate(id: staticCmd.id, score: staticCmd.score, kind: .command(staticCmd))

        store.recordSelection(candidate: calcCand, query: "2+2")
        store.recordSelection(candidate: clipCand, query: "secret")
        store.recordSelection(candidate: webCand, query: "g hello")
        store.recordSelection(candidate: staticCand, query: "set")

        #expect(store.learnedItemCount == 1)
        #expect(store.clickCount(for: staticCand) == 1)
        #expect(store.clickCount(for: clipCand) == 0)
        #expect(store.clickCount(for: calcCand) == 0)
        #expect(store.clickCount(for: webCand) == 0)

        // Legacy GeneralPreferences JSON defaults enableSmartSearchRanking to true
        let prefURL = GeneralPreferences.defaultConfigURL(appSupportDirectory: tmp)
        try Data(#"{"showDockIcon": false}"#.utf8).write(to: prefURL)
        #expect(GeneralPreferences.load(from: prefURL).enableSmartSearchRanking == true)
    }
}
