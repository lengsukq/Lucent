import CoreGraphics
import Foundation
import LumakeyFoundation

public extension ScreenshotCompositor {
    static func sampleColorFromSlices(
        _ slices: [(canvasFrame: CGRect, image: CGImage)],
        at canvasPoint: CGPoint
    ) -> (hex: String, rgb: String) {
        guard let hit = slices.first(where: { $0.canvasFrame.contains(canvasPoint) })
            ?? slices.min(by: {
                hypot($0.canvasFrame.midX - canvasPoint.x, $0.canvasFrame.midY - canvasPoint.y)
                    < hypot($1.canvasFrame.midX - canvasPoint.x, $1.canvasFrame.midY - canvasPoint.y)
            }),
              let (r, g, b) = samplePixelRGB(in: hit.image, point: canvasPoint, screenBounds: hit.canvasFrame) else {
            return ("#000000", "rgb(0, 0, 0)")
        }
        return (String(format: "#%02X%02X%02X", r, g, b), "rgb(\(r), \(g), \(b))")
    }

    static func cropLoupeImage(
        from slices: [(canvasFrame: CGRect, scale: CGFloat, image: CGImage)],
        at canvasPoint: CGPoint,
        pointSize: CGFloat = 28
    ) -> CGImage? {
        let half = pointSize / 2.0
        let sampleRect = CGRect(x: canvasPoint.x - half, y: canvasPoint.y - half, width: pointSize, height: pointSize)
        if let single = slices.first(where: { $0.canvasFrame.contains(sampleRect) }) {
            let sx = CGFloat(single.image.width) / max(single.canvasFrame.width, 1)
            let sy = CGFloat(single.image.height) / max(single.canvasFrame.height, 1)
            let pxRect = CGRect(
                x: max(0, floor((sampleRect.minX - single.canvasFrame.minX) * sx)),
                y: max(0, floor((sampleRect.minY - single.canvasFrame.minY) * sy)),
                width: max(2, round(sampleRect.width * sx)),
                height: max(2, round(sampleRect.height * sy))
            )
            return single.image.cropping(to: pxRect)
        }
        let scale = slices.filter { !$0.canvasFrame.intersection(sampleRect).isNull }.map(\.scale).max() ?? 2.0
        let pxW = max(2, Int(round(pointSize * scale))), pxH = max(2, Int(round(pointSize * scale)))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        ctx.interpolationQuality = .none
        for slice in slices {
            guard let localSrc = MultiDisplayLayout.clampedLocalSourceRect(forSelection: sampleRect, in: slice.canvasFrame) else { continue }
            let sx = CGFloat(slice.image.width) / max(slice.canvasFrame.width, 1)
            let sy = CGFloat(slice.image.height) / max(slice.canvasFrame.height, 1)
            let srcPx = CGRect(x: localSrc.minX * sx, y: localSrc.minY * sy, width: localSrc.width * sx, height: localSrc.height * sy)
            guard let sub = slice.image.cropping(to: srcPx) else { continue }
            let inter = slice.canvasFrame.intersection(sampleRect)
            let rel = inter.offsetBy(dx: -sampleRect.minX, dy: -sampleRect.minY)
            ctx.draw(sub, in: CGRect(
                x: rel.minX * scale, y: (sampleRect.height - rel.maxY) * scale,
                width: rel.width * scale, height: rel.height * scale
            ))
        }
        return ctx.makeImage()
    }

    static func renderMultiDisplaySelection(
        slices: [(canvasFrame: CGRect, scale: CGFloat, image: CGImage)],
        canvasBounds: CGRect,
        selectionRect: CGRect,
        annotations: [ScreenshotAnnotation]
    ) throws -> (image: CGImage, scale: CGFloat) {
        let clamped = selectionRect.intersection(canvasBounds).standardized
        guard !clamped.isNull, clamped.width >= 2, clamped.height >= 2 else {
            throw LumakeyError.visionFailed("截图选区尺寸过小。")
        }
        let intersecting = slices.filter { s in
            let inter = s.canvasFrame.intersection(clamped)
            return !inter.isNull && inter.width >= 1 && inter.height >= 1
        }
        guard !intersecting.isEmpty else {
            throw LumakeyError.visionFailed("选区未落在任何活跃显示器内。")
        }

        if intersecting.count == 1,
           let single = intersecting.first,
           single.canvasFrame.insetBy(dx: -0.5, dy: -0.5).contains(clamped) {
            let safeSingleSel = clamped.intersection(single.canvasFrame)
            let img = try renderCroppedImage(
                baseImage: single.image,
                screenBounds: single.canvasFrame,
                selectionRect: safeSingleSel,
                annotations: annotations
            )
            return (img, single.scale)
        }

        let outScale = intersecting.map(\.scale).max() ?? 2.0
        let outW = max(2, Int(round(clamped.width * outScale)))
        let outH = max(2, Int(round(clamped.height * outScale)))
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: outW * 4,
            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LumakeyError.visionFailed("无法创建跨屏截图合成画布。")
        }
        ctx.interpolationQuality = .high
        for slice in intersecting {
            guard let localSrc = MultiDisplayLayout.clampedLocalSourceRect(forSelection: clamped, in: slice.canvasFrame) else { continue }
            let sx = CGFloat(slice.image.width) / max(slice.canvasFrame.width, 1)
            let sy = CGFloat(slice.image.height) / max(slice.canvasFrame.height, 1)
            let pxRect = CGRect(
                x: floor(localSrc.minX * sx),
                y: floor(localSrc.minY * sy),
                width: max(1, round(localSrc.width * sx)),
                height: max(1, round(localSrc.height * sy))
            )
            guard let sub = slice.image.cropping(to: pxRect) else { continue }
            let inter = slice.canvasFrame.intersection(clamped)
            let rel = inter.offsetBy(dx: -clamped.minX, dy: -clamped.minY)
            ctx.draw(sub, in: CGRect(
                x: rel.minX * outScale,
                y: (clamped.height - rel.maxY) * outScale,
                width: rel.width * outScale,
                height: rel.height * outScale
            ))
        }
        guard let baseCropped = ctx.makeImage() else {
            throw LumakeyError.visionFailed("合成跨显示器选区图像失败。")
        }
        if annotations.isEmpty { return (baseCropped, outScale) }
        let annotated = try overlayAnnotations(
            onto: baseCropped, selectionRect: clamped, scaleX: outScale, scaleY: outScale, annotations: annotations
        )
        return (annotated, outScale)
    }
}
