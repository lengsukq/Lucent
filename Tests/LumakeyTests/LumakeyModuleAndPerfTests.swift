import Foundation
import Testing
@testable import LumakeyCore
@testable import LumakeyFoundation
@testable import LumakeyMedia
@testable import LumakeySearch
@testable import LumakeySystem

@Suite("Lumakey Workspace Safety & Performance Baseline Tests")
struct LumakeyModuleAndPerfTests {
    private func makeTempWorkspace(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-perf-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("WorkspaceFileOperations blocks read-only NTFS, self-nesting moves, and collisions")
    func workspaceAbnormalSafetyGuards() throws {
        let root = try makeTempWorkspace("ws-guards")
        defer { try? FileManager.default.removeItem(at: root) }

        let parentFolder = try WorkspaceFileOperations.createFolder(named: "ProjectA", in: root)
        let childFolder = try WorkspaceFileOperations.createFolder(named: "Sub", in: parentFolder)
        let fileA = root.appendingPathComponent("report.md")
        let fileB = childFolder.appendingPathComponent("report.md")
        try "# A".write(to: fileA, atomically: true, encoding: .utf8)
        try "# B".write(to: fileB, atomically: true, encoding: .utf8)

        // 1. Block moving a folder into its own descendant
        #expect(throws: LumakeyError.self) {
            _ = try WorkspaceFileOperations.moveItems([parentFolder], to: childFolder)
        }

        // 2. Block overwrite on move collision while preserving original file untouched
        #expect(throws: LumakeyError.self) {
            _ = try WorkspaceFileOperations.moveItems([fileA], to: childFolder)
        }
        #expect(FileManager.default.fileExists(atPath: fileA.path))
        #expect((try String(contentsOf: fileB, encoding: .utf8)) == "# B")

        // 3. Block writes to read-only NTFS volume via injected VolumeSummary
        let fakeReadOnlyNTFS: (URL) -> VolumeSummary? = { url in
            VolumeSummary(
                name: "ExternalNTFS",
                mountPath: url.path,
                fileSystemType: "ntfs",
                formatKind: .ntfsReadOnly,
                isReadOnly: true,
                isExternal: true,
                totalBytes: 1_000_000,
                availableBytes: 500_000
            )
        }
        #expect(throws: LumakeyError.self) {
            _ = try WorkspaceFileOperations.createFolder(named: "Blocked", in: root, inspectVolume: fakeReadOnlyNTFS)
        }
    }

    @Test("EverythingIndex search, O(1) header probe, mmap load, and memory relief meet latency baselines")
    func everythingPerformanceAndMemoryBaselines() throws {
        let root = try makeTempWorkspace("bench")
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheDir = root.appendingPathComponent("IdxCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Synthesize 5,000 compact nodes across 25 folders
        var nodes: [IndexedNode] = []
        nodes.reserveCapacity(5_025)
        for d in 0..<25 {
            nodes.append(IndexedNode(parentID: -1, rootIndex: 0, isDirectory: true, name: "Module_\(d)"))
        }
        for i in 0..<5_000 {
            let ext = (i % 5 == 0) ? "swift" : ((i % 3 == 0) ? "md" : "json")
            nodes.append(IndexedNode(
                parentID: Int32(i % 25),
                rootIndex: 0,
                isDirectory: false,
                name: "Component_\(i)_Service.\(ext)"
            ))
        }
        let syntheticIndex = EverythingIndex(rootURLs: [root], nodes: nodes, builtAt: Date(), reachedNodeLimit: false)
        let saved = EverythingSnapshotStore.save(syntheticIndex, scopeKey: "bench-5k", cacheDirectory: cacheDir)
        #expect(saved != nil)

        // Baseline 1: O(1) header probe must complete in < 25 ms
        let tHeader = ContinuousClock.now
        let header = EverythingSnapshotStore.readHeaderMetadata(
            scopeKey: "bench-5k", expectedRoots: [root], cacheDirectory: cacheDir
        )
        let headerMs = tHeader.duration(to: .now).millisecondsDouble
        #expect(header?.nodeCount == 5_025)
        #expect(headerMs < 25.0)

        // Baseline 2: Full mmap + SHA-256 verified load of 5k nodes must complete in < 80 ms
        let tLoad = ContinuousClock.now
        let loaded = try #require(EverythingSnapshotStore.load(
            scopeKey: "bench-5k", expectedRoots: [root], cacheDirectory: cacheDir
        ))
        let loadMs = tLoad.duration(to: .now).millisecondsDouble
        #expect(loaded.nodes.count == 5_025)
        #expect(loadMs < 80.0)

        // Baseline 3: Ranked UTF-8 + DSL search across 5k nodes must complete in < 40 ms
        let tSearch = ContinuousClock.now
        let hits = loaded.search(queryText: "ext:swift component_4995", limit: 20)
        let searchMs = tSearch.duration(to: .now).millisecondsDouble
        #expect(hits.count == 1)
        #expect(searchMs < 40.0)

        // Baseline 4: Memory footprint & page reclamation API health
        let footprint = MemoryStats.currentPhysicalFootprintMB()
        MemoryStats.reclaimFreeHeapPages()
        #expect(footprint > 0 && footprint < 1024)
    }

    @Test("Independent domain modules (Foundation, Search, Media, System) interoperate cleanly")
    func domainModulesInteroperability() {
        let blocks = MarkdownDocumentParser.parse("# Title\n\n- [x] Modularized")
        #expect(MarkdownDocumentParser.headings(in: blocks).first?.text == "Title")

        let chord = HotKeyChord.parse("⌥Space")
        #expect(chord?.isValidGlobalShortcut == true)
    }
}

private extension Duration {
    var millisecondsDouble: Double {
        Double(components.seconds) * 1000.0 + Double(components.attoseconds) / 1_000_000_000_000_000.0
    }
}
