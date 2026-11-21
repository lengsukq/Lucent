import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentMedia

@Suite("Screenshot Vector Editor, Curved Arrows, Multiply Highlighter, Lazy Pasteboard & Scrolling Stitcher Tests")
struct LucentAirSnipUpgradesTests {
    private func makeDocumentImage(
        width: Int,
        height: Int,
        headerRows: Int,
        footerRows: Int,
        scrollOffset: Int,
        totalDocHeight: Int = 600
    ) throws -> CGImage {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let srcRow: Int
            let isHeader = y < headerRows
            let isFooter = y >= height - footerRows
            if isHeader {
                srcRow = y
            } else if isFooter {
                srcRow = totalDocHeight - footerRows + (y - (height - footerRows))
            } else {
                srcRow = min(totalDocHeight - 1, scrollOffset + (y - headerRows))
            }
            for x in 0..<width {
                let idx = (y * width + x) * 4
                if isHeader {
                    rgba[idx] = 32; rgba[idx + 1] = 44; rgba[idx + 2] = 68; rgba[idx + 3] = 255
                } else if isFooter {
                    rgba[idx] = 48; rgba[idx + 1] = 52; rgba[idx + 2] = 60; rgba[idx + 3] = 255
                } else {
                    rgba[idx] = UInt8((srcRow * 17 + x * 3) & 0xFF)
                    rgba[idx + 1] = UInt8((srcRow * 31 + (srcRow / 7) * 53) & 0xFF)
                    rgba[idx + 2] = UInt8((srcRow * 47 + x * 5) & 0xFF)
                    rgba[idx + 3] = 255
                }
            }
        }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return try rgba.withUnsafeMutableBytes { raw -> CGImage in
            let ctx = try #require(CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(ctx.makeImage())
        }
    }

    @Test("ADR 0023 draw-first hit test, Shift geometry snapping, S-curve arrow handles, and corner-radius transform")
    func vectorAnnotationGeometryAndHitTesting() {
        let spotlight = ScreenshotAnnotation(
            tool: .spotlight,
            color: AnnotationRGBColor.presets[0],
            strokeSize: .medium,
            points: [CGPoint(x: 40, y: 40), CGPoint(x: 240, y: 180)]
        )
        // 1. Inside unselected/selected shape while using an active drawing tool -> interiorSelectOrDraw (never blocks drawing on top!)
        let interiorHit = AnnotationGeometry.hitTest(
            at: CGPoint(x: 120, y: 110),
            annotations: [spotlight],
            selectedID: spotlight.id,
            activeTool: .arrow,
            forceMoveModifier: false
        )
        #expect(interiorHit == .interiorSelectOrDraw(spotlight.id))

        // 2. Pressing on 6pt bounding border OR holding Command/Move tool -> borderMove
        let borderHit = AnnotationGeometry.hitTest(
            at: CGPoint(x: 42, y: 100),
            annotations: [spotlight],
            selectedID: spotlight.id,
            activeTool: .arrow,
            forceMoveModifier: false
        )
        #expect(borderHit == .borderMove(spotlight.id))

        let cmdInteriorHit = AnnotationGeometry.hitTest(
            at: CGPoint(x: 120, y: 110),
            annotations: [spotlight],
            selectedID: nil,
            activeTool: .arrow,
            forceMoveModifier: true
        )
        #expect(cmdInteriorHit == .borderMove(spotlight.id))

        // 3. Shift snapping: square box for rect & 45-degree snap for arrow
        let sq = AnnotationGeometry.snapEndpoint(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 60), tool: .rect, shiftHeld: true)
        #expect(abs((sq.x - 10) - (sq.y - 20)) < 0.001)

        let diag = AnnotationGeometry.snapEndpoint(from: .zero, to: CGPoint(x: 100, y: 92), tool: .arrow, shiftHeld: true)
        #expect(abs(diag.x - diag.y) < 0.01)

        // 4. Straight arrow -> drag curveControl1 -> becomes 4-point cubic Bezier S-curve with truncated shaft
        let straightArrow = ScreenshotAnnotation(
            tool: .arrow, color: AnnotationRGBColor.presets[0], strokeSize: .large,
            points: [CGPoint(x: 20, y: 100), CGPoint(x: 200, y: 100)]
        )
        let curved = AnnotationGeometry.transformed(
            straightArrow, handle: .curveControl1, to: CGPoint(x: 80, y: 30), shiftHeld: false
        )
        #expect(curved.points.count == 4)
        let resolved = try! #require(AnnotationGeometry.resolveArrow(curved))
        #expect(resolved.isCurved == true)
        #expect(hypot(resolved.tip.x - resolved.shaftEnd.x, resolved.tip.y - resolved.shaftEnd.y) > 4)

        // 5. Corner-radius handle clamps within half of shortest side
        let rectItem = ScreenshotAnnotation(
            tool: .rect, color: AnnotationRGBColor.presets[1], strokeSize: .medium,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 60)]
        )
        let rounded = AnnotationGeometry.transformed(rectItem, handle: .cornerRadius, to: CGPoint(x: 20, y: 50), shiftHeld: false)
        #expect(rounded.cornerRadius == 30)
    }

    @Test("Multiply highlighter preserves dark text, Gaussian blur & gradients composite cleanly, and multi-format templates work")
    @MainActor
    func compositorBlendModesLazyPasteboardAndExportFormats() throws {
        // White page with a dark text bar in the middle
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 200 * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 40, y: 50, width: 120, height: 20))
        let page = try #require(ctx.makeImage())

        let yellow = AnnotationRGBColor(red: 1.0, green: 0.9, blue: 0.0)
        let marker = ScreenshotAnnotation(
            tool: .highlighter, color: yellow, strokeSize: .large,
            points: [CGPoint(x: 20, y: 60), CGPoint(x: 180, y: 60)]
        )
        let gradArrow = ScreenshotAnnotation(
            tool: .arrow, color: yellow, gradient: AnnotationGradientPreset.presets[0],
            strokeSize: .medium, lineStyle: .dashed,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 5), CGPoint(x: 120, y: 35), CGPoint(x: 170, y: 20)]
        )
        let counterWithArrow = ScreenshotAnnotation(
            tool: .counter, color: AnnotationRGBColor.presets[0], strokeSize: .medium,
            points: [CGPoint(x: 30, y: 95), CGPoint(x: 90, y: 95)], counterIndex: 3
        )
        let blurBox = ScreenshotAnnotation(
            tool: .blur, color: yellow, strokeSize: .medium, cornerRadius: 8,
            points: [CGPoint(x: 130, y: 40), CGPoint(x: 170, y: 80)]
        )

        let out = try ScreenshotCompositor.renderCroppedImage(
            baseImage: page,
            screenBounds: CGRect(x: 0, y: 0, width: 200, height: 120),
            selectionRect: CGRect(x: 0, y: 0, width: 200, height: 120),
            annotations: [marker, gradArrow, counterWithArrow, blurBox]
        )
        // Multiply over dark text at (80, 60) must stay dark rather than washing out toward yellow!
        let darkSample = try #require(ScreenshotCompositor.samplePixelRGB(in: out, point: CGPoint(x: 80, y: 60), screenBounds: CGRect(x: 0, y: 0, width: 200, height: 120)))
        #expect(darkSample.0 < 40 && darkSample.1 < 40 && darkSample.2 < 40)

        // Lazy pasteboard provider encodes PNG & TIFF on demand (and installs on pboard when XPC is available)
        let encodedLazyPNG = LazyImagePasteboardProvider.encodeData(cgImage: out, scale: 2.0, utType: .png)
        #expect(encodedLazyPNG != nil && encodedLazyPNG!.count > 64)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        if pb.setString("probe", forType: .string) {
            #expect(ScreenshotCompositor.copyImageToPasteboard(out, scale: 2.0, lazy: true, to: pb) == true)
            let pngBytes = pb.data(forType: .png)
            #expect(pngBytes != nil && pngBytes!.count > 64)
        }

        // Multi-format export (PNG & JPEG) + filename template collision numbering
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lucent-exp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fixedDate = Date(timeIntervalSince1970: 1_763_622_000)
        let baseName = CaptureFileNameFormatter.formatBaseName(template: "Shot_{app}_{date}", appName: "Xcode/Beta", date: fixedDate)
        #expect(baseName.hasPrefix("Shot_Xcode-Beta_"))

        let jpg1 = CaptureFileNameFormatter.uniqueFileURL(in: tmp, baseName: baseName, format: .jpeg)
        try ScreenshotCompositor.writeEncodedImage(out, scale: 2.0, format: .jpeg, to: jpg1)
        #expect(FileManager.default.fileExists(atPath: jpg1.path))
        let jpg2 = CaptureFileNameFormatter.uniqueFileURL(in: tmp, baseName: baseName, format: .jpeg)
        #expect(jpg2.lastPathComponent.hasSuffix("-1.jpg"))

        let pngURL = CaptureFileNameFormatter.uniqueFileURL(in: tmp, baseName: baseName, format: .png)
        try ScreenshotCompositor.writeEncodedImage(out, scale: 2.0, format: .png, to: pngURL)
        #expect(FileManager.default.fileExists(atPath: pngURL.path))
    }

    @Test("ScrollingCaptureStitcher deduplicates sticky header/footer, stitches downward & upward scrolls, and supports undo")
    func scrollingCaptureStitcherDownUpAndUndo() throws {
        // Viewport: 120x160 px with 20px sticky header + 20px sticky footer (120px scrollable window)
        let f0 = try makeDocumentImage(width: 120, height: 160, headerRows: 20, footerRows: 20, scrollOffset: 0)
        let f1 = try makeDocumentImage(width: 120, height: 160, headerRows: 20, footerRows: 20, scrollOffset: 50)
        let f2 = try makeDocumentImage(width: 120, height: 160, headerRows: 20, footerRows: 20, scrollOffset: 95)

        let stitcher = ScrollingCaptureStitcher(maxPixelHeight: 4_000)
        #expect(stitcher.pushFrame(f0) == .initialized(height: 160))
        // Pushing identical frame is ignored
        #expect(stitcher.pushFrame(f0) == .unchanged)

        let r1 = stitcher.pushFrame(f1)
        #expect(r1 == .appendedDown(addedRows: 50, totalHeight: 210))

        let r2 = stitcher.pushFrame(f2)
        #expect(r2 == .appendedDown(addedRows: 45, totalHeight: 255))

        let full = try #require(stitcher.makeComposedImage())
        #expect(full.width == 120 && full.height == 255)

        // Undo last segment cleanly reverts to 210px height
        #expect(stitcher.canUndo == true)
        #expect(stitcher.undoLastSegment() == true)
        let reverted = try #require(stitcher.makeComposedImage())
        #expect(reverted.height == 210)

        // Upward scroll (e.g., scrolling up through chat messages from offset 100 -> 60)
        let upStitcher = ScrollingCaptureStitcher()
        let u0 = try makeDocumentImage(width: 120, height: 160, headerRows: 16, footerRows: 16, scrollOffset: 100)
        let u1 = try makeDocumentImage(width: 120, height: 160, headerRows: 16, footerRows: 16, scrollOffset: 60)
        _ = upStitcher.pushFrame(u0)
        #expect(upStitcher.pushFrame(u1) == .appendedUp(addedRows: 40, totalHeight: 200))
    }
}
