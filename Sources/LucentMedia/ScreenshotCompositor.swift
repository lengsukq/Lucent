import AppKit
import CoreGraphics
import CoreImage
import Foundation
import LucentFoundation
import LucentSearch

public enum ScreenshotCompositor {
    // CIContext is documented thread-safe by Apple, but macOS 15.x SDK headers do not mark it Sendable yet.
    private final class CIContextBox: @unchecked Sendable {
        let context = CIContext(options: [.useSoftwareRenderer: false])
    }
    private static let sharedCIContextBox = CIContextBox()

    public static func samplePixelColor(in cgImage: CGImage, point: CGPoint, screenBounds: CGRect) -> String {
        guard let (r, g, b) = samplePixelRGB(in: cgImage, point: point, screenBounds: screenBounds) else {
            return "#000000"
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public static func samplePixelRGBString(in cgImage: CGImage, point: CGPoint, screenBounds: CGRect) -> String {
        guard let (r, g, b) = samplePixelRGB(in: cgImage, point: point, screenBounds: screenBounds) else {
            return "rgb(0, 0, 0)"
        }
        return "rgb(\(r), \(g), \(b))"
    }

    public static func makePixelatedPreview(from cgImage: CGImage, cellPixelSize: Int = 16) -> CGImage? {
        let step = max(4, cellPixelSize)
        let smallW = max(2, cgImage.width / step)
        let smallH = max(2, cgImage.height / step)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: smallW, height: smallH, bitsPerComponent: 8, bytesPerRow: smallW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        return ctx.makeImage()
    }

    public static func makeBlurredPreview(from cgImage: CGImage, radius: Double = 18.0) -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard extent.width >= 2, extent.height >= 2 else { return nil }
        let ciInput = CIImage(cgImage: cgImage).clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(max(2.0, radius), forKey: kCIInputRadiusKey)
        guard let out = filter.outputImage?.cropped(to: extent) else { return nil }
        return sharedCIContextBox.context.createCGImage(out, from: extent)
    }

    public static func renderCroppedImage(
        baseImage: CGImage,
        screenBounds: CGRect,
        selectionRect: CGRect,
        annotations: [ScreenshotAnnotation]
    ) throws -> CGImage {
        let clamped = selectionRect.intersection(screenBounds).standardized
        guard clamped.width >= 2, clamped.height >= 2 else {
            throw LucentError.visionFailed("截图选区尺寸过小。")
        }
        let scaleX = CGFloat(baseImage.width) / max(screenBounds.width, 1)
        let scaleY = CGFloat(baseImage.height) / max(screenBounds.height, 1)
        let pixelRect = CGRect(
            x: max(0, floor((clamped.minX - screenBounds.minX) * scaleX)),
            y: max(0, floor((clamped.minY - screenBounds.minY) * scaleY)),
            width: max(2, round(clamped.width * scaleX)),
            height: max(2, round(clamped.height * scaleY))
        )
        guard let cropped = baseImage.cropping(to: pixelRect) else {
            throw LucentError.visionFailed("无法裁剪选中区域图像。")
        }
        if annotations.isEmpty { return cropped }
        return try overlayAnnotations(onto: cropped, selectionRect: clamped, scaleX: scaleX, scaleY: scaleY, annotations: annotations)
    }

    public static func compositeAnnotationsOntoWindowImage(
        windowImage: CGImage,
        windowCanvasFrame: CGRect,
        annotations: [ScreenshotAnnotation]
    ) throws -> CGImage {
        if annotations.isEmpty { return windowImage }
        let w = windowImage.width, h = windowImage.height
        let scale = max(1.0, round(CGFloat(w) / max(windowCanvasFrame.width, 1)))
        let padX = max(0, (CGFloat(w) / scale - windowCanvasFrame.width) / 2.0)
        let padY = max(0, (CGFloat(h) / scale - windowCanvasFrame.height) / 2.0)
        let effectiveOrigin = CGPoint(x: windowCanvasFrame.minX - padX, y: windowCanvasFrame.minY - padY)
        return try overlayAnnotations(
            onto: windowImage,
            selectionRect: CGRect(origin: effectiveOrigin, size: CGSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)),
            spotlightSelection: windowCanvasFrame,
            scaleX: scale,
            scaleY: scale,
            annotations: annotations
        )
    }

    static func overlayAnnotations(
        onto baseCropped: CGImage,
        selectionRect: CGRect,
        spotlightSelection: CGRect? = nil,
        scaleX: CGFloat,
        scaleY: CGFloat,
        annotations: [ScreenshotAnnotation]
    ) throws -> CGImage {
        let w = baseCropped.width, h = baseCropped.height
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LucentError.visionFailed("无法创建标注合成画布。")
        }
        ctx.draw(baseCropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scaleX, y: -scaleY)
        ctx.translateBy(x: -selectionRect.minX, y: -selectionRect.minY)
        for item in annotations where item.tool == .blur || item.tool == .mosaic {
            drawAnnotationShape(item, into: ctx, baseCropped: baseCropped, origin: selectionRect.origin, scaleX: scaleX, scaleY: scaleY)
        }
        let spotlights = annotations.filter { $0.tool == .spotlight }
        if !spotlights.isEmpty {
            drawSpotlights(spotlights, selectionRect: spotlightSelection ?? selectionRect, in: ctx)
        }
        for item in annotations where item.tool != .spotlight && item.tool != .blur && item.tool != .mosaic {
            drawAnnotationShape(item, into: ctx, baseCropped: baseCropped, origin: selectionRect.origin, scaleX: scaleX, scaleY: scaleY)
        }
        ctx.restoreGState()
        guard let result = ctx.makeImage() else {
            throw LucentError.visionFailed("导出合成截图失败。")
        }
        return result
    }

    static func samplePixelRGB(in cgImage: CGImage, point: CGPoint, screenBounds: CGRect) -> (UInt8, UInt8, UInt8)? {
        guard screenBounds.width > 0, screenBounds.height > 0, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let px = max(0, min(cgImage.width - 1, Int((point.x - screenBounds.minX) * CGFloat(cgImage.width) / screenBounds.width)))
        let py = max(0, min(cgImage.height - 1, Int((point.y - screenBounds.minY) * CGFloat(cgImage.height) / screenBounds.height)))
        var pixel: [UInt8] = [0, 0, 0, 0]
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: -px, y: -(cgImage.height - 1 - py), width: cgImage.width, height: cgImage.height))
        return (pixel[0], pixel[1], pixel[2])
    }

    static func blurSubimage(_ baseCropped: CGImage, pixelRect: CGRect, radius: Double) -> CGImage? {
        let clamped = pixelRect.intersection(CGRect(x: 0, y: 0, width: baseCropped.width, height: baseCropped.height)).integral
        guard clamped.width >= 2, clamped.height >= 2, let sub = baseCropped.cropping(to: clamped) else { return nil }
        return makeBlurredPreview(from: sub, radius: radius)
    }
}
