import AppKit
import CoreGraphics
import Foundation
import LucentCore

func testV063BinarySnapshotFSEventsAndDirCache() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lucent-v063-\(UUID().uuidString)", isDirectory: true)
    let cacheDir = root.appendingPathComponent(".cache-dir", isDirectory: true)
    let subDir = root.appendingPathComponent("src", isDirectory: true)
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    try Data("print(1)\n".utf8).write(to: subDir.appendingPathComponent("hello.swift"))
    let built = try EverythingIndex.build(rootURL: root, maxNodes: 1000)
    check(built.search(queryText: "hello.swift").count == 1, "initial index finds hello.swift")

    let savedURL = EverythingSnapshotStore.save(built, scopeKey: "v063-unit", cacheDirectory: cacheDir)
    check(savedURL != nil && fm.fileExists(atPath: savedURL!.path), "EverythingSnapshotStore saves binary .lcntidx file")

    let loaded = EverythingSnapshotStore.load(scopeKey: "v063-unit", expectedRoots: [root], cacheDirectory: cacheDir)
    check(loaded != nil && loaded?.nodes.count == built.nodes.count, "EverythingSnapshotStore loads snapshot via mmap")
    check(loaded?.search(queryText: "hello.swift").count == 1, "mmap-loaded snapshot serves search hits")
    check(EverythingSnapshotStore.load(scopeKey: "v063-unit", expectedRoots: [root.appendingPathComponent("other")], cacheDirectory: cacheDir) == nil, "snapshot rejects mismatched expectedRoots")
    check(EverythingSnapshotStore.load(scopeKey: "v063-unit", expectedRoots: [root], maxAgeSeconds: -1, cacheDirectory: cacheDir) == nil, "snapshot rejects expired snapshot")

    let emptyTmp = root.appendingPathComponent("empty-tmp", isDirectory: true)
    let cacheBefore = AppCacheService.inspectAll(tempRoot: emptyTmp, indexCacheRoot: cacheDir)
    check((cacheBefore.buckets.first(where: { $0.kind == .diskIndexSnapshot })?.sizeBytes ?? 0) > 0, ".diskIndexSnapshot reports persisted snapshot size")
    check(AppCacheService.clearBucket(.diskIndexSnapshot, tempRoot: emptyTmp, indexCacheRoot: cacheDir) > 0, "clearing .diskIndexSnapshot deletes .lcntidx snapshot files")

    let newSub = root.appendingPathComponent("docs", isDirectory: true)
    try fm.createDirectory(at: newSub, withIntermediateDirectories: true)
    try Data("# guide".utf8).write(to: newSub.appendingPathComponent("guide.md"))
    try Data("fn main() {}".utf8).write(to: subDir.appendingPathComponent("live_add.rs"))
    let resolvedRootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    let resolvedSubPath = subDir.resolvingSymlinksInPath().standardizedFileURL.path
    let updated = built.applyingFSEventDirectories([resolvedRootPath, resolvedSubPath])
    check(updated.search(queryText: "live_add.rs").count == 1 && updated.search(queryText: "guide.md").count == 1, "incremental FSEvent sync adds new files")

    try fm.removeItem(at: subDir.appendingPathComponent("live_add.rs"))
    let afterDelete = updated.applyingFSEventDirectories([resolvedSubPath])
    check(afterDelete.search(queryText: "live_add.rs").isEmpty, "incremental FSEvent sync removes deleted file")

    let watchDir = root.appendingPathComponent("watch-live", isDirectory: true)
    try fm.createDirectory(at: watchDir, withIntermediateDirectories: true)
    let sem = DispatchSemaphore(value: 0)
    let watcher = EverythingFSEventWatcher(roots: [watchDir], debounceInterval: 0.25) { dirs in
        if !dirs.isEmpty { sem.signal() }
    }
    check(watcher != nil, "EverythingFSEventWatcher initializes on existing directory")
    try Data("x".utf8).write(to: watchDir.appendingPathComponent("probe.txt"))
    let waitRes = sem.wait(timeout: .now() + 4.0)
    watcher?.stop()
    check(waitRes == .success, "EverythingFSEventWatcher delivers live filesystem event")

    let scannedFast = try DirectoryScanner.scanDirectory(at: subDir, includeHidden: false, skipExtendedTags: true)
    check(scannedFast.contains(where: { $0.name == "hello.swift" && $0.tags.isEmpty }), "skipExtendedTags skips xattr tags")
    check(DirectoryScanner.directoryModificationDate(at: subDir) != nil, "directoryModificationDate returns POSIX stat mtime")

    let dirCache = WorkspaceDirectoryCache(maxEntries: 2)
    let summary = VolumeInspector.inspect(url: subDir)
    dirCache.store(entries: scannedFast, volumeSummary: summary, for: subDir, includeHidden: false, directoryMTime: Date())
    dirCache.store(entries: [], volumeSummary: summary, for: newSub, includeHidden: false, directoryMTime: Date())
    dirCache.store(entries: [], volumeSummary: summary, for: watchDir, includeHidden: false, directoryMTime: Date())
    check(dirCache.count == 2 && dirCache.lookup(for: subDir, includeHidden: false) == nil && dirCache.lookup(for: watchDir, includeHidden: false) != nil, "WorkspaceDirectoryCache LRU")
    dirCache.trimKeepingRecent(1)
    check(dirCache.count == 1, "WorkspaceDirectoryCache.trimKeepingRecent keeps bounded count")
    dirCache.clear()
    check(dirCache.count == 0, "WorkspaceDirectoryCache.clear empties cache")
    print("[ok] v0.6.3 Binary mmap Snapshot, FSEvents Incremental Index & Workspace Directory Cache")
}

