import CoreGraphics

public enum BrandIconRenderer {
    public static func renderCGImage(pixelSize: Int, includeOuterMargin: Bool) -> CGImage? {
        let s = CGFloat(pixelSize)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelSize, height: pixelSize,
            bitsPerComponent: 8, bytesPerRow: pixelSize * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let isTiny = pixelSize <= 40
        let inset = includeOuterMargin ? s * (isTiny ? 0.062 : 0.092) : s * 0.018
        let yShift = includeOuterMargin ? s * 0.012 : 0
        let bodyRect = CGRect(x: inset, y: inset + yShift, width: s - inset * 2, height: s - inset * 2)
        let chassisPath = makeSquircle(in: bodyRect, radiusRatio: 0.228)

        if includeOuterMargin && !isTiny {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.026), blur: s * 0.056, color: srgb(2, 5, 18, 0.50))
            ctx.addPath(chassisPath)
            ctx.setFillColor(srgb(7, 10, 28))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(chassisPath)
        ctx.clip()
        drawChassisInterior(ctx, bodyRect: bodyRect)
        let topRect = drawKeycapFrustumAndDish(ctx, bodyRect: bodyRect)
        drawOrbitAndCrystalGem(ctx, topRect: topRect, bodyWidth: bodyRect.width, isTiny: isTiny)
        ctx.restoreGState()

