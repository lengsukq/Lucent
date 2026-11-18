import AppKit
import CoreGraphics
import Foundation
import LucentCore

private func makeSampleJPEG(width: Int = 64, height: Int = 48, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        check(false, "encode synthetic JPEG")
        return
    }
    try jpg.write(to: url)
}

func testClipboardMediaCaptureAndPasteModel() throws {
    let fm = FileManager.default
    let tmp = try makeTempDir("clip-media")
    defer { try? fm.removeItem(at: tmp) }

    check(ClipboardCategory.video.localizedTitle == "视频", "ClipboardCategory.video zh title")
    check(ClipboardPayloadKind.video(tmp).badgeTitle == "视频", "ClipboardPayloadKind.video badge")

    // Ephemeral / container path detection (WeChat RWTemp, Containers, /var/folders, /tmp)
    check(
        ClipboardPasteboardIO.isEphemeralOrContainerPath("/Users/demo/Library/Containers/com.tencent.xinWeChat/Data/RWTemp/a.mp4"),
        "WeChat container RWTemp detected as ephemeral/container path"
    )
    check(
        ClipboardPasteboardIO.isEphemeralOrContainerPath("/private/var/folders/xx/T/clip.png"),
        "/private/var/folders detected as ephemeral path"
    )
    check(
        !ClipboardPasteboardIO.isEphemeralOrContainerPath("/Volumes/ExternalSSD/Movies/demo.mp4"),
        "persistent volume path not flagged as ephemeral"
    )

    // Multi-file URL preservation & promote/dedupe safety
    let imgURL = tmp.appendingPathComponent("cover.jpg")
    let vidURL = tmp.appendingPathComponent("clip.mp4")
    try makeSampleJPEG(to: imgURL)
    try Data("FAKE-MP4-PAYLOAD".utf8).write(to: vidURL)

    let imgEntry = ClipboardEntry(title: "cover.jpg", subtitle: "JPG", fileURL: imgURL, payloadKind: .image(imgURL, CGSize(width: 64, height: 48)))
    let vidEntry = ClipboardEntry(title: "clip.mp4", subtitle: "MP4", fileURL: vidURL, payloadKind: .video(vidURL))
    let multiEntry = ClipboardEntry(title: "2 items", subtitle: tmp.path, fileURLs: [imgURL, vidURL], payloadKind: .file(imgURL))
    check(multiEntry.fileURLs.count == 2 && multiEntry.fileURL == imgURL.standardizedFileURL, "ClipboardEntry preserves multiple fileURLs")

    var history: [ClipboardEntry] = []
    history = ClipboardService.insert(imgEntry, into: history)
    history = ClipboardService.insert(vidEntry, into: history)
    check(ClipboardService.filter(history, query: "", category: .image).count == 1, "filter(.image) matches image entry")
    check(ClipboardService.filter(history, query: "", category: .video).count == 1, "filter(.video) matches video entry")

    let promoted = ClipboardService.promote(imgEntry, in: history)
    check(promoted.first?.id == imgEntry.id && promoted.count == 2, "promote moves existing clipboard entry to top without duplicating")

    // Nested temp subfolder cleanup + pinned protection in AppCacheService & ClipboardService
    let clipRoot = ClipboardPasteboardIO.clipboardTempDirectory(tempRoot: tmp)
    let unpinnedSlot = clipRoot.appendingPathComponent("slot-unpinned", isDirectory: true)
    let pinnedSlot = clipRoot.appendingPathComponent("slot-pinned", isDirectory: true)
    try fm.createDirectory(at: unpinnedSlot, withIntermediateDirectories: true)
    try fm.createDirectory(at: pinnedSlot, withIntermediateDirectories: true)
    let unpinnedVideo = unpinnedSlot.appendingPathComponent("chat-video.mp4")
    let pinnedVideo = pinnedSlot.appendingPathComponent("fav-video.mp4")
    try Data(repeating: 0x42, count: 256).write(to: unpinnedVideo)
    try Data(repeating: 0x24, count: 128).write(to: pinnedVideo)

    let freed = AppCacheService.clearBucket(.clipboardImages, protectedURLs: [pinnedVideo], tempRoot: tmp)
    check(freed == 256, "AppCacheService recursively clears nested unpinned clipboard media subfolder")
    check(!fm.fileExists(atPath: unpinnedSlot.path), "empty unpinned slot directory removed cleanly")
    check(fm.fileExists(atPath: pinnedVideo.path), "pinned nested video preserved")

    // Backup round-trip of pinned video entry
    let supportSrc = tmp.appendingPathComponent("SupportSrc", isDirectory: true)
    let supportDst = tmp.appendingPathComponent("SupportDst", isDirectory: true)
    try fm.createDirectory(at: supportSrc, withIntermediateDirectories: true)
    let pinnedVidEntry = ClipboardEntry(title: "fav-video.mp4", subtitle: "MP4", fileURL: pinnedVideo, isPinned: true, payloadKind: .video(pinnedVideo))
    let backupData = try BackupArchiveService.exportBackupData(
        appSupportDirectory: supportSrc,
        clipboardEntries: [pinnedVidEntry],
        appVersion: "0.8.9"
    )
    let restored = try BackupArchiveService.restoreBackupData(backupData, appSupportDirectory: supportDst)
    if let firstRestored = restored.restoredClipboardEntries.first,
       case .video(let u) = firstRestored.payloadKind {
        check(u.lastPathComponent == "fav-video.mp4", "BackupArchiveService restores pinned video as .video payload")
    } else {
        check(false, "BackupArchiveService restores pinned video entry")
    }

    // PluginContextMatcher video support
    let ctx = PluginContextMatcher.payloadFromClipboard(vidEntry)
    check(ctx?.kind == .file && ctx?.filePaths == [vidURL.standardizedFileURL.path], "PluginContextMatcher maps video clipboard entry to file context")

    // MCPAgentPromptBuilder full Agent setup prompt verification (zh-Hans + English + extraTask)
    let fakeMCPPath = "/Applications/Lucent.app/Contents/MacOS/lucent-mcp"
    let zhPrompt = MCPAgentPromptBuilder.buildAgentPrompt(
        executablePath: fakeMCPPath,
        pluginsDirectoryPath: "/Users/demo/Library/Application Support/Lucent/Plugins",
        extraTask: "帮我写一个端口占用查看插件",
        language: .zhHans
    )
    check(zhPrompt.contains(fakeMCPPath), "zh Agent prompt embeds exact lucent-mcp executable path")
    check(zhPrompt.contains("claude mcp add --transport stdio lucent"), "zh Agent prompt includes Claude Code CLI command")
    check(zhPrompt.contains("\"mcpServers\""), "zh Agent prompt includes standard mcpServers JSON block")
    check(zhPrompt.contains("lucent://specs/plugin-v3") && zhPrompt.contains("lucent_list_plugins"), "zh Agent prompt instructs post-connect handshake & spec read")
    check(zhPrompt.contains("帮我写一个端口占用查看插件"), "zh Agent prompt appends optional follow-up task")

    let enPrompt = MCPAgentPromptBuilder.buildAgentPrompt(executablePath: fakeMCPPath, language: .english)
    check(enPrompt.contains("Connect") || enPrompt.contains("connect"), "en Agent prompt generated in English")
    check(!enPrompt.contains("Follow-Up Task After Connecting"), "empty extraTask omitted cleanly")
    print("[ok] Clipboard Media Model + MCPAgentPromptBuilder (zh/en + CLI/JSON + Handshake)")
}

