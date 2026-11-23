import Darwin
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentSearch

@Suite("Live App Discovery & Snapshot Reconciliation Tests")
struct LucentLiveAppAndIndexCatchUpTests {
    private func makeIsolatedDir(_ name: String) throws -> URL {
        let rawDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-catchup-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        return rawDir.resolvingSymlinksInPath().standardizedFileURL
    }

    private func createMockAppBundle(
        at appURL: URL,
        infoDisplayName: String? = nil,
        zhStringsDisplayName: String? = nil
    ) throws {
        let fm = FileManager.default
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        var infoDict: [String: Any] = [
            "CFBundleIdentifier": "test.\(UUID().uuidString)",
            "CFBundleName": appURL.deletingPathExtension().lastPathComponent
        ]
        if let infoDisplayName {
            infoDict["CFBundleDisplayName"] = infoDisplayName
        }
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoDict, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        if let zhStringsDisplayName {
            let zhDir = resources.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
            try fm.createDirectory(at: zhDir, withIntermediateDirectories: true)
            let content = "\"CFBundleDisplayName\" = \"\(zhStringsDisplayName)\";\n"
            try Data(content.utf8).write(to: zhDir.appendingPathComponent("InfoPlist.strings"))
        }
    }

    @Test("App discovery scans 2nd-level subfolders, resolves InfoPlist.strings & Info.plist names, and tracks directory fingerprints")
    func appDiscoverySubfoldersLocalizationAndFingerprints() throws {
        let workspace = try makeIsolatedDir("apps")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let systemApps = workspace.appendingPathComponent("Applications", isDirectory: true)
        let lateUserApps = workspace.appendingPathComponent("UserApplications", isDirectory: true)
        try FileManager.default.createDirectory(at: systemApps, withIntermediateDirectories: true)

        try createMockAppBundle(
            at: systemApps.appendingPathComponent("SketchPad.app", isDirectory: true),
            zhStringsDisplayName: "流光画板"
        )
        let toolboxDir = systemApps.appendingPathComponent("JetBrains Toolbox", isDirectory: true)
        try FileManager.default.createDirectory(at: toolboxDir, withIntermediateDirectories: true)
        try createMockAppBundle(
            at: toolboxDir.appendingPathComponent("DataGrip.app", isDirectory: true),
            infoDisplayName: "DataGrip IDE"
        )

        let frameworkDir = systemApps.appendingPathComponent("Vendor.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        try createMockAppBundle(at: frameworkDir.appendingPathComponent("EmbeddedHelper.app", isDirectory: true))

        try FileManager.default.createSymbolicLink(
            at: systemApps.appendingPathComponent("SketchPadAlias.app"),
            withDestinationURL: systemApps.appendingPathComponent("SketchPad.app")
        )

        let roots = [systemApps, lateUserApps]
        let fpInitial = LauncherEngine.applicationDirectoriesFingerprint(roots: roots)
        let initialApps = LauncherEngine.discoverInstalledApps(roots: roots)

        #expect(initialApps.count == 2)
        #expect(initialApps.contains { $0.name == "流光画板" && $0.englishName == "SketchPad" })
        #expect(initialApps.contains { $0.name == "DataGrip IDE" && $0.englishName == "DataGrip" })
        #expect(!initialApps.contains { $0.englishName == "EmbeddedHelper" })

        let zhRanked = LauncherEngine.rankCandidates(query: "lghb", filter: .all, apps: initialApps, plugins: [])
        #expect(zhRanked.first?.id.hasSuffix("SketchPad.app") == true)
        let enRanked = LauncherEngine.rankCandidates(query: "datagrip", filter: .all, apps: initialApps, plugins: [])
        #expect(enRanked.first?.id.hasSuffix("DataGrip.app") == true)

        // Simulate installing a new app inside an existing 2nd-level subfolder
        try createMockAppBundle(at: toolboxDir.appendingPathComponent("RustRover.app", isDirectory: true))
        let fpAfterSubfolderInstall = LauncherEngine.applicationDirectoriesFingerprint(roots: roots)
        #expect(fpAfterSubfolderInstall != fpInitial)
        let afterSubfolderApps = LauncherEngine.discoverInstalledApps(roots: roots)
        #expect(afterSubfolderApps.contains { $0.englishName == "RustRover" })

        // Simulate ~/Applications being created for the first time while app is running
        try FileManager.default.createDirectory(at: lateUserApps, withIntermediateDirectories: true)
        try createMockAppBundle(
            at: lateUserApps.appendingPathComponent("LocalStudio.app", isDirectory: true),
            zhStringsDisplayName: "本地工坊"
        )
        let fpAfterUserAppsCreated = LauncherEngine.applicationDirectoriesFingerprint(roots: roots)
        #expect(fpAfterUserAppsCreated != fpAfterSubfolderInstall)
        let finalApps = LauncherEngine.discoverInstalledApps(roots: roots)
        #expect(finalApps.contains { $0.name == "本地工坊" && $0.englishName == "LocalStudio" })
    }

    @Test("LCNTIDX4 persists lastEventId and offline snapshot reconciliation catches newly created files, nested folders, and deletions")
    func offlineSnapshotReconciliationCatchesMissedFileChanges() throws {
        let root = try makeIsolatedDir("offline-reconcile")
        defer { try? FileManager.default.removeItem(at: root) }

        let scanRoot = root.appendingPathComponent("Home", isDirectory: true)
        let downloads = scanRoot.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = scanRoot.appendingPathComponent("Desktop", isDirectory: true)
        let removableDir = scanRoot.appendingPathComponent("OldScratch", isDirectory: true)
        let cacheDir = root.appendingPathComponent("IndexCache", isDirectory: true)
        for dir in [downloads, desktop, removableDir, cacheDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let transientFile = downloads.appendingPathComponent("ephemeral_old.txt")
        try Data("old".utf8).write(to: transientFile)
        try Data("scratch".utf8).write(to: removableDir.appendingPathComponent("gone.tmp"))

        let expectedEventId = max(EverythingFSEventWatcher.currentEventId(), 987_654_321)
        let initialIndex = try EverythingIndex.build(rootURLs: [scanRoot], maxNodes: 5_000)
            .withUpdatedEventId(expectedEventId)
        #expect(initialIndex.search(queryText: "ephemeral_old.txt").count == 1)

        let scopeKey = "unit-reconcile"
        let savedURL = try #require(EverythingSnapshotStore.save(initialIndex, scopeKey: scopeKey, cacheDirectory: cacheDir))
        #expect(FileManager.default.fileExists(atPath: savedURL.path))

        let header = try #require(EverythingSnapshotStore.readHeaderMetadata(
            scopeKey: scopeKey, expectedRoots: [scanRoot], cacheDirectory: cacheDir
        ))
        #expect(header.lastEventId == expectedEventId)

        // Simulate app closed / watcher unloaded while filesystem mutates:
        try FileManager.default.removeItem(at: transientFile)
        try FileManager.default.removeItem(at: removableDir)
        try Data("fresh-pdf".utf8).write(to: downloads.appendingPathComponent("newly_generated_invoice.pdf"))
        let nestedDir = desktop.appendingPathComponent("Sprint24/Deliverables", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try Data("spec".utf8).write(to: nestedDir.appendingPathComponent("architecture_plan.md"))

        let reloadedStale = try #require(EverythingSnapshotStore.load(
            scopeKey: scopeKey, expectedRoots: [scanRoot], cacheDirectory: cacheDir
        ))
        #expect(reloadedStale.lastEventId == expectedEventId)
        #expect(reloadedStale.search(queryText: "newly_generated_invoice.pdf").isEmpty)

