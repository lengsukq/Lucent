import AppKit
import Foundation
import LucentCore

@discardableResult
func check(_ condition: Bool, _ message: String) -> Bool {
    if !condition {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
    return true
}

func makeTempDir(_ label: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-check-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func renderTextPNG(text: String, to url: URL) throws {
    let width = 480
    let height = 140
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 42, weight: .bold),
        .foregroundColor: NSColor.black
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: 28, y: 44))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

do {
    L10n.setCurrent(.zhHans)
    if CommandLine.arguments.contains("--sandbox-safe") {
        try testV099ScriptLibraryAndMCP()
        try testV095HomeLayoutAndMCPOrchestration()
        try testClipboardMediaCaptureAndPasteModel()
        try testV089PluginStoreAndSmartSniffer()
        try testV088PluginNativeExperience()
        try testV087LocalSecretVaultAndLazyLoading()
        try testV086BilingualSystem()
        try testV085BuiltInThemes()
        try testV083PluginV4CustomizationAndFusion()
        try testPluginAndMCPSubprocess()
        try testDirectoryAndBatchRename()
        try testEverythingLauncherUnitsAndClipboard()
        try testV03MarkdownOmniMosAndMemory()
        try testV05SystemMonitor()
        try testV051MultiRootEverythingWorkspaceAndDefaults()
        try testV053VideoCompatAndCodeSigning()
        testV061PreviewAutoPause()
        testV062SystemPulseEdgeOrientation()
        try testV065PerformanceCompactIndexHeaderAndFormatters()
        try testV070AppUsageAndPinning()
        try testV070HotKeyConflict()
        print("ALL SANDBOX-SAFE LUCENT CHECKS PASSED")
        exit(0)
    }
    try testVolumeAndMedia()
    try testDirectoryAndBatchRename()
    try testEverythingLauncherUnitsAndClipboard()
    try testPluginAndMCPSubprocess()
    try testV03MarkdownOmniMosAndMemory()
    try testV04ScreenshotCompositorAndFastIndex()
    try testV05SystemMonitor()
    try testV051MultiRootEverythingWorkspaceAndDefaults()
    try testV053VideoCompatAndCodeSigning()
    try testV060NetworkTrafficAndAppCache()
    testV061PreviewAutoPause()
    testV062SystemPulseEdgeOrientation()
    try testV063BinarySnapshotFSEventsAndDirCache()
    try testV064ScreenshotAutoPasteboardAndRestore()
    try testV065PerformanceCompactIndexHeaderAndFormatters()
    try testV070CleanPerf()
    try testV070AppUsageAndPinning()
    try testV070GifRecorder()
    try testV070HotKeyConflict()
    try testV070BackupAndWebDAV()
    try testV070PluginsAndToolkit()
    try testV081PluginV3AndMCP()
    try testV082PluginV31ArchitectureHardening()
    try testV083PluginV4CustomizationAndFusion()
    try testV085BuiltInThemes()
    try testV086BilingualSystem()
    try testV087LocalSecretVaultAndLazyLoading()
    try testV088PluginNativeExperience()
    try testV089PluginStoreAndSmartSniffer()
    try testV095HomeLayoutAndMCPOrchestration()
    try testV099ScriptLibraryAndMCP()
    try testClipboardMediaCaptureAndPasteModel()
    try testLivePasteboardImageAndVideoRoundtrip()
    try testV070Wave2Integration()
    try testV071WorkspaceOperations()
    try testV080LumaLink()
    print("ALL LUCENT CHECKS PASSED")
} catch {
    fputs("UNEXPECTED ERROR: \(error)\n", stderr)
    exit(1)
}
