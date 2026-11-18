import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import LucentCore

func testV04ScreenshotCompositorAndFastIndex() throws {
    check(MediaClassifier.classifyExtension("md", isDirectory: false) == .markdown, "classifyExtension classifies md as markdown")
    check(MediaClassifier.classifyExtension("mp4", isDirectory: false) == .video, "classifyExtension classifies mp4 as video")

    let tmp = try makeTempDir("v04-fast")
    defer { try? FileManager.default.removeItem(at: tmp) }
    try "# Doc".write(to: tmp.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
    let index = try EverythingIndex.build(rootURLs: [tmp])
    let emptyHits = index.search(queryText: "", limit: 10)
    check(emptyHits.contains(where: { $0.name == "note.md" && FileManager.default.fileExists(atPath: $0.url.path) }), "EverythingIndex empty-query fast path returns valid URL")

    let width = 200, height = 120
    let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        check(false, "create synthetic screenshot CGContext")
        return
    }
    ctx.setFillColor(CGColor(srgbRed: 0x33 / 255.0, green: 0x66 / 255.0, blue: 0x99 / 255.0, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let baseCG = ctx.makeImage() else {
        check(false, "extract CGImage from synthetic context")
        return
    }

    let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)
    let hex = ScreenshotCompositor.samplePixelColor(in: baseCG, point: CGPoint(x: 50, y: 40), screenBounds: bounds)
    check(hex == "#336699", "samplePixelColor reads exact #RRGGBB pixel value (got \(hex))")

    let sel = CGRect(x: 20, y: 20, width: 100, height: 80)
    let red = AnnotationRGBColor.presets[0]
    let blue = AnnotationRGBColor.presets[4]
    let annotations: [ScreenshotAnnotation] = [
        ScreenshotAnnotation(tool: .rect, color: red, strokeSize: .small, points: [CGPoint(x: 25, y: 25), CGPoint(x: 70, y: 60)]),
        ScreenshotAnnotation(tool: .ellipse, color: blue, strokeSize: .medium, points: [CGPoint(x: 40, y: 30), CGPoint(x: 100, y: 80)]),
        ScreenshotAnnotation(tool: .arrow, color: red, strokeSize: .medium, points: [CGPoint(x: 30, y: 80), CGPoint(x: 90, y: 35)]),
        ScreenshotAnnotation(tool: .pen, color: red, strokeSize: .small, points: [CGPoint(x: 28, y: 40), CGPoint(x: 45, y: 55), CGPoint(x: 62, y: 45)]),
        ScreenshotAnnotation(tool: .highlighter, color: AnnotationRGBColor.presets[2], strokeSize: .large, points: [CGPoint(x: 35, y: 70), CGPoint(x: 105, y: 70)]),
        ScreenshotAnnotation(tool: .mosaic, color: red, strokeSize: .medium, points: [CGPoint(x: 60, y: 50), CGPoint(x: 75, y: 55)]),
        ScreenshotAnnotation(tool: .counter, color: red, strokeSize: .medium, points: [CGPoint(x: 85, y: 40)], counterIndex: 1),
        ScreenshotAnnotation(tool: .text, color: blue, strokeSize: .small, points: [CGPoint(x: 30, y: 24)], text: "Lucent")
    ]
    let cropped = try ScreenshotCompositor.renderCroppedImage(baseImage: baseCG, screenBounds: bounds, selectionRect: sel, annotations: annotations)
    check(cropped.width == 100 && cropped.height == 80, "renderCroppedImage produces exact cropped dimensions")

    let outURL = try ScreenshotCompositor.saveTempCapture(cropped, scale: 1.0)
    defer { try? FileManager.default.removeItem(at: outURL) }
    check(FileManager.default.fileExists(atPath: outURL.path), "saveTempCapture writes PNG file")
    let reloaded = NSImage(contentsOf: outURL)
    check(reloaded != nil && Int(reloaded!.size.width) >= 100, "saved screenshot PNG loads back cleanly via NSImage")

    let pix = ScreenshotCompositor.makePixelatedPreview(from: baseCG, cellPixelSize: 10)
    check(pix != nil && pix!.width == 20 && pix!.height == 12, "makePixelatedPreview downsamples CGImage cleanly")

    let ocrURL = tmp.appendingPathComponent("ocr-fast-check.png")
    try renderTextPNG(text: "测试识字 Lucent 2026", to: ocrURL)
    let ocrStarted = Date()
    let ocrResult = try VisionService.analyzeTextAndBarcodes(at: ocrURL)
    let ocrElapsed = Date().timeIntervalSince(ocrStarted)
    check(ocrElapsed < 3.0, "Vision OCR finishes rapidly without ANE stall (elapsed: \(String(format: "%.2f", ocrElapsed))s)")
    check(ocrResult.recognizedText.contains("Lucent"), "Vision OCR recognizes Chinese + English text cleanly")
    print("[ok] v0.4.1 ScreenshotCompositor + Fast CPU Vision OCR (\(String(format: "%.2f", ocrElapsed))s) + Fast Index")
}

func testV05SystemMonitor() throws {
    let sampler = SystemMonitorSampler()
    _ = sampler.sample()
    usleep(35_000)
    var snap = sampler.sample()
    for _ in 0..<15 { snap = sampler.sample() }
    check(snap.memoryTotalBytes > 1_000_000_000, "system monitor reads positive total physical RAM")
    check(snap.memoryUsedBytes > 0 && snap.memoryUsedBytes <= snap.memoryTotalBytes, "system monitor used memory bounded")
    check(snap.cpuTotalPercent >= 0 && snap.cpuTotalPercent <= 100.0, "system monitor CPU percent in 0...100")
    check(snap.estimatedFrequencyGHz > 0.2 && snap.maxFrequencyGHz >= snap.estimatedFrequencyGHz, "system monitor DVFS frequency valid")
    check(!snap.chipBrand.isEmpty && snap.systemWatts >= 0, "system monitor chip brand & watts valid")
    check(snap.netDownBytesPerSec >= 0 && snap.netUpBytesPerSec >= 0, "system monitor net rate non-negative")
    check(snap.diskTotalGB > 1.0 && !snap.menuBarCompactText.isEmpty, "system monitor disk & menu bar readout")

    let tmp = try makeTempDir("v05-telemetry")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let cfgURL = tmp.appendingPathComponent("telemetry.json")
    var cfg = SystemMonitorConfig()
    cfg.displayMode = .edgeAutoHide; cfg.dockedEdgeRaw = "right"; cfg.showInMenuBar = false
    cfg.save(to: cfgURL)
    check(SystemMonitorConfig.load(from: cfgURL) == cfg, "SystemMonitorConfig JSON persistence roundtrip")
    check(UnitAndCommandEngine.matchCommands(query: "监控", volumes: []).contains(where: { $0.command == .toggleSystemMonitor }), "monitor command matched")
    print("[ok] v0.5 SystemMonitorSampler (CPU/Freq/Mem/Watts/Net/Disk) + Config + Command")
}

func testV051MultiRootEverythingWorkspaceAndDefaults() throws {
    let defaultTelemetry = SystemMonitorConfig()
    check(!defaultTelemetry.floatingEnabled && !defaultTelemetry.showInMenuBar && !MosConfig().enabled, "fresh install defaults OFF")

    var metricCfg = SystemMonitorConfig()
    metricCfg.menuShowCPU = true; metricCfg.menuShowFreq = true; metricCfg.menuShowMemory = true
    metricCfg.menuShowPower = false; metricCfg.menuShowNet = false
    var sampleSnap = SystemTelemetrySnapshot.placeholder
    sampleSnap.cpuTotalPercent = 24; sampleSnap.estimatedFrequencyGHz = 3.21; sampleSnap.memoryPercent = 58
    let barText = metricCfg.formatMenuBarText(from: sampleSnap)
    check(barText.contains("24%") && barText.contains("3.21G") && barText.contains("M58%"), "custom menu bar telemetry metrics formatted")

    let tmp = try makeTempDir("v051-multi-posix")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let rootA = tmp.appendingPathComponent("LocalHome")
    let rootB = tmp.appendingPathComponent("ExternalDisk")
    try FileManager.default.createDirectory(at: rootA.appendingPathComponent("Docs"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rootB.appendingPathComponent("Movies"), withIntermediateDirectories: true)
    try "hello world".write(to: rootA.appendingPathComponent("Docs/guide.md"), atomically: true, encoding: .utf8)
    try Data(repeating: 0xAB, count: 512).write(to: rootB.appendingPathComponent("Movies/clip.mp4"))

    let idxA = try EverythingIndex.build(rootURLs: [rootA], maxNodes: 1000)
    let idxB = try EverythingIndex.build(rootURLs: [rootB], maxNodes: 1000)
    let videoHits = idxA.merging(idxB).search(queryText: "video: path:ExternalDisk", limit: 10)
    check(videoHits.count == 1 && videoHits[0].name == "clip.mp4" && videoHits[0].sizeBytes == 512, "merged POSIX EverythingIndex finds external volume video")

    let entries = try DirectoryScanner.scanDirectory(at: rootB, includeHidden: false)
        + [FileEntry(url: rootA.appendingPathComponent("Docs/guide.md"), name: "guide.md", isDirectory: false, sizeBytes: 11, modifiedAt: Date(), createdAt: Date().addingTimeInterval(-100), extensionLowercased: "md", mediaKind: .markdown)]
    let sortedExt = DirectoryScanner.sortEntries(entries, by: .ext, order: .ascending, foldersFirst: false)
    check(sortedExt.first?.name == "Movies", "sort by ext with foldersFirst=false sorts directories by empty extension first")
    check(WorkspaceMediaFilter.document.matches(entries.last!) && !WorkspaceMediaFilter.image.matches(entries.last!), "WorkspaceMediaFilter document/image matching")
    print("[ok] v0.5.1 Default-OFF Telemetry + POSIX Multi-Root Everything + Workspace Sort/Filter")
}

func testV053VideoCompatAndCodeSigning() throws {
    let tmp = try makeTempDir("v053-video")
    defer { try? FileManager.default.removeItem(at: tmp) }
    let mp4URL = tmp.appendingPathComponent("sample-hev1.mp4")

    var ftyp = Data([0x00, 0x00, 0x00, 0x10]) + Data("ftypisom".utf8) + Data([0, 0, 0, 0])
    let moovPayload = Data(repeating: 0x00, count: 12)
        + Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
        + Data(repeating: 0x11, count: 16)
    let moovSize = UInt32(8 + moovPayload.count).bigEndian
    let moov = withUnsafeBytes(of: moovSize) { Data($0) } + Data("moov".utf8) + moovPayload
    let mdatPayload = Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) + Data(repeating: 0xAA, count: 24)
    let mdatSize = UInt32(8 + mdatPayload.count).bigEndian
    let mdat = withUnsafeBytes(of: mdatSize) { Data($0) } + Data("mdat".utf8) + mdatPayload
    ftyp.append(moov); ftyp.append(mdat)
    try ftyp.write(to: mp4URL)

    let scan = Hev1ResourceLoader.findHev1SampleEntryOffsets(in: mp4URL)
    check(scan.fileSize == Int64(ftyp.count) && scan.offsets == [Int64(16 + 8 + 12)], "Hev1ResourceLoader finds moov hev1 sample entry and ignores mdat bytes")

    let signStatus = CodeSigningInspector.inspect(bundleURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
    check(!signStatus.badgeTitle.isEmpty && !signStatus.bundleIdentifier.isEmpty, "CodeSigningInspector inspects macOS app bundle")
    print("[ok] v0.5.3 Hev1ResourceLoader Zero-Copy Patch + CodeSigningInspector")
}

func testV060NetworkTrafficAndAppCache() throws {
    let csv1 = """
    ,interface,state,bytes_in,bytes_out,
    apsd.405,,,5519,10159,
    tcp4 198.18.0.1:58910<->17.57.145.26:5223,utun1024,Established,5519,10159,
    Safari.888,,,205000,45000,
    tcp4 192.168.1.5:51234<->142.250.190.78:443,en1,Established,205000,45000,
    launchd.1,,,0,0,
    tcp4 *:445<->*:*,,Listen,,,
    """
    let csv2 = """
    ,interface,state,bytes_in,bytes_out,
    apsd.405,,,5519,10159,
    tcp4 198.18.0.1:58910<->17.57.145.26:5223,utun1024,Established,5519,10159,
    Safari.888,,,307400,65480,
    tcp4 192.168.1.5:51234<->142.250.190.78:443,en1,Established,307400,65480,
    launchd.1,,,0,0,
    tcp4 *:445<->*:*,,Listen,,,
    """
    let pass1 = NetworkTrafficParser.parseNettopCSV(csv1, previous: [:], elapsed: 0) { _, name in (name, nil, nil) }
    let pass2 = NetworkTrafficParser.parseNettopCSV(csv2, previous: pass1.counters, elapsed: 2.0) { _, name in
        (name == "Safari" ? "Safari" : name, nil, nil)
    }
    check(pass2.snapshot.processes.count == 3 && pass2.snapshot.externalHostCount == 2, "parseNettopCSV parses processes and hosts")
    if let safari = pass2.snapshot.processes.first(where: { $0.pid == 888 }) {
        check(abs(safari.downBytesPerSec - 51_200) < 1.0 && abs(safari.upBytesPerSec - 10_240) < 1.0 && safari.connections.first?.serviceTag == "HTTPS", "Safari delta & HTTPS tag")
    } else { check(false, "Safari process parsed") }
    check(pass2.snapshot.processes.first(where: { $0.pid == 405 })?.connections.first?.serviceTag == "TUN · Apple 推送", "apsd utun tag")
    check(pass2.snapshot.processes.first(where: { $0.pid == 1 })?.connections.first?.isListening == true, "launchd Listen tag")
    check(!NetworkTrafficSampler().sample().processes.isEmpty, "live NetworkTrafficSampler collects host sockets without root")

    let tmpRoot = try makeTempDir("v060-cache")
    defer { try? FileManager.default.removeItem(at: tmpRoot) }
    let clipDir = tmpRoot.appendingPathComponent("lucent-clipboard", isDirectory: true)
    let cinemaDir = tmpRoot.appendingPathComponent("lucent-cinema", isDirectory: true)
    let supportDir = tmpRoot.appendingPathComponent("Support", isDirectory: true)
    for d in [clipDir, cinemaDir, supportDir] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

    let purgeClip = clipDir.appendingPathComponent("a.png")
    let keepClip = clipDir.appendingPathComponent("keep.png")
    let pinFile = tmpRoot.appendingPathComponent("lucent-pin-1.png")
    let remuxFile = cinemaDir.appendingPathComponent("remux.mp4")
    let configFile = supportDir.appendingPathComponent("mos-config.json")
    try Data(repeating: 1, count: 128).write(to: purgeClip)
    try Data(repeating: 2, count: 64).write(to: keepClip)
    try Data(repeating: 3, count: 256).write(to: pinFile)
    try Data(repeating: 4, count: 512).write(to: remuxFile)
    try Data(repeating: 5, count: 32).write(to: configFile)

    let before = AppCacheService.inspectAll(tempRoot: tmpRoot, appSupportRoot: supportDir, inMemoryEstimatedBytes: 1024, inMemoryItemCount: 5)
    check(before.purgeableBytes == 128 + 64 + 256 + 512 && before.protectedBytes == 32, "AppCacheService sums purgeable and protected bytes")
    let freed = AppCacheService.clearAllPurgeable(protectedURLs: [keepClip], tempRoot: tmpRoot)
    check(freed == 128 + 256 + 512 && !FileManager.default.fileExists(atPath: purgeClip.path) && FileManager.default.fileExists(atPath: keepClip.path) && FileManager.default.fileExists(atPath: configFile.path), "clearAllPurgeable preserves protected files")
    check(UnitAndCommandEngine.matchCommands(query: "流量", volumes: []).contains(where: { $0.command == .openNetworkMonitor }), "traffic command")
    check(UnitAndCommandEngine.matchCommands(query: "缓存", volumes: []).contains(where: { $0.command == .openCacheManager }), "cache command")
    print("[ok] v0.6.0 NetworkTrafficParser/Sampler + AppCacheService + Commands")
}

func testV061PreviewAutoPause() {
    let player = AVPlayer()
    let token = UUID()
    PreviewPlaybackRegistry.shared.register(token: token, player: player)
    check(PreviewPlaybackRegistry.shared.activeCount >= 1, "PreviewPlaybackRegistry tracks active inline AVPlayer")
    player.play()
    let ep0 = PreviewPlaybackRegistry.shared.pauseEpoch
    PreviewPlaybackRegistry.shared.pauseAll()
    check(player.rate == 0 && player.timeControlStatus == .paused && PreviewPlaybackRegistry.shared.pauseEpoch == ep0 + 1, "pauseAll pauses registered AVPlayer")
    PreviewPlaybackRegistry.shared.unregister(token: token)
    check(PreviewPlaybackRegistry.shared.activeCount == 0, "PreviewPlaybackRegistry unregisters dismantled player")
    print("[ok] v0.6.1 PreviewPlaybackRegistry Auto-Pause")
}

func testV062SystemPulseEdgeOrientation() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let topEdge = PulseDockEdge.detectSnapEdge(frame: CGRect(x: 520, y: 850, width: 356, height: 34), visibleFrame: screen)
    check(topEdge == .top && topEdge.isHorizontalStrip && !topEdge.isVerticalColumn, ".top renders horizontally")
    let leftEdge = PulseDockEdge.detectSnapEdge(frame: CGRect(x: 10, y: 400, width: 58, height: 182), visibleFrame: screen)
    check(leftEdge == .left && leftEdge.isVerticalColumn, "detectSnapEdge returns vertical .left")
    let rightEdge = PulseDockEdge.detectSnapEdge(frame: CGRect(x: 1370, y: 400, width: 58, height: 182), visibleFrame: screen)
    check(rightEdge == .right && rightEdge.isVerticalColumn, "detectSnapEdge returns vertical .right")
    let centerEdge = PulseDockEdge.detectSnapEdge(frame: CGRect(x: 560, y: 400, width: 354, height: 318), visibleFrame: screen)
    check(centerEdge == .none && centerEdge.isHorizontalStrip, "center desktop stays unlocked .none")
    check(PulseDockEdge.nearestEdge(for: CGRect(x: 680, y: 780, width: 100, height: 100), visibleFrame: screen) == .top, "nearestEdge detects top edge")
    print("[ok] v0.6.2 PulseDockEdge Top Horizontal & Side Vertical Orientation")
}