        strokeGradient(
            ctx, path: chassisPath, width: max(0.9, bodyRect.width * 0.009),
            colors: [srgb(255, 255, 255, 0.82), srgb(125, 211, 252, 0.45), srgb(99, 102, 241, 0.22), srgb(244, 114, 182, 0.52)],
            locations: [0.0, 0.32, 0.68, 1.0],
            start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
            end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
        )
        return ctx.makeImage()
    }

    private static func drawChassisInterior(_ ctx: CGContext, bodyRect: CGRect) {
        drawLinear(
            ctx, colors: [srgb(20, 33, 78), srgb(8, 13, 34), srgb(21, 12, 50)],
            locations: [0.0, 0.54, 1.0],
            start: CGPoint(x: bodyRect.minX + bodyRect.width * 0.2, y: bodyRect.maxY),
            end: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.1, y: bodyRect.minY)
        )
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        drawRadial(
            ctx, colors: [srgb(14, 165, 233, 0.50), srgb(56, 189, 248, 0.15), srgb(14, 165, 233, 0.0)],
            locations: [0.0, 0.48, 1.0],
            center: CGPoint(x: bodyRect.minX + bodyRect.width * 0.18, y: bodyRect.minY + bodyRect.height * 0.20),
            endRadius: bodyRect.width * 0.65
        )
        drawRadial(
            ctx, colors: [srgb(168, 85, 247, 0.48), srgb(244, 114, 182, 0.20), srgb(168, 85, 247, 0.0)],
            locations: [0.0, 0.46, 1.0],
            center: CGPoint(x: bodyRect.minX + bodyRect.width * 0.84, y: bodyRect.minY + bodyRect.height * 0.82),
            endRadius: bodyRect.width * 0.62
        )
        ctx.restoreGState()
    }

    private static func drawKeycapFrustumAndDish(_ ctx: CGContext, bodyRect: CGRect) -> CGRect {
        let skirtW = bodyRect.width * 0.68, skirtH = bodyRect.height * 0.67
        let skirtRect = CGRect(
            x: bodyRect.midX - skirtW * 0.5, y: bodyRect.midY - skirtH * 0.5 - bodyRect.height * 0.016,
            width: skirtW, height: skirtH
        )
        let skirtPath = makeSquircle(in: skirtRect, radiusRatio: 0.265)
        let sideBevel = skirtW * 0.068, topBevel = skirtH * 0.036, bottomWall = skirtH * 0.142
        let topRect = CGRect(
            x: skirtRect.minX + sideBevel, y: skirtRect.minY + bottomWall,
            width: skirtW - sideBevel * 2, height: skirtH - topBevel - bottomWall
        )
        let topPath = makeSquircle(in: topRect, radiusRatio: 0.245)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -bodyRect.height * 0.044), blur: bodyRect.width * 0.068, color: srgb(1, 3, 12, 0.90))
        ctx.addPath(skirtPath)
        ctx.setFillColor(srgb(12, 18, 46))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(skirtPath)
        ctx.clip()
        drawLinear(
            ctx, colors: [srgb(125, 211, 252), srgb(45, 108, 228), srgb(28, 36, 94), srgb(96, 40, 186), srgb(236, 72, 153)],
            locations: [0.0, 0.20, 0.50, 0.80, 1.0],
            start: CGPoint(x: skirtRect.minX, y: skirtRect.midY), end: CGPoint(x: skirtRect.maxX, y: skirtRect.midY)
        )
        drawLinear(
            ctx, colors: [srgb(255, 255, 255, 0.26), srgb(14, 20, 54, 0.28), srgb(10, 14, 40, 0.52), srgb(129, 140, 248, 0.28)],
            locations: [0.0, 0.45, 0.84, 1.0],
            start: CGPoint(x: skirtRect.midX, y: skirtRect.maxY), end: CGPoint(x: skirtRect.midX, y: skirtRect.minY)
        )
        ctx.setShadow(offset: CGSize(width: 0, height: -bodyRect.height * 0.012), blur: bodyRect.width * 0.018, color: srgb(3, 6, 22, 0.55))
        ctx.addPath(topPath)
        ctx.setFillColor(srgb(20, 30, 76))
        ctx.fillPath()
        ctx.restoreGState()

        strokeGradient(
            ctx, path: skirtPath, width: max(0.8, bodyRect.width * 0.007),
            colors: [srgb(224, 242, 254, 0.68), srgb(99, 102, 241, 0.28), srgb(244, 114, 182, 0.54)],
            locations: [0.0, 0.52, 1.0],
            start: CGPoint(x: skirtRect.minX, y: skirtRect.maxY), end: CGPoint(x: skirtRect.maxX, y: skirtRect.minY)
        )

        ctx.saveGState()
        ctx.addPath(topPath)
        ctx.clip()
        drawLinear(
            ctx, colors: [srgb(40, 66, 146), srgb(16, 25, 66), srgb(40, 24, 96)], locations: [0.0, 0.52, 1.0],
            start: CGPoint(x: topRect.minX, y: topRect.maxY), end: CGPoint(x: topRect.maxX, y: topRect.minY)
        )
        drawRadial(
            ctx, colors: [srgb(5, 8, 24, 0.62), srgb(17, 28, 74, 0.18), srgb(125, 211, 252, 0.30)],
            locations: [0.0, 0.64, 1.0],
            center: CGPoint(x: topRect.midX, y: topRect.midY + topRect.height * 0.04), endRadius: topRect.width * 0.58
        )
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        drawRadial(
            ctx, colors: [srgb(56, 189, 248, 0.38), srgb(168, 85, 247, 0.20), srgb(56, 189, 248, 0.0)],
            locations: [0.0, 0.52, 1.0], center: CGPoint(x: topRect.midX, y: topRect.midY), endRadius: topRect.width * 0.52
        )
        ctx.restoreGState()
        ctx.restoreGState()

        strokeGradient(
            ctx, path: topPath, width: max(1.0, bodyRect.width * 0.010),
            colors: [srgb(255, 255, 255, 0.92), srgb(125, 211, 252, 0.65), srgb(129, 140, 248, 0.30), srgb(244, 114, 182, 0.62)],
            locations: [0.0, 0.35, 0.72, 1.0],
            start: CGPoint(x: topRect.minX, y: topRect.maxY), end: CGPoint(x: topRect.maxX, y: topRect.minY)
        )
        return topRect
    }

    private static func drawOrbitAndCrystalGem(_ ctx: CGContext, topRect: CGRect, bodyWidth: CGFloat, isTiny: Bool) {
        let gemCenter = CGPoint(x: topRect.midX, y: topRect.midY + topRect.height * 0.01)
        let ringRX = topRect.width * 0.485, ringRY = topRect.height * 0.205, ringTilt: CGFloat = 0.55
        let orbitRing = makePerspectiveOrbitRing(
            cx: gemCenter.x, cy: gemCenter.y, rx: ringRX, ry: ringRY,
            tilt: ringTilt, baseHalfWidth: bodyWidth * (isTiny ? 0.033 : 0.027)
        )
        let axisDir = CGPoint(x: cos(ringTilt), y: sin(ringTilt))
        let normalFront = CGPoint(x: sin(ringTilt), y: -cos(ringTilt))
        let ext = bodyWidth * 1.6

        let renderRingHalf: (CGFloat, CGFloat) -> Void = { sign, glowAlpha in
            ctx.saveGState()
            let plane = CGMutablePath()
            plane.move(to: CGPoint(x: gemCenter.x - axisDir.x * ext, y: gemCenter.y - axisDir.y * ext))
            plane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * ext, y: gemCenter.y + axisDir.y * ext))
            plane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * ext + normalFront.x * ext * sign, y: gemCenter.y + axisDir.y * ext + normalFront.y * ext * sign))
            plane.addLine(to: CGPoint(x: gemCenter.x - axisDir.x * ext + normalFront.x * ext * sign, y: gemCenter.y - axisDir.y * ext + normalFront.y * ext * sign))
            plane.closeSubpath()
            ctx.addPath(plane); ctx.clip()

            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.setShadow(offset: .zero, blur: bodyWidth * 0.034, color: srgb(56, 189, 248, glowAlpha))
            ctx.addPath(orbitRing); ctx.setFillColor(srgb(56, 189, 248, 0.42)); ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            ctx.addPath(orbitRing); ctx.clip(using: .evenOdd)
            drawLinear(
                ctx, colors: [srgb(34, 211, 238, 0.96), srgb(240, 249, 255, 1.0), srgb(167, 139, 250, 0.96), srgb(244, 114, 182, 0.95)],
                locations: [0.0, 0.40, 0.74, 1.0],
                start: CGPoint(x: gemCenter.x - ringRX, y: gemCenter.y - ringRY * 0.6),
                end: CGPoint(x: gemCenter.x + ringRX, y: gemCenter.y + ringRY * 0.9)
            )
            ctx.restoreGState()
        }

        renderRingHalf(-1.0, 0.62)
        drawCrystalGemBody(ctx, gemCenter: gemCenter, gemR: topRect.width * (isTiny ? 0.43 : 0.375), bodyWidth: bodyWidth, isTiny: isTiny)
        renderRingHalf(1.0, 0.92)

        if !isTiny {
            let ct = cos(ringTilt), st = sin(ringTilt), ang = CGFloat.pi * 0.14
            let lx = cos(ang) * ringRX, ly = sin(ang) * ringRY
            let pearl = CGPoint(x: gemCenter.x + lx * ct - ly * st, y: gemCenter.y + lx * st + ly * ct)
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            drawRadial(
                ctx, colors: [srgb(255, 255, 255), srgb(244, 114, 182, 0.85), srgb(244, 114, 182, 0.0)],
                locations: [0.0, 0.40, 1.0], center: pearl, endRadius: bodyWidth * 0.048
            )
            ctx.restoreGState()
        }
    }

    private static func drawCrystalGemBody(_ ctx: CGContext, gemCenter: CGPoint, gemR: CGFloat, bodyWidth: CGFloat, isTiny: Bool) {
        let d = gemR * 0.31 * 0.70710678, cx = gemCenter.x, cy = gemCenter.y
        let pN = CGPoint(x: cx, y: cy + gemR * 1.06), pS = CGPoint(x: cx, y: cy - gemR * 1.02)
        let pE = CGPoint(x: cx + gemR, y: cy), pW = CGPoint(x: cx - gemR, y: cy)
        let gemPath = CGMutablePath()
        gemPath.move(to: pN)
        gemPath.addQuadCurve(to: pE, control: CGPoint(x: cx + d, y: cy + d))
        gemPath.addQuadCurve(to: pS, control: CGPoint(x: cx + d, y: cy - d))
        gemPath.addQuadCurve(to: pW, control: CGPoint(x: cx - d, y: cy - d))
        gemPath.addQuadCurve(to: pN, control: CGPoint(x: cx - d, y: cy + d))
        gemPath.closeSubpath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -bodyWidth * 0.028), blur: bodyWidth * 0.036, color: srgb(2, 5, 20, 0.82))
        ctx.addPath(gemPath); ctx.setFillColor(srgb(255, 255, 255)); ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(gemPath); ctx.clip()
        let quads: [([CGPoint], CGColor, CGColor)] = [
            ([gemCenter, pN, CGPoint(x: cx - gemR, y: cy + gemR), pW], srgb(255, 255, 255), srgb(224, 242, 254)),
            ([gemCenter, pN, CGPoint(x: cx + gemR, y: cy + gemR), pE], srgb(240, 249, 255), srgb(56, 189, 248)),
            ([gemCenter, pE, CGPoint(x: cx + gemR, y: cy - gemR), pS], srgb(192, 132, 252), srgb(236, 72, 153)),
            ([gemCenter, pW, CGPoint(x: cx - gemR, y: cy - gemR), pS], srgb(125, 211, 252), srgb(79, 70, 229))
        ]
        for (poly, c0, c1) in quads {
            ctx.saveGState()
            ctx.beginPath(); ctx.move(to: poly[0]); poly.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.closePath(); ctx.clip()
            drawLinear(ctx, colors: [c0, c1], locations: [0.0, 1.0], start: gemCenter, end: poly[2])
            ctx.restoreGState()
        }
        if !isTiny {
            ctx.setLineCap(.round); ctx.setLineWidth(max(1.0, bodyWidth * 0.007)); ctx.setStrokeColor(srgb(255, 255, 255, 0.92))
            ctx.beginPath(); ctx.move(to: pN); ctx.addLine(to: pS); ctx.move(to: pW); ctx.addLine(to: pE); ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func makePerspectiveOrbitRing(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, tilt: CGFloat, baseHalfWidth: CGFloat) -> CGPath {
        let steps = 96, ct = cos(tilt), st = sin(tilt)
        var outPts: [CGPoint] = [], inPts: [CGPoint] = []
        for i in 0..<steps {
            let ang = (CGFloat(i) / CGFloat(steps)) * (.pi * 2.0)
            let hw = baseHalfWidth * (0.68 - 0.36 * sin(ang))
            let lx = cos(ang), ly = sin(ang), nx = lx / max(rx, 1), ny = ly / max(ry, 1), len = max(hypot(nx, ny), 0.0001)
            let ux = nx / len, uy = ny / len
            let oX = lx * rx + ux * hw, oY = ly * ry + uy * hw, iX = lx * rx - ux * hw, iY = ly * ry - uy * hw
            outPts.append(CGPoint(x: cx + oX * ct - oY * st, y: cy + oX * st + oY * ct))
            inPts.append(CGPoint(x: cx + iX * ct - iY * st, y: cy + iX * st + iY * ct))
        }
        let path = CGMutablePath()
        if let f = outPts.first { path.move(to: f); outPts.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath() }
        if let f = inPts.first { path.move(to: f); inPts.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath() }
        return path
    }

    private static func makeSquircle(in rect: CGRect, radiusRatio: CGFloat) -> CGPath {
        let r = min(rect.width, rect.height) * radiusRatio
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }

    private static func strokeGradient(_ ctx: CGContext, path: CGPath, width: CGFloat, colors: [CGColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
        ctx.saveGState(); ctx.addPath(path); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
        drawLinear(ctx, colors: colors, locations: locations, start: start, end: end); ctx.restoreGState()
    }

    private static func drawLinear(_ ctx: CGContext, colors: [CGColor], locations: [CGFloat], start: CGPoint, end: CGPoint) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else { return }
        ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func drawRadial(_ ctx: CGContext, colors: [CGColor], locations: [CGFloat], center: CGPoint, endRadius: CGFloat) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: endRadius, options: [.drawsAfterEndLocation])
    }
}
