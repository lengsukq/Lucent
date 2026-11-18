import AVFoundation
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentMedia
@testable import LucentSearch

@Suite("Media Playback Compat, Hev1 Stsd Walker & Workspace/Everything Search Fixes")
struct LucentPlayerAndSearchFixesTests {
    private func makeTempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-fixes-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Hev1ResourceLoader walks nested moov->trak->mdia->minf->stbl->stsd boxes without size limit")
    func hev1NestedStsdBoxWalker() throws {
        let tmp = try makeTempDir("hev1-stsd")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let mp4URL = tmp.appendingPathComponent("nested-hev1.mp4")

        func makeBox(_ type: String, _ payload: Data) -> Data {
            var size = UInt32(8 + payload.count).bigEndian
            return withUnsafeBytes(of: &size) { Data($0) } + Data(type.utf8) + payload
        }

        // stsd: version/flags (4) + entry_count (4) + [hev1 sample entry box]
        let hev1Entry = makeBox("hev1", Data(repeating: 0x22, count: 24))
        var stsdHeader = Data([0, 0, 0, 0, 0, 0, 0, 1])
        stsdHeader.append(hev1Entry)
        let stsd = makeBox("stsd", stsdHeader)
        let stbl = makeBox("stbl", stsd)
        let minf = makeBox("minf", stbl)
        let mdia = makeBox("mdia", minf)
        let trak = makeBox("trak", mdia)
        let moov = makeBox("moov", trak)
        let ftyp = makeBox("ftyp", Data("isom\0\0\0\0".utf8))
        let mdat = makeBox("mdat", Data("hev1\0\0\0\0\0\0".utf8) + Data(repeating: 0x99, count: 32))

        var fileData = Data()
        fileData.append(ftyp)
        fileData.append(moov)
        fileData.append(mdat)
        try fileData.write(to: mp4URL)

        let scan = Hev1ResourceLoader.findHev1SampleEntryOffsets(in: mp4URL)
        #expect(scan.fileSize == Int64(fileData.count))
        #expect(scan.offsets.count == 1)
        if let patchPos = scan.offsets.first {
            let tagSlice = fileData[Int(patchPos)..<Int(patchPos + 4)]
            #expect(String(data: tagSlice, encoding: .ascii) == "hev1")
        }
    }

    @Test("EverythingIndex supports Unicode NFD/NFC, Chinese Pinyin, single-root path:, and deep exact hits")
    func everythingSearchNFDAndPinyinAndSingleRootPath() throws {
        let root = try makeTempDir("search-fixes")
        defer { try? FileManager.default.removeItem(at: root) }

        let subDir = root.appendingPathComponent("影视收藏/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let cnVideo = subDir.appendingPathComponent("复仇者联盟4.mp4")
        try Data("v".utf8).write(to: cnVideo)

        // Decomposed NFD filename ("Cafe\u{0301}_Clip.mp4") queried with NFC ("café")
        let nfdName = "Cafe\u{0301}_Clip.mp4"
        try Data("c".utf8).write(to: subDir.appendingPathComponent(nfdName))

        let idx = try EverythingIndex.build(rootURLs: [root], maxNodes: 5_000)

        // 1. Pinyin initials & full pinyin match Chinese filename
        let pinyinInitHits = idx.search(queryText: "fczlm", limit: 10)
        #expect(pinyinInitHits.contains(where: { $0.name == "复仇者联盟4.mp4" }))
        let pinyinFullHits = idx.search(queryText: "fuchouzhe", limit: 10)
        #expect(pinyinFullHits.contains(where: { $0.name == "复仇者联盟4.mp4" }))

        // 2. NFC query matches NFD filename
        let nfcHits = idx.search(queryText: "caf\u{00E9}", limit: 10)
        #expect(nfcHits.count == 1)

        // 3. Single-root full path filter matches nested files even when rootURLs.count == 1
        let rootPathQuery = "path:\"\(root.standardizedFileURL.path)\" video:"
        let pathHits = idx.search(queryText: rootPathQuery, limit: 10)
        #expect(pathHits.count == 2)

        // 4. Deep exact match beyond 300 substring hits is never truncated
        var syntheticNodes: [IndexedNode] = []
        for i in 0..<400 {
            syntheticNodes.append(IndexedNode(parentID: -1, rootIndex: 0, isDirectory: false, name: "prefix_noise_\(i)_clip.mp4"))
        }
        syntheticNodes.append(IndexedNode(parentID: -1, rootIndex: 0, isDirectory: false, name: "clip.mp4"))
        let deepIdx = EverythingIndex(rootURLs: [root], nodes: syntheticNodes, builtAt: Date(), reachedNodeLimit: false)
        let deepHits = deepIdx.search(queryText: "clip.mp4", limit: 12)
        #expect(deepHits.first?.name == "clip.mp4")
    }

    @Test("WorkspaceSearchMatcher recursively finds nested files with multi-keyword, extension, and Pinyin queries")
    func workspaceRecursiveSubfolderSearch() throws {
        let root = try makeTempDir("ws-recursive")
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("素材库/演示视频", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let target = nested.appendingPathComponent("产品发布会_1080p.mp4")
        try Data(repeating: 0x01, count: 64).write(to: target)
        try Data("note".utf8).write(to: nested.appendingPathComponent("备注.txt"))

        let multiHits = WorkspaceSearchMatcher.searchDirectoryRecursively(
            rootURL: root,
            queryText: "fbh .mp4",
            mediaFilter: .all
        )
        #expect(multiHits.count == 1)
        #expect(multiHits.first?.name == "产品发布会_1080p.mp4")

        let videoOnlyHits = WorkspaceSearchMatcher.searchDirectoryRecursively(
            rootURL: root,
            queryText: "演示",
            mediaFilter: .video
        )
        #expect(videoOnlyHits.count == 1)
        #expect(videoOnlyHits.first?.url.standardizedFileURL.path == target.standardizedFileURL.path)
    }
}