        let reconciled = reloadedStale.reconcilingFilesystemChangesSinceSnapshot()
        #expect(reconciled.search(queryText: "newly_generated_invoice.pdf").count == 1)
        #expect(reconciled.search(queryText: "architecture_plan.md").count == 1)
        #expect(reconciled.search(queryText: "ephemeral_old.txt").isEmpty)
        #expect(reconciled.search(queryText: "gone.tmp").isEmpty)
        #expect(reconciled.lastEventId >= expectedEventId)
    }

    @Test("Dirty-directory & recursive-subtree batch sync merges changes accumulated while index was unloaded")
    func dirtyBatchAndRecursiveSubtreeSync() async throws {
        let root = try makeIsolatedDir("idle-dirty")
        defer { try? FileManager.default.removeItem(at: root) }

        let scanRoot = root.appendingPathComponent("Workspace", isDirectory: true)
        let exportsDir = scanRoot.appendingPathComponent("Exports", isDirectory: true)
        let coalescedNested = scanRoot.appendingPathComponent("Coalesced/ExistingChild", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coalescedNested, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: exportsDir.appendingPathComponent("seed.txt"))

        let snapshotIndex = try EverythingIndex.build(rootURLs: [scanRoot], maxNodes: 1_000)

        // Mutate both a direct watched directory and a deep existing child under a MustScanSubDirs parent
        try Data("v2".utf8).write(to: exportsDir.appendingPathComponent("live_created_export.csv"))
        try Data("deep".utf8).write(to: coalescedNested.appendingPathComponent("deep_coalesced.json"))

        let batch = EverythingFSEventBatch(
            directories: [exportsDir.path],
            recursiveDirectories: [scanRoot.appendingPathComponent("Coalesced").path],
            latestEventId: 42_000,
            isHistoricalReplay: false
        )
        let merged = snapshotIndex.applyingFSEventDirectories(
            batch.directories,
            recursiveSubtreeDirs: batch.recursiveDirectories,
            latestEventId: batch.latestEventId
        )
        #expect(merged.search(queryText: "live_created_export.csv").count == 1)
        #expect(merged.search(queryText: "deep_coalesced.json").count == 1)
        #expect(merged.lastEventId >= 42_000)

        // When com.apple.FSEvents Mach IPC is available (outside strict seatbelt sandboxes), verify live stream too
        if EverythingFSEventWatcher.currentEventId() > 0 {
            let collector = DirtyBatchCollector()
            let watcher = EverythingFSEventWatcher(roots: [scanRoot], debounceInterval: 0.1) { liveBatch in
                collector.record(liveBatch)
            }
            defer { watcher?.stop() }
            try Data("v3".utf8).write(to: exportsDir.appendingPathComponent("stream_live_probe.txt"))
            var liveCaptured: EverythingFSEventBatch?
            for _ in 0..<25 {
                if let b = collector.drain(), !b.directories.isEmpty {
                    liveCaptured = b
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            let validLive = try #require(liveCaptured)
            let afterStream = merged.applyingFSEventDirectories(validLive.directories)
            #expect(afterStream.search(queryText: "stream_live_probe.txt").count == 1)
        }
    }

    @Test("Priority user folders (Desktop & Downloads) are indexed before bulk sibling directories when maxNodes is capped")
    func priorityUserFoldersSurviveNodeCap() throws {
        let home = try makeIsolatedDir("prio-cap")
        defer { try? FileManager.default.removeItem(at: home) }

        let bulkSub = home.appendingPathComponent("00_HugeArchive/DeepBatch", isDirectory: true)
        let desktopSub = home.appendingPathComponent("Desktop/Urgent", isDirectory: true)
        let downloadsSub = home.appendingPathComponent("Downloads/Incoming", isDirectory: true)
        for dir in [bulkSub, desktopSub, downloadsSub] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for i in 0..<80 {
            try Data("x".utf8).write(to: bulkSub.appendingPathComponent("bulk_item_\(i).dat"))
        }
        try Data("contract".utf8).write(to: desktopSub.appendingPathComponent("client_contract.pdf"))
        try Data("dmg".utf8).write(to: downloadsSub.appendingPathComponent("release_installer.dmg"))

        let capped = try EverythingIndex.build(rootURLs: [home], maxNodes: 25)
        #expect(capped.reachedNodeLimit)
        #expect(capped.search(queryText: "client_contract.pdf").count == 1)
        #expect(capped.search(queryText: "release_installer.dmg").count == 1)
    }
}

private final class DirtyBatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var dirs: Set<String> = []
    private var recDirs: Set<String> = []
    private var latestId: UInt64 = 0

    func record(_ batch: EverythingFSEventBatch) {
        lock.lock()
        dirs.formUnion(batch.directories)
        recDirs.formUnion(batch.recursiveDirectories)
        if batch.latestEventId > latestId { latestId = batch.latestEventId }
        lock.unlock()
    }

    func drain() -> EverythingFSEventBatch? {
        lock.lock()
        defer { lock.unlock() }
        guard !dirs.isEmpty || !recDirs.isEmpty else { return nil }
        let out = EverythingFSEventBatch(directories: dirs, recursiveDirectories: recDirs, latestEventId: latestId)
        dirs.removeAll(); recDirs.removeAll(); latestId = 0
        return out
    }
}