func testV064ScreenshotAutoPasteboardAndRestore() throws {
    try MainActor.assumeIsolated {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        pb.setString("keep-my-previous-text", forType: .string)
        let backup = PasteboardSnapshot.capture(from: pb)

        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            check(false, "create CGContext for v0.6.4 pasteboard test")
            return
        }
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.52, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        guard let cgImage = ctx.makeImage() else {
            check(false, "create CGImage for v0.6.4 pasteboard test")
            return
        }

        let copyOK = ScreenshotCompositor.copyImageToPasteboard(cgImage, scale: 2.0, to: pb)
        check(copyOK && pb.data(forType: .png) != nil && pb.data(forType: .tiff) != nil, "copyImageToPasteboard writes PNG and TIFF")
        check(NSImage(pasteboard: pb)?.size == NSSize(width: 40, height: 30), "pasteboard NSImage preserves Retina point size")

        let clipEntry = ClipboardService.captureCurrent(from: pb)
        if let clipEntry, case .image = clipEntry.payloadKind {
            ClipboardService.removeTempFiles(for: [clipEntry])
        } else {
            check(false, "ClipboardService captures copied screenshot image")
        }

        let tmpDir = try makeTempDir("v064-pb")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let fileURL = tmpDir.appendingPathComponent("shot.png")
        try ScreenshotCompositor.writePNG(cgImage, to: fileURL)
        pb.clearContents()
        let fileCopyOK = ScreenshotCompositor.copyImageFileToPasteboard(at: fileURL, to: pb)
        check(fileCopyOK && pb.data(forType: .png) != nil && pb.data(forType: .tiff) != nil, "copyImageFileToPasteboard writes PNG and TIFF")

        backup.restore(to: pb)
        check(pb.string(forType: .string) == "keep-my-previous-text" && pb.data(forType: .png) == nil, "PasteboardSnapshot restores previous text on cancel")
        print("[ok] v0.6.4 Screenshot Auto-Pasteboard Dual-Format & Cancel Restore")
    }
}

func testV065PerformanceCompactIndexHeaderAndFormatters() throws {
    let strideBytes = MemoryLayout<IndexedNode>.stride
    check(strideBytes <= 32, "IndexedNode stride is compact (\(strideBytes) B <= 32 B)")

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("lucent-v065-\(UUID().uuidString)", isDirectory: true)
    let cacheDir = root.appendingPathComponent("idx-cache", isDirectory: true)
    let subDir = root.appendingPathComponent("docs", isDirectory: true)
    try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    try Data("pdf".utf8).write(to: subDir.appendingPathComponent("2026年度总结Report.pdf"))
    try Data("cafe".utf8).write(to: subDir.appendingPathComponent("Café_Notes.md"))

    let idx = try EverythingIndex.build(rootURLs: [subDir], maxNodes: 500)
    check(idx.nodes.count == 2, "indexed 2 unicode/mixed-case files")
    check(idx.search(queryText: "report").count == 1 && idx.search(queryText: "年度").count == 1, "zero-alloc UTF8 query matches ASCII and CJK")
    check(idx.search(queryText: "café").count == 1 && idx.search(queryText: "CAFÉ").count == 1, "non-ASCII fallback matches accented uppercase/lowercase")
    check(idx.search(queryText: "ext:pdf;md !pdf").count == 1, "ext + negated DSL works without stored ext strings")

    let saved = EverythingSnapshotStore.save(idx, scopeKey: "v065-perf", cacheDirectory: cacheDir)
    check(saved != nil, "LCNTIDX3 snapshot saves cleanly")
    check(EverythingSnapshotStore.readHeaderMetadata(scopeKey: "v065-perf", expectedRoots: [subDir], cacheDirectory: cacheDir)?.nodeCount == 2, "O(1) readHeaderMetadata reads exact nodeCount")
    check(EverythingSnapshotStore.load(scopeKey: "v065-perf", expectedRoots: [subDir], cacheDirectory: cacheDir)?.search(queryText: "report").count == 1, "LCNTIDX3 load preserves search fidelity")
    if let snapURL = saved, var rawSnap = try? Data(contentsOf: snapURL), rawSnap.count > 40 {
        rawSnap[rawSnap.count - 36] ^= 0xFF
        try? rawSnap.write(to: snapURL, options: .atomic)
        check(EverythingSnapshotStore.load(scopeKey: "v065-perf", expectedRoots: [subDir], cacheDirectory: cacheDir) == nil, "LCNTIDX3 SHA-256 digest rejects corrupted snapshot bytes")
    }

    check(FastFormatters.formatFileBytes(512) == "512 B" && FastFormatters.formatFileBytes(2_500_000) == "2.5 MB", "FastFormatters byte formatting")
    let dateStr = FastFormatters.formatModificationDate(Date(timeIntervalSince1970: 1_700_000_000))
    check(dateStr.count == 16 && dateStr.contains("-"), "FastFormatters formats local timestamp: \(dateStr)")

    let appItem = InstalledAppItem(name: "访达", englishName: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
    check(appItem.englishNameLowercased == "finder" && appItem.nameLowercased == "访达", "InstalledAppItem precomputes lowercased names")
    let manifest = PluginManifest(id: "fast-plug", name: "NetTool", version: "1.0.0", description: "Probe Ports", mode: .script, keywords: ["Net", "PORT"], entry: "run.sh")
    let desc = PluginDescriptor(id: "fast-plug", directoryURL: subDir, manifest: manifest, validationIssues: [])
    check(desc.nameLowercased == "nettool" && desc.keywordsLowercased == ["net", "port"], "PluginDescriptor precomputes lowercased fields")
    print("[ok] v0.6.5 Compact IndexedNode (\(strideBytes)B) + LCNTIDX2 O(1) Header + UTF8 Query + FastFormatters")
}
