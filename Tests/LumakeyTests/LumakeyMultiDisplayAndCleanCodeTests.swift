import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import LumakeyCore
@testable import LumakeyFoundation
@testable import LumakeyMedia

@Suite("Multi-Display Geometry, Per-Display Capture Compositor & Zero-Legacy Clean Project Tests")
struct LumakeyMultiDisplayAndCleanCodeTests {
    private func makeSolidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) throws -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ctx.makeImage())
    }

    @Test("MultiDisplayLayout maps negative-origin, vertically stacked, and mixed-DPI displays bijectively")
    func multiDisplayCoordinateBijectionAndScale() {
        // Primary Built-in Retina: (0, 0, 1512, 982) @ 2x
        // Left 1080p External (slightly lower): (-1920, -98, 1920, 1080) @ 1x
        // Top 4K External (above primary): (0, 982, 2560, 1440) @ 2x -> Quartz y = -1440
        let layout = MultiDisplayLayout(
            screens: [
                (displayID: 1, appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                 appKitVisibleFrame: CGRect(x: 0, y: 50, width: 1512, height: 900), scale: 2.0),
                (displayID: 2, appKitFrame: CGRect(x: -1920, y: -98, width: 1920, height: 1080),
                 appKitVisibleFrame: CGRect(x: -1920, y: -98, width: 1920, height: 1055), scale: 1.0),
                (displayID: 3, appKitFrame: CGRect(x: 0, y: 982, width: 2560, height: 1440),
                 appKitVisibleFrame: CGRect(x: 0, y: 982, width: 2560, height: 1415), scale: 2.0)
            ],
            mainDisplayID: 1
        )

        #expect(layout.primaryScreenHeight == 982)
        #expect(layout.cgUnionBounds == CGRect(x: -1920, y: -1440, width: 4480, height: 2520))
        #expect(layout.canvasBounds == CGRect(x: 0, y: 0, width: 4480, height: 2520))

        for testPt in [CGPoint(x: 300, y: 400), CGPoint(x: -1200, y: 120), CGPoint(x: 800, y: 1600)] {
            let canvasPt = layout.canvasPoint(fromAppKitGlobal: testPt)
            let roundtrip = layout.appKitGlobalPoint(fromCanvas: canvasPt)
            #expect(abs(roundtrip.x - testPt.x) < 0.001 && abs(roundtrip.y - testPt.y) < 0.001)
        }

        let leftSlice = try! #require(layout.slices.first { $0.displayID == 2 })
        let mainSlice = try! #require(layout.slices.first { $0.displayID == 1 })
        let topSlice = try! #require(layout.slices.first { $0.displayID == 3 })

        // Selection solely on 1x external monitor preserves 1.0x scale
        let selOnLeft = CGRect(x: leftSlice.canvasFrame.minX + 100, y: leftSlice.canvasFrame.minY + 100, width: 400, height: 300)
        #expect(layout.effectiveScale(forSelection: selOnLeft) == 1.0)
        #expect(layout.targetSlice(forSelection: selOnLeft, fallbackPoint: .zero)?.displayID == 2)

        // Selection spanning 1x left monitor and 2x primary monitor upgrades to 2.0x scale
        let crossSel = CGRect(x: leftSlice.canvasFrame.maxX - 150, y: mainSlice.canvasFrame.minY + 100, width: 300, height: 240)
        #expect(layout.effectiveScale(forSelection: crossSel) == 2.0)
        #expect(layout.targetSlice(forSelection: crossSel, fallbackPoint: .zero)?.displayID == 1)

        // Quartz window on top display maps accurately into canvas space
        let quartzWin = CGRect(x: 200, y: -1000, width: 800, height: 600)
        let winCanvas = layout.canvasRect(fromQuartzGlobal: quartzWin)
        #expect(topSlice.canvasFrame.contains(winCanvas))
        let appKitRect = layout.appKitGlobalRect(fromCanvas: winCanvas)
        #expect(topSlice.appKitFrame.contains(appKitRect))
    }

    @Test("clampedLocalSourceRect, clampedHUDFrame, and clampedPinFrame prevent out-of-bounds multi-display errors")
    func sourceRectAndHUDClampingSafety() {
        let sliceFrame = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        // Overhanging by 0.4pt on left/top and 0.6pt on right/bottom must clamp strictly inside (0, 0, 1920, 1080)
        let overhanging = CGRect(x: 1919.6, y: -0.4, width: 1921.0, height: 1081.0)
        let local = try! #require(MultiDisplayLayout.clampedLocalSourceRect(forSelection: overhanging, in: sliceFrame))
        #expect(local.minX >= 0 && local.minY >= 0)
        #expect(local.maxX <= 1920 && local.maxY <= 1080)
        #expect(local == CGRect(x: 0, y: 0, width: 1920, height: 1080))

        // Narrow portrait secondary monitor (width 720 < preferred 820 HUD width) at negative X
        let portraitVisible = CGRect(x: -720, y: 0, width: 720, height: 1240)
        let hudFrame = MultiDisplayLayout.clampedHUDFrame(
            preferredSize: CGSize(width: 820, height: 64),
            near: CGRect(x: -600, y: 500, width: 400, height: 300),
            visibleFrame: portraitVisible
        )
        #expect(portraitVisible.contains(hudFrame))
        #expect(hudFrame.width <= 704)

        // Cross-display pin rect clamps cleanly onto dominant monitor when spanning separate Spaces
        let dualLayout = MultiDisplayLayout(
            screens: [
                (1, CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 0, y: 40, width: 1440, height: 835), 2.0),
                (2, CGRect(x: 1440, y: 0, width: 1920, height: 1080), CGRect(x: 1440, y: 0, width: 1920, height: 1055), 1.0)
            ],
            mainDisplayID: 1
        )
        let spanningPin = CGRect(x: 1300, y: 200, width: 500, height: 300) // 140pt on disp 1, 360pt on disp 2
        let clampedPin = dualLayout.clampedPinFrame(forAppKitSelection: spanningPin)
        let disp2Vis = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        #expect(disp2Vis.contains(clampedPin))
    }

    @Test("Per-display native crop preserves 1x/2x sharpness, stitches cross-display selections, and embeds PNG DPI")
    func multiDisplayCompositorAndDPIMetadata() throws {
        // Left display: 400x300 pt @ 1x (400x300 px, pure red)
        // Right display: 400x300 pt @ 2x (800x600 px, pure blue)
        let leftImg = try makeSolidImage(width: 400, height: 300, r: 220, g: 30, b: 40)
        let rightImg = try makeSolidImage(width: 800, height: 600, r: 20, g: 90, b: 230)
        let slices: [(canvasFrame: CGRect, scale: CGFloat, image: CGImage)] = [
            (CGRect(x: 0, y: 0, width: 400, height: 300), 1.0, leftImg),
            (CGRect(x: 400, y: 0, width: 400, height: 300), 2.0, rightImg)
        ]
        let canvasBounds = CGRect(x: 0, y: 0, width: 800, height: 300)

        // 1. Single-display selection on 1x monitor -> exact 100x80 px @ 1.0x (NOT upscaled to 2x!)
        let single1x = try ScreenshotCompositor.renderMultiDisplaySelection(
            slices: slices, canvasBounds: canvasBounds,
            selectionRect: CGRect(x: 50, y: 40, width: 100, height: 80), annotations: []
        )
        #expect(single1x.scale == 1.0)
        #expect(single1x.image.width == 100 && single1x.image.height == 80)

        // 2. Single-display selection on 2x monitor -> exact 200x160 px @ 2.0x
        let single2x = try ScreenshotCompositor.renderMultiDisplaySelection(
            slices: slices, canvasBounds: canvasBounds,
            selectionRect: CGRect(x: 450, y: 40, width: 100, height: 80), annotations: []
        )
        #expect(single2x.scale == 2.0)
        #expect(single2x.image.width == 200 && single2x.image.height == 160)

        // 3. Cross-display selection (50pt on left + 50pt on right = 100x60 pt @ 2.0x = 200x120 px)
        let cross = try ScreenshotCompositor.renderMultiDisplaySelection(
            slices: slices, canvasBounds: canvasBounds,
            selectionRect: CGRect(x: 350, y: 50, width: 100, height: 60), annotations: []
        )
        #expect(cross.scale == 2.0)
        #expect(cross.image.width == 200 && cross.image.height == 120)
        let crossBounds = CGRect(x: 0, y: 0, width: 200, height: 120)
        #expect(ScreenshotCompositor.samplePixelColor(in: cross.image, point: CGPoint(x: 30, y: 60), screenBounds: crossBounds) == "#DC1E28")
        #expect(ScreenshotCompositor.samplePixelColor(in: cross.image, point: CGPoint(x: 170, y: 60), screenBounds: crossBounds) == "#145AE6")

        // 4. Loupe across seam & DPI-aware PNG roundtrip
        let seamLoupe = ScreenshotCompositor.cropLoupeImage(from: slices, at: CGPoint(x: 400, y: 120), pointSize: 28)
        #expect(seamLoupe != nil && seamLoupe!.width == 56 && seamLoupe!.height == 56)

        let pngURL = try ScreenshotCompositor.saveTempCapture(single2x.image, scale: 2.0)
        defer { try? FileManager.default.removeItem(at: pngURL) }
        let nsImage = try #require(NSImage(contentsOf: pngURL))
        #expect(abs(nsImage.size.width - 100) < 0.5 && abs(nsImage.size.height - 80) < 0.5)
    }

    @Test("Window click snap, Tab-cycle hover, micro-drag slip, and SCContentFilter zero-rect fallback prevent 1x1 captures in Screenshot & GIF")
    func windowClickAndZeroPixelCaptureRegression() {
        let topWin = DetectedScreenWindow(id: 101, ownerName: "Safari", title: "Docs", frame: CGRect(x: 120, y: 80, width: 960, height: 640))
        let backWin = DetectedScreenWindow(id: 102, ownerName: "Terminal", title: "zsh", frame: CGRect(x: 80, y: 60, width: 1040, height: 700))
        let sideWin = DetectedScreenWindow(id: 103, ownerName: "Finder", title: "Downloads", frame: CGRect(x: 1180, y: 120, width: 520, height: 420))
        let windows = [topWin, backWin, sideWin]

        var lastTopID: CGWindowID?
        var cycleIdx = 0
        let clickPt = CGPoint(x: 300, y: 260)
        let hover1 = CaptureSelectionGeometry.resolveHover(at: clickPt, windows: windows, lastTopWindowID: &lastTopID, cycleIndex: &cycleIdx)
        #expect(hover1.hovered == topWin && hover1.overlapCount == 2)

        // Simulate Tab-cycling to lower overlapping window, then clicking with DragGesture(minimumDistance: 0)
        cycleIdx = 1
        let hover2 = CaptureSelectionGeometry.resolveHover(at: clickPt, windows: windows, lastTopWindowID: &lastTopID, cycleIndex: &cycleIdx)
        #expect(hover2.hovered == backWin)

        // Zero-distance click must NOT start drag and must snap to cycled window even if live hover became nil
        #expect(CaptureSelectionGeometry.shouldBeginDrag(from: clickPt, to: clickPt) == false)
        let pressCtx = SelectionCreationContext(
            startPoint: clickPt, previousSelection: nil, previousSelectedWindow: nil, pressHoveredWindow: hover2.hovered
        )
        let screenshotClick = CaptureSelectionGeometry.resolveCreationEnd(
            context: pressCtx, endPoint: clickPt, currentSelection: nil,
            currentHoveredWindow: nil, windows: windows, minimumSelectionSize: 6
        )
        #expect(screenshotClick == .snapToWindow(backWin))

        let gifClick = CaptureSelectionGeometry.resolveCreationEnd(
            context: pressCtx, endPoint: CGPoint(x: clickPt.x + 1.5, y: clickPt.y + 1.0), currentSelection: nil,
            currentHoveredWindow: nil, windows: windows, minimumSelectionSize: 12
        )
        #expect(gifClick == .snapToWindow(backWin))

        // Slight trackpad drift (4pt -> 4x3pt sub-threshold selection) over a window still snaps cleanly to window
        let slipEnd = CGPoint(x: clickPt.x + 4, y: clickPt.y + 3)
        #expect(CaptureSelectionGeometry.shouldBeginDrag(from: clickPt, to: slipEnd) == true)
        let slipRect = CaptureSelectionGeometry.rubberBandRect(from: clickPt, to: slipEnd, clampedTo: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let gifSlip = CaptureSelectionGeometry.resolveCreationEnd(
            context: pressCtx, endPoint: slipEnd, currentSelection: slipRect,
            currentHoveredWindow: nil, windows: windows, minimumSelectionSize: 12
        )
        #expect(gifSlip == .snapToWindow(backWin))

        // Clicking or twitching on empty desktop space never leaves a 1x1 / 2x2 ghost selection
        let emptyPt = CGPoint(x: 24, y: 24)
        let emptyCtx = SelectionCreationContext(
            startPoint: emptyPt, previousSelection: nil, previousSelectedWindow: nil,
            pressHoveredWindow: CaptureSelectionGeometry.topWindow(at: emptyPt, in: windows)
        )
        #expect(CaptureSelectionGeometry.resolveCreationEnd(
            context: emptyCtx, endPoint: emptyPt, currentSelection: nil,
            currentHoveredWindow: nil, windows: windows, minimumSelectionSize: 6
        ) == .restorePrevious(selection: nil, window: nil))

        // Single-clicking outside an already-selected window onto another window switches cleanly to the new window
        let switchPt = CGPoint(x: 1260, y: 240)
        let switchCtx = SelectionCreationContext(
            startPoint: switchPt, previousSelection: topWin.frame, previousSelectedWindow: topWin,
            pressHoveredWindow: CaptureSelectionGeometry.topWindow(at: switchPt, in: windows)
        )
        #expect(CaptureSelectionGeometry.resolveCreationEnd(
            context: switchCtx, endPoint: switchPt, currentSelection: topWin.frame,
            currentHoveredWindow: nil, windows: windows, minimumSelectionSize: 12
        ) == .snapToWindow(sideWin))

        // SCContentFilter.contentRect == .zero or 1x1 falls back to scWin.frame.size
        let fallbackSize = CaptureSelectionGeometry.resolvedWindowCaptureSize(
            filterContentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            fallbackWindowFrame: topWin.frame
        )
        #expect(fallbackSize == topWin.frame.size)
        #expect(CaptureSelectionGeometry.resolvedWindowCaptureSize(filterContentRect: .zero, fallbackWindowFrame: .zero) == nil)
    }

    @Test("Zero-legacy verification: deprecated schemas and bundle-root search indexes are strictly ignored")
    func zeroLegacyCleanCodeAssertions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-clean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Legacy non-optional "includeInGlobalSearch": false in overrides JSON is ignored (uses includeInGlobalSearchOverride)
        let rawOverrideJSON = Data(#"{"includeInGlobalSearch":false,"priorityBoost":20}"#.utf8)
        let decodedOverrides = try JSONDecoder().decode(PluginUserOverrides.self, from: rawOverrideJSON)
        #expect(decodedOverrides.includeInGlobalSearchOverride == nil)
        #expect(decodedOverrides.priorityBoost == 20)

        // 2. PluginSearchIndex reads strictly from PluginData/<id>/search-index.json, ignoring Plugins/<id>/search-index.json
        let pluginsRoot = dir.appendingPathComponent("Plugins", isDirectory: true)
        let plugin = try PluginSystem.scaffoldPlugin(
            id: "idx-clean", name: "Clean Index", keywords: ["ic"], description: "d",
            mode: .script, capabilities: [], resourceScopes: [], in: pluginsRoot
        )
        try Data(#"{"items":[{"id":"legacy","title":"Should Ignore"}]}"#.utf8)
            .write(to: plugin.directoryURL.appendingPathComponent("search-index.json"))
        #expect(PluginSearchIndex.indexFileURL(for: plugin, in: pluginsRoot) == nil)
        #expect(PluginSearchIndex.loadEntries(for: [plugin], in: pluginsRoot).isEmpty)
    }
}
