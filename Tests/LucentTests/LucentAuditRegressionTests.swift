import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentSearch

@Suite("Indexing, Snapshot, Search & AppUsage Audit Regression Tests")
struct LucentAuditRegressionTests {
    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-audit-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath().standardizedFileURL
    }

    @Test("EverythingIndex.merging preserves empty-volume roots and conservative builtAt")
    func mergingPreservesEmptyVolumeRootAndBuiltAt() throws {
        let root = try makeTempDir("merge-empty")
        defer { try? FileManager.default.removeItem(at: root) }
        let fastDir = root.appendingPathComponent("Fast", isDirectory: true)
        let emptySlowDir = root.appendingPathComponent("EmptyUSB", isDirectory: true)
        let cacheDir = root.appendingPathComponent("Cache", isDirectory: true)
        for d in [fastDir, emptySlowDir, cacheDir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        try Data("ok".utf8).write(to: fastDir.appendingPathComponent("doc.txt"))

        let stage1 = try EverythingIndex.build(rootURLs: [fastDir], maxNodes: 100)
        let stage2 = try EverythingIndex.build(rootURLs: [emptySlowDir], maxNodes: 100)
        #expect(stage2.nodes.isEmpty)

        let merged = stage1.merging(stage2)
        #expect(merged.rootURLs.count == 2)
        #expect(merged.rootPaths == [fastDir.path, emptySlowDir.path])
        #expect(merged.builtAt <= stage1.builtAt)

        let saved = EverythingSnapshotStore.save(merged, scopeKey: "empty-usb", cacheDirectory: cacheDir)
        #expect(saved != nil)
        let reloaded = EverythingSnapshotStore.load(
            scopeKey: "empty-usb", expectedRoots: [fastDir, emptySlowDir], cacheDirectory: cacheDir
        )
        #expect(reloaded?.rootPaths == [fastDir.path, emptySlowDir.path])
    }

    @Test("applyingFSEventDirectories expands ancestor/root recursive flags, preserves builtAt, and does not truncate existing nodes")
    func applyingFSEventsExpandsRootAncestorsAndPreservesBuiltAt() throws {
        let root = try makeTempDir("fs-root-expand")
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("Docs/Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: sub.appendingPathComponent("alpha.md"))

        let initial = try EverythingIndex.build(rootURLs: [root], maxNodes: 500)
        try Data("v2".utf8).write(to: sub.appendingPathComponent("beta.md"))

        // Passing "/" as a recursive subtree (simulating FSEvents UserDropped/KernelDropped) must expand to root
        let expanded = initial.applyingFSEventDirectories([], recursiveSubtreeDirs: ["/"])
        #expect(expanded.search(queryText: "beta.md").count == 1)
        #expect(expanded.builtAt == initial.builtAt)

        // Passing maxNodes smaller than existing node count must NOT truncate existing nodes
        let capped = expanded.applyingFSEventDirectories([sub.path], maxNodes: 1)
        #expect(capped.nodes.count >= expanded.nodes.count)
    }

    @Test("EverythingIndex.search honors excludedPaths before limit (no starvation) and drops deleted files when verifyExistence is true")
    func searchPreFiltersExclusionsAndDropsPhantomDeletedHits() throws {
        let root = try makeTempDir("search-filter")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let secretDir = root.appendingPathComponent("Secret", isDirectory: true)
        let publicDir = root.appendingPathComponent("Public", isDirectory: true)
        try fm.createDirectory(at: secretDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: publicDir, withIntermediateDirectories: true)

        for i in 0..<20 {
            try Data("s".utf8).write(to: secretDir.appendingPathComponent("invoice_\(i).txt"))
        }
        let validFile = publicDir.appendingPathComponent("invoice_valid.txt")
        let doomedFile = publicDir.appendingPathComponent("invoice_doomed.txt")
        try Data("ok".utf8).write(to: validFile)
        try Data("bye".utf8).write(to: doomedFile)

        let index = try EverythingIndex.build(rootURLs: [root], maxNodes: 1_000)
        try fm.removeItem(at: doomedFile)

        let hits = index.search(
            queryText: "invoice",
            limit: 5,
            excludedPaths: [secretDir.path],
            verifyExistence: true
        )
        #expect(hits.count == 1)
        #expect(hits.first?.name == "invoice_valid.txt")
    }

    @Test("EverythingSnapshotStore rejects NaN builtAt timestamps and reads headers larger than 4 KB")
    func snapshotHeaderValidationAndLargeRootList() throws {
        let root = try makeTempDir("snap-header")
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheDir = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Build 60 long-path roots (> 4096 bytes header)
        var manyRoots: [URL] = []
        for i in 0..<60 {
            let r = root.appendingPathComponent(String(format: "root_directory_segment_padding_%03d_long_name_for_header_test", i), isDirectory: true)
            try FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
            manyRoots.append(r)
        }
        let idx = EverythingIndex(rootURLs: manyRoots, nodes: [], builtAt: Date(), reachedNodeLimit: false, lastEventId: 77)
        let saved = try #require(EverythingSnapshotStore.save(idx, scopeKey: "many-roots", cacheDirectory: cacheDir))
        let header = EverythingSnapshotStore.readHeaderMetadata(
            scopeKey: "many-roots", expectedRoots: manyRoots, cacheDirectory: cacheDir
        )
        #expect(header?.lastEventId == 77)

        // Corrupt builtAt bits in header to quiet NaN and confirm readHeaderMetadata rejects it
        var raw = try Data(contentsOf: saved)
        var nanBits = Double.nan.bitPattern.littleEndian
        withUnsafeBytes(of: &nanBits) { raw.replaceSubrange(8..<16, with: $0) }
        try raw.write(to: saved, options: .atomic)
        #expect(EverythingSnapshotStore.readHeaderMetadata(
            scopeKey: "many-roots", expectedRoots: manyRoots, cacheDirectory: cacheDir
        ) == nil)
    }

    @Test("AppUsageService clears running state when setAppRunning(false) is reported on termination")
    func appUsageClearsRunningStateOnTermination() throws {
        let root = try makeTempDir("usage-term")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AppUsageService(storageURL: root.appendingPathComponent("usage.json"), debounceNanoseconds: 0)
        let appID = "/Applications/SampleTool.app"

        service.setAppRunning(true, appID: appID)
        #expect(service.compactBadgeSummary(for: appID) == "运行中")

        service.setAppRunning(false, appID: appID)
        #expect(service.compactBadgeSummary(for: appID) == nil)
    }
}
