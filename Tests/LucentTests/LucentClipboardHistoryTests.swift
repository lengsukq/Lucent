import Foundation
import Testing
@testable import LucentCore

@Suite("Full Clipboard History Persistence & Batch Cleanup")
struct LucentClipboardHistoryTests {
    @Test("ClipboardHistoryStore persists unpinned history with 0600 permissions, migrates temp media, merges with pinned, and stays out of raw backup")
    func fullClipboardPersistenceAndBackupIsolation() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-clip-hist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let clipTempDir = ClipboardPasteboardIO.clipboardTempDirectory()
        try FileManager.default.createDirectory(at: clipTempDir, withIntermediateDirectories: true)
        let transientFile = clipTempDir.appendingPathComponent("clip-hist-test-\(UUID().uuidString).txt")
        try Data("hello-media".utf8).write(to: transientFile)
        defer { try? FileManager.default.removeItem(at: transientFile) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let pinned = ClipboardEntry(
            title: "Pinned Note",
            subtitle: "Text",
            textValue: "keep-pinned",
            capturedAt: now.addingTimeInterval(-3_600),
            isPinned: true,
            payloadKind: .text
        )
        let unpinnedText = ClipboardEntry(
            title: "Recent Text",
            subtitle: "Text",
            textValue: "hello-unpinned",
            capturedAt: now,
            isPinned: false,
            payloadKind: .text
        )
        let unpinnedFile = ClipboardEntry(
            title: "Transient File",
            subtitle: "File",
            fileURL: transientFile,
            capturedAt: now.addingTimeInterval(-120),
            isPinned: false,
            payloadKind: .file(transientFile)
        )
        let staleText = ClipboardEntry(
            title: "Stale Text",
            subtitle: "Text",
            textValue: "expired-unpinned",
            capturedAt: now.addingTimeInterval(-3 * 86_400),
            isPinned: false,
            payloadKind: .text
        )

        var entries = [pinned, unpinnedText, unpinnedFile, staleText]
        entries = ClipboardPersistenceStore.savePinnedEntries(entries, appSupportDirectory: tmp)
        entries = ClipboardHistoryStore.saveHistoryEntries(entries, appSupportDirectory: tmp)

        let migratedFile = entries.first(where: { $0.id == unpinnedFile.id })
        #expect(migratedFile?.fileURL?.path.contains("ClipboardHistory/hist-") == true)

        let histURL = ClipboardHistoryStore.defaultStoreURL(appSupportDirectory: tmp)
        let perms = (try? FileManager.default.attributesOfItem(atPath: histURL.path)[.posixPermissions] as? Int) ?? 0
        #expect((perms & 0o777) == 0o600)

        // Merged load honors TTL (hours24 drops staleText while keeping pinned + fresh unpinned)
        let merged = ClipboardHistoryStore.loadMergedEntries(
            appSupportDirectory: tmp,
            maxUnpinned: 80,
            ttl: .hours24,
            now: now
        )
        #expect(merged.map(\.id).contains(pinned.id))
        #expect(merged.map(\.id).contains(unpinnedText.id))
        #expect(merged.map(\.id).contains(unpinnedFile.id))
        #expect(!merged.map(\.id).contains(staleText.id))

        // Unpinned clipboard history must NOT leak into BackupArchiveService raw configs
        let archive = try BackupArchiveService.exportBackupData(appSupportDirectory: tmp, compress: true)
        let summary = try BackupArchiveService.inspectBackupData(archive)
        #expect(!summary.configFileNames.contains(ClipboardHistoryStore.storeFileName))

        // Orphaned history media is pruned once removed from entries
        let migratedPath = try #require(migratedFile?.fileURL?.path)
        #expect(FileManager.default.fileExists(atPath: migratedPath) == true)
        _ = ClipboardHistoryStore.saveHistoryEntries([pinned, unpinnedText], appSupportDirectory: tmp)
        #expect(FileManager.default.fileExists(atPath: migratedPath) == false)
    }

    @Test("ClipboardBatchCleaner handles age-based, media-only, category, unpinned-all, and full cleanup accurately")
    func batchCleanupModes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dummyImg = URL(fileURLWithPath: "/tmp/a.png")
        let dummyVid = URL(fileURLWithPath: "/tmp/b.mp4")

        let pinnedOld = ClipboardEntry(title: "Pinned Old", subtitle: "", textValue: "p", capturedAt: now.addingTimeInterval(-10 * 86_400), isPinned: true, payloadKind: .text)
        let recentText = ClipboardEntry(title: "Recent Text", subtitle: "", textValue: "t", capturedAt: now.addingTimeInterval(-600), isPinned: false, payloadKind: .text)
        let old2dText = ClipboardEntry(title: "2d Text", subtitle: "", textValue: "t2", capturedAt: now.addingTimeInterval(-2 * 86_400), isPinned: false, payloadKind: .text)
        let old9dImg = ClipboardEntry(title: "9d Img", subtitle: "", fileURL: dummyImg, capturedAt: now.addingTimeInterval(-9 * 86_400), isPinned: false, payloadKind: .image(dummyImg, CGSize(width: 100, height: 100)))
        let recentVid = ClipboardEntry(title: "Recent Vid", subtitle: "", fileURL: dummyVid, capturedAt: now.addingTimeInterval(-300), isPinned: false, payloadKind: .video(dummyVid))

        let all = [pinnedOld, recentText, old2dText, old9dImg, recentVid]

        let older24h = ClipboardBatchCleaner.apply(.olderThan24Hours, to: all, now: now)
        #expect(Set(older24h.removed.map(\.id)) == Set([old2dText.id, old9dImg.id]))
        #expect(older24h.remaining.contains(where: { $0.id == pinnedOld.id }))

        let older7d = ClipboardBatchCleaner.apply(.olderThan7Days, to: all, now: now)
        #expect(older7d.removed.map(\.id) == [old9dImg.id])

        let mediaOnly = ClipboardBatchCleaner.apply(.unpinnedMediaOnly, to: all, now: now)
        #expect(Set(mediaOnly.removed.map(\.id)) == Set([old9dImg.id, recentVid.id]))

        let textOnly = ClipboardBatchCleaner.apply(.unpinnedCategory(.text), to: all, now: now)
        #expect(Set(textOnly.removed.map(\.id)) == Set([recentText.id, old2dText.id]))

        let unpinnedAll = ClipboardBatchCleaner.apply(.unpinnedAll, to: all, now: now)
        #expect(unpinnedAll.remaining.map(\.id) == [pinnedOld.id])

        let wipeAll = ClipboardBatchCleaner.apply(.allIncludingPinned, to: all, now: now)
        #expect(wipeAll.remaining.isEmpty)
        #expect(wipeAll.removed.count == all.count)
    }
}