func testLivePasteboardImageAndVideoRoundtrip() throws {
    try MainActor.assumeIsolated {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        let fm = FileManager.default
        let tmp = try makeTempDir("pb-live-media")
        defer { try? fm.removeItem(at: tmp) }

        // 1. Simulate WeChat / transient container JPEG image + MP4 video copy, then delete original source files!
        let fakeContainer = tmp.appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data/RWTemp", isDirectory: true)
        try fm.createDirectory(at: fakeContainer, withIntermediateDirectories: true)
        let srcJPG = fakeContainer.appendingPathComponent("wechat_pic.jpg")
        let srcMP4 = fakeContainer.appendingPathComponent("wechat_clip.mp4")
        try makeSampleJPEG(width: 96, height: 72, to: srcJPG)
        try Data("MP4-VIDEO-STREAM-BYTES".utf8).write(to: srcMP4)

        check(ClipboardPasteboardIO.writeFileURLsToPasteboard([srcJPG], to: pb), "seed pasteboard with container JPEG")
        guard let capturedImg = ClipboardPasteboardIO.captureCurrent(from: pb, tempRoot: tmp) else {
            check(false, "captureCurrent captures container JPEG as ClipboardEntry")
            return
        }
        if case .image(let cachedImgURL, let dims) = capturedImg.payloadKind {
            check(cachedImgURL.lastPathComponent == "wechat_pic.jpg", "cached image keeps original filename")
            check(cachedImgURL.path != srcJPG.standardizedFileURL.path, "container JPEG snapshotted into clipboard cache")
            check(dims == CGSize(width: 96, height: 72), "captured JPEG dimensions read accurately")
        } else {
            check(false, "copied JPEG file classified as .image payload")
        }

        check(ClipboardPasteboardIO.writeFileURLsToPasteboard([srcMP4], to: pb), "seed pasteboard with container MP4")
        guard let capturedVid = ClipboardPasteboardIO.captureCurrent(from: pb, tempRoot: tmp) else {
            check(false, "captureCurrent captures container MP4 as ClipboardEntry")
            return
        }
        if case .video(let cachedVidURL) = capturedVid.payloadKind {
            check(cachedVidURL.lastPathComponent == "wechat_clip.mp4", "cached video keeps original filename")
            check(cachedVidURL.path != srcMP4.standardizedFileURL.path, "container MP4 snapshotted into clipboard cache")
        } else {
            check(false, "copied MP4 file classified as .video payload")
        }

        // Remove the transient WeChat RWTemp originals — clipboard entries MUST still paste cleanly!
        try fm.removeItem(at: fakeContainer)

        // 2. Write captured JPEG entry back to pasteboard -> verify BOTH file URL + NSFilenamesPboardType AND valid PNG header (\x89PNG)!
        check(ClipboardService.copyToPasteboard(capturedImg, pasteboard: pb), "copyToPasteboard succeeds for cached JPEG after container removal")
        let pastedImgURLs = ClipboardPasteboardIO.readFileURLs(from: pb)
        check(pastedImgURLs.count == 1 && fm.fileExists(atPath: pastedImgURLs[0].path), "pasted image exposes valid existing file URL for Finder/Workspace")
        let filenamesList = pb.propertyList(forType: ClipboardPasteboardIO.filenamesPasteboardType) as? [String]
        check(filenamesList == [pastedImgURLs[0].path], "pasted image exposes NSFilenamesPboardType for WeChat/Electron")
        if let pngBytes = pb.data(forType: .png) {
            let magic = Array(pngBytes.prefix(8))
            check(magic == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "JPEG source re-encoded with genuine PNG signature on .png pasteboard type")
        } else {
            check(false, "pasted JPEG provides .png representation for browsers/rich editors")
        }
        check(pb.data(forType: .tiff) != nil, "pasted JPEG provides .tiff representation")
        check(pb.data(forType: ClipboardPasteboardIO.jpegPasteboardType) != nil, "pasted JPEG preserves original public.jpeg data")

        // 3. Write captured MP4 video entry back to pasteboard -> verify file URL + NSFilenamesPboardType!
        check(ClipboardService.copyToPasteboard(capturedVid, pasteboard: pb), "copyToPasteboard succeeds for cached MP4 after container removal")
        let pastedVidURLs = ClipboardPasteboardIO.readFileURLs(from: pb)
        check(pastedVidURLs.count == 1 && fm.fileExists(atPath: pastedVidURLs[0].path), "pasted video exposes valid file URL")
        let vidFilenames = pb.propertyList(forType: ClipboardPasteboardIO.filenamesPasteboardType) as? [String]
        check(vidFilenames == [pastedVidURLs[0].path], "pasted video exposes NSFilenamesPboardType")

        // 4. Verify missing file returns false instead of silent empty pasteboard
        let missingURL = tmp.appendingPathComponent("deleted.mp4")
        let staleVid = ClipboardEntry(title: "deleted.mp4", subtitle: "MP4", fileURL: missingURL, payloadKind: .video(missingURL))
        check(ClipboardService.copyToPasteboard(staleVid, pasteboard: pb) == false, "missing source video returns false cleanly")
        print("[ok] Live Pasteboard Image & Video Dual-Representation + Container Snapshot Roundtrip")
    }
}
