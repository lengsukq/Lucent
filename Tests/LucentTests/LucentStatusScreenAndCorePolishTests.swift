import AppKit
import Foundation
import Testing
@testable import LucentCore
@testable import LucentMedia

@Suite("Status Screen Host Bridge & Core Feature Refinements")
struct LucentStatusScreenAndCorePolishTests {
    @Test("StatusScreenOverlayService & systemControl Host Bridge manage lifecycle cleanly")
    func statusScreenHostBridgeLifecycle() {
        let shield = StatusScreenOverlayService.shared
        shield.suppressWindowPresentationForTesting = true
        defer {
            shield.dismiss()
            shield.suppressWindowPresentationForTesting = false
        }

        let activateResp = PluginHostBridgeHandlers.dispatch(
            capability: .systemControl,
            action: "setStatusScreen",
            params: [
                "preset": "clean",
                "icon": "🧹",
                "title": "擦拭键盘中",
                "subtitle": "防止误触",
                "blockInput": true,
                "keepAwake": false,
                "muteAudio": false,
                "holdSeconds": 2.5,
                "delaySeconds": 0.0
            ],
            hostContext: .default
        )
        #expect(activateResp["ok"] as? Bool == true)
        #expect(shield.isActive == true)
        #expect(shield.currentConfiguration?.preset == "clean")
        #expect(shield.currentConfiguration?.holdSeconds == 2.5)

        let statusResp = PluginHostBridgeHandlers.dispatch(
            capability: .systemControl, action: "status", params: [:], hostContext: .default
        )
        let statusData = statusResp["data"] as? [String: Any]
        #expect(statusData?["statusScreenActive"] as? Bool == true)

        let clearResp = PluginHostBridgeHandlers.dispatch(
            capability: .systemControl, action: "clearStatusScreen", params: [:], hostContext: .default
        )
        #expect(clearResp["ok"] as? Bool == true)
        #expect(shield.isActive == false)
    }

    @Test("Refined Clipboard colors, Math functions/percentages, Bilingual Unit conversions & 10 Screenshot tools")
    func coreFeatureRefinements() {
        #expect(ClipboardService.parseHexColor("#f80") == "#FF8800")
        #expect(ClipboardService.parseHexColor("rgb(14, 165, 233)") == "#0EA5E9")
        #expect(ClipboardService.hslString(fromHex: "#FF0000") == "hsl(0, 100%, 50%)")
        #expect(ClipboardService.looksLikeSensitiveSecret("normal clipboard note") == false)

        #expect(SafeMathEvaluator.evaluate("20% of 350") == "70")
        #expect(SafeMathEvaluator.evaluate("100 + 15%") == "115")
        #expect(SafeMathEvaluator.evaluate("sqrt(144) + 2^3") == "20")
        #expect(SafeMathEvaluator.evaluate("12,500 * 12") == "150000")
        #expect(UnitAndCommandEngine.evaluate("30c to f")?.resultText == "86 °F")
        #expect(UnitAndCommandEngine.evaluate("30 摄氏度转华氏度")?.resultText == "86 °F")
        #expect(UnitAndCommandEngine.evaluate("3 斤转克")?.resultText == "1500 g")
        #expect(UnitAndCommandEngine.evaluate("2h to min")?.resultText == "120 min")
        #expect(UnitAndCommandEngine.evaluate("255 in hex")?.resultText == "0xFF")
        #expect(UnitAndCommandEngine.evaluate("24px to rem")?.resultText == "1.5 rem")
        #expect(UnitAndCommandEngine.evaluate("12pt to px")?.resultText == "16 px")
        #expect(UnitAndCommandEngine.evaluate("180 deg to rad")?.resultText.contains("3.142") == true)
        #expect(UnitAndCommandEngine.evaluate("0.5 turn to 度")?.resultText == "180 deg")
        #expect(UnitAndCommandEngine.evaluate("108 km/h to m/s")?.resultText == "30 m/s")
        #expect(UnitAndCommandEngine.evaluate("10 节转 km/h")?.resultText.contains("18.52") == true)

        #expect(AnnotationToolKind.allCases.count == 11)
        #expect(AnnotationToolKind.fromShortcutKeyCode(21) == .line)
        #expect(AnnotationToolKind.fromShortcutKeyCode(28) == .spotlight)
    }

    @Test("Polyphone Chinese Pinyin indexing & plain-text pasteboard helper work reliably")
    @MainActor
    func polyphonePinyinAndPlainPasteboard() {
        let musicApp = InstalledAppItem(name: "音乐", englishName: "Music", url: URL(fileURLWithPath: "/System/Applications/Music.app"))
        let cliApp = InstalledAppItem(name: "命令行工具", englishName: "CLI", url: URL(fileURLWithPath: "/Applications/CLI.app"))
        let cqApp = InstalledAppItem(name: "重庆地图", englishName: "CQMap", url: URL(fileURLWithPath: "/Applications/CQMap.app"))
        let apps = [musicApp, cliApp, cqApp]

        let yyHits = LauncherEngine.rankCandidates(query: "yy", filter: .all, apps: apps, plugins: [])
        #expect(yyHits.contains(where: { $0.id == musicApp.id }))
        let yinyueHits = LauncherEngine.rankCandidates(query: "yinyue", filter: .all, apps: apps, plugins: [])
        #expect(yinyueHits.contains(where: { $0.id == musicApp.id }))
        let yinleHits = LauncherEngine.rankCandidates(query: "yinle", filter: .all, apps: apps, plugins: [])
        #expect(yinleHits.contains(where: { $0.id == musicApp.id }))

        let mlhHits = LauncherEngine.rankCandidates(query: "mlh", filter: .all, apps: apps, plugins: [])
        #expect(mlhHits.contains(where: { $0.id == cliApp.id }))
        let cqHits = LauncherEngine.rankCandidates(query: "chongqing", filter: .all, apps: apps, plugins: [])
        #expect(cqHits.contains(where: { $0.id == cqApp.id }))

        let expectedPath = URL(fileURLWithPath: "/tmp/demo.png").standardizedFileURL.path
        let fileEntry = ClipboardEntry(
            title: "demo.png",
            subtitle: "图片",
            fileURL: URL(fileURLWithPath: "/tmp/demo.png"),
            payloadKind: .image(URL(fileURLWithPath: "/tmp/demo.png"), CGSize(width: 64, height: 64))
        )
        #expect(ClipboardPasteboardIO.plainTextRepresentation(for: fileEntry) == expectedPath)

        let textEntry = ClipboardEntry(title: "Hello", subtitle: "文本", textValue: "  rich -> plain  ", payloadKind: .text)
        #expect(ClipboardPasteboardIO.plainTextRepresentation(for: textEntry) == "  rich -> plain  ")

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        if pb.setString("probe", forType: .string) {
            #expect(ClipboardService.copyPlainTextToPasteboard(fileEntry, pasteboard: pb) == true)
            #expect(pb.string(forType: .string) == expectedPath)
        }
    }

    @Test("Standalone window image annotation compositing preserves native alpha dimensions")
    func standaloneWindowAnnotationCompositing() throws {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 240, height: 180, bitsPerComponent: 8, bytesPerRow: 240 * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1.0))
        ctx.fill(CGRect(x: 20, y: 20, width: 200, height: 140))
        let winImg = ctx.makeImage()!

        let passthrough = try ScreenshotCompositor.compositeAnnotationsOntoWindowImage(
            windowImage: winImg, windowCanvasFrame: CGRect(x: 100, y: 100, width: 100, height: 70), annotations: []
        )
        #expect(passthrough.width == 240 && passthrough.height == 180)

        let lineAnn = ScreenshotAnnotation(
            tool: .line, color: AnnotationRGBColor.presets[0], strokeSize: .medium,
            points: [CGPoint(x: 110, y: 110), CGPoint(x: 180, y: 150)]
        )
        let composed = try ScreenshotCompositor.compositeAnnotationsOntoWindowImage(
            windowImage: winImg, windowCanvasFrame: CGRect(x: 100, y: 100, width: 100, height: 70), annotations: [lineAnn]
        )
        #expect(composed.width == 240 && composed.height == 180)
    }
}
