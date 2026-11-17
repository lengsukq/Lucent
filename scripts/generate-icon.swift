#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

private func makeSquircle(in rect: CGRect, radiusRatio: CGFloat) -> CGPath {
    let r = min(rect.width, rect.height) * radiusRatio
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

private func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

private func drawLinear(
    _ ctx: CGContext,
    colors: [CGColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let grad = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else { return }
    ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

private func drawRadial(
    _ ctx: CGContext,
    colors: [CGColor],
    locations: [CGFloat],
    center: CGPoint,
    endRadius: CGFloat
) {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let grad = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) else { return }
    ctx.drawRadialGradient(
        grad,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: endRadius,
        options: [.drawsAfterEndLocation]
    )
}

private func tiltedRingPoint(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, tilt: CGFloat, angle: CGFloat) -> CGPoint {
    let lx = cos(angle) * rx
    let ly = sin(angle) * ry
    let ct = cos(tilt)
    let st = sin(tilt)
    return CGPoint(x: cx + lx * ct - ly * st, y: cy + lx * st + ly * ct)
}

private func makePerspectiveOrbitRing(
    cx: CGFloat,
    cy: CGFloat,
    rx: CGFloat,
    ry: CGFloat,
    tilt: CGFloat,
    baseHalfWidth: CGFloat,
    steps: Int = 120
) -> CGPath {
    var outerPts: [CGPoint] = []
    var innerPts: [CGPoint] = []
    for i in 0..<steps {
        let ang = (CGFloat(i) / CGFloat(steps)) * (.pi * 2.0)
        // Perspective depth: sin(ang) == 1 is back-top (thinner), sin(ang) == -1 is front-bottom (thicker)
        let depthScale = 0.68 - 0.36 * sin(ang)
        let hw = baseHalfWidth * depthScale
        let lx = cos(ang)
        let ly = sin(ang)
        // Outward normal in local ellipse space
        let nx = lx / max(rx, 1)
        let ny = ly / max(ry, 1)
        let nLen = max(hypot(nx, ny), 0.0001)
        let ux = nx / nLen
        let uy = ny / nLen

        let outLX = lx * rx + ux * hw
        let outLY = ly * ry + uy * hw
        let inLX = lx * rx - ux * hw
        let inLY = ly * ry - uy * hw

        let ct = cos(tilt)
        let st = sin(tilt)
        outerPts.append(CGPoint(x: cx + outLX * ct - outLY * st, y: cy + outLX * st + outLY * ct))
        innerPts.append(CGPoint(x: cx + inLX * ct - inLY * st, y: cy + inLX * st + inLY * ct))
    }

    let path = CGMutablePath()
    if let firstOut = outerPts.first {
        path.move(to: firstOut)
        for pt in outerPts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
    }
    if let firstIn = innerPts.first {
        path.move(to: firstIn)
        for pt in innerPts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
    }
    return path
}

func renderIconPNG(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let isTiny = pixelSize <= 32
    let inset = s * (isTiny ? 0.062 : 0.092)
    let bodyRect = CGRect(x: inset, y: inset + s * 0.012, width: s - inset * 2, height: s - inset * 2)
    let chassisPath = makeSquircle(in: bodyRect, radiusRatio: 0.226)

    // 1. Soft macOS Sequoia studio drop shadow
    if !isTiny {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.026), blur: s * 0.056, color: srgb(2, 5, 18, 0.50))
        ctx.addPath(chassisPath)
        ctx.setFillColor(srgb(7, 10, 28, 1.0))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 2. 3D Deep Obsidian-Sapphire Cushion Chassis
    ctx.saveGState()
    ctx.addPath(chassisPath)
    ctx.clip()

    drawLinear(
        ctx,
        colors: [srgb(20, 33, 78), srgb(8, 13, 34), srgb(21, 12, 50)],
        locations: [0.0, 0.54, 1.0],
        start: CGPoint(x: bodyRect.minX + bodyRect.width * 0.2, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.1, y: bodyRect.minY)
    )

    // Ambient volumetric aurora caustics inside chassis
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    drawRadial(
        ctx,
        colors: [srgb(14, 165, 233, 0.50), srgb(56, 189, 248, 0.15), srgb(14, 165, 233, 0.0)],
        locations: [0.0, 0.48, 1.0],
        center: CGPoint(x: bodyRect.minX + bodyRect.width * 0.18, y: bodyRect.minY + bodyRect.height * 0.20),
        endRadius: bodyRect.width * 0.65
    )
    drawRadial(
        ctx,
        colors: [srgb(168, 85, 247, 0.48), srgb(244, 114, 182, 0.20), srgb(168, 85, 247, 0.0)],
        locations: [0.0, 0.46, 1.0],
        center: CGPoint(x: bodyRect.minX + bodyRect.width * 0.84, y: bodyRect.minY + bodyRect.height * 0.82),
        endRadius: bodyRect.width * 0.62
    )
    ctx.restoreGState()

    // Soft pillowed inner bevel glow around chassis perimeter
    let innerChassis = bodyRect.insetBy(dx: s * 0.011, dy: s * 0.011)
    let innerChassisPath = makeSquircle(in: innerChassis, radiusRatio: 0.222)
    ctx.saveGState()
    ctx.addPath(chassisPath)
    ctx.addPath(innerChassisPath)
    ctx.clip(using: .evenOdd)
    drawLinear(
        ctx,
        colors: [
            srgb(224, 242, 254, 0.46),
            srgb(56, 189, 248, 0.20),
            srgb(129, 140, 248, 0.10),
            srgb(236, 72, 153, 0.34)
        ],
        locations: [0.0, 0.30, 0.68, 1.0],
        start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
    )
    ctx.restoreGState()

    // 3. True 3D Sculpted Tactile Keycap Frustum
    let skirtW = bodyRect.width * 0.68
    let skirtH = bodyRect.height * 0.67
    let skirtRect = CGRect(
        x: bodyRect.midX - skirtW * 0.5,
        y: bodyRect.midY - skirtH * 0.5 - bodyRect.height * 0.016,
        width: skirtW,
        height: skirtH
    )
    let skirtPath = makeSquircle(in: skirtRect, radiusRatio: 0.265)

    let sideBevel = skirtW * 0.068
    let topBevel = skirtH * 0.036
    let bottomWall = skirtH * 0.142
    let topRect = CGRect(
        x: skirtRect.minX + sideBevel,
        y: skirtRect.minY + bottomWall,
        width: skirtW - sideBevel * 2,
        height: skirtH - topBevel - bottomWall
    )
    let topPath = makeSquircle(in: topRect, radiusRatio: 0.245)

    // Deep ambient occlusion + colored under-keycap bounce shadow onto chassis
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.038), blur: s * 0.060, color: srgb(1, 3, 12, 0.90))
    ctx.addPath(skirtPath)
    ctx.setFillColor(srgb(12, 18, 46, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    if !isTiny {
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.022), blur: s * 0.048, color: srgb(56, 189, 248, 0.40))
        ctx.addPath(skirtPath)
        ctx.setFillColor(srgb(56, 189, 248, 0.06))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 3D Extruded Anodized Crystal Keycap Side Skirt (smooth cylindrical lighting)
    ctx.saveGState()
    ctx.addPath(skirtPath)
    ctx.clip()

    drawLinear(
        ctx,
        colors: [
            srgb(125, 211, 252),
            srgb(45, 108, 228),
            srgb(28, 36, 94),
            srgb(96, 40, 186),
            srgb(236, 72, 153)
        ],
        locations: [0.0, 0.20, 0.50, 0.80, 1.0],
        start: CGPoint(x: skirtRect.minX, y: skirtRect.midY),
        end: CGPoint(x: skirtRect.maxX, y: skirtRect.midY)
    )

    drawLinear(
        ctx,
        colors: [
            srgb(255, 255, 255, 0.26),
            srgb(14, 20, 54, 0.28),
            srgb(10, 14, 40, 0.52),
            srgb(129, 140, 248, 0.28)
        ],
        locations: [0.0, 0.45, 0.84, 1.0],
        start: CGPoint(x: skirtRect.midX, y: skirtRect.maxY),
        end: CGPoint(x: skirtRect.midX, y: skirtRect.minY)
    )
    ctx.restoreGState()

    // Fine specular lip along skirt outer edge
    ctx.saveGState()
    ctx.addPath(skirtPath)
    ctx.setLineWidth(max(0.8, s * 0.006))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    drawLinear(
        ctx,
        colors: [srgb(224, 242, 254, 0.68), srgb(99, 102, 241, 0.28), srgb(244, 114, 182, 0.54)],
        locations: [0.0, 0.52, 1.0],
        start: CGPoint(x: skirtRect.minX, y: skirtRect.maxY),
        end: CGPoint(x: skirtRect.maxX, y: skirtRect.minY)
    )
    ctx.restoreGState()

    // Subtle elevation shadow of topDish onto the 3D skirt bevel
    ctx.saveGState()
    ctx.addPath(skirtPath)
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.010), blur: s * 0.016, color: srgb(3, 6, 22, 0.55))
    ctx.addPath(topPath)
    ctx.setFillColor(srgb(20, 30, 76, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 4. 3D Concave Frosted Sapphire Key-Top Dish
    ctx.saveGState()
    ctx.addPath(topPath)
    ctx.clip()

    drawLinear(
        ctx,
        colors: [srgb(40, 66, 146), srgb(16, 25, 66), srgb(40, 24, 96)],
        locations: [0.0, 0.52, 1.0],
        start: CGPoint(x: topRect.minX, y: topRect.maxY),
        end: CGPoint(x: topRect.maxX, y: topRect.minY)
    )

    drawRadial(
        ctx,
        colors: [srgb(5, 8, 24, 0.62), srgb(17, 28, 74, 0.18), srgb(125, 211, 252, 0.30)],
        locations: [0.0, 0.64, 1.0],
        center: CGPoint(x: topRect.midX, y: topRect.midY + topRect.height * 0.04),
        endRadius: topRect.width * 0.58
    )

    ctx.saveGState()
    ctx.setBlendMode(.screen)
    drawRadial(
        ctx,
        colors: [srgb(56, 189, 248, 0.38), srgb(168, 85, 247, 0.20), srgb(56, 189, 248, 0.0)],
        locations: [0.0, 0.52, 1.0],
        center: CGPoint(x: topRect.midX, y: topRect.midY),
        endRadius: topRect.width * 0.52
    )
    ctx.restoreGState()

    let dishGloss = CGRect(
        x: topRect.minX - topRect.width * 0.12,
        y: topRect.midY + topRect.height * 0.08,
        width: topRect.width * 1.24,
        height: topRect.height * 0.60
    )
    ctx.saveGState()
    ctx.addEllipse(in: dishGloss)
    ctx.clip()
    drawLinear(
        ctx,
        colors: [srgb(255, 255, 255, 0.28), srgb(255, 255, 255, 0.0)],
        locations: [0.0, 1.0],
        start: CGPoint(x: topRect.midX, y: topRect.maxY),
        end: CGPoint(x: topRect.midX, y: topRect.midY + topRect.height * 0.08)
    )
    ctx.restoreGState()
    ctx.restoreGState() // End topDish clip

    // Pillowed 3D chamfer highlight around topDish
    ctx.saveGState()
    ctx.addPath(topPath)
    ctx.setLineWidth(max(1.0, s * 0.0085))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    drawLinear(
        ctx,
        colors: [
            srgb(255, 255, 255, 0.92),
            srgb(125, 211, 252, 0.65),
            srgb(129, 140, 248, 0.30),
            srgb(244, 114, 182, 0.62)
        ],
        locations: [0.0, 0.35, 0.72, 1.0],
        start: CGPoint(x: topRect.minX, y: topRect.maxY),
        end: CGPoint(x: topRect.maxX, y: topRect.minY)
    )
    ctx.restoreGState()

    // 5. Seamless 360° Perspective 3D Orbit Ring (Back Pass -> 3D Crystal Gem -> Front Occluding Pass)
    let gemCenter = CGPoint(x: topRect.midX, y: topRect.midY + topRect.height * 0.01)
    let ringRX = topRect.width * 0.485
    let ringRY = topRect.height * 0.205
    let ringTilt: CGFloat = 0.55
    let fullOrbitRing = makePerspectiveOrbitRing(
        cx: gemCenter.x,
        cy: gemCenter.y,
        rx: ringRX,
        ry: ringRY,
        tilt: ringTilt,
        baseHalfWidth: s * (isTiny ? 0.028 : 0.023)
    )

    let drawRingArtwork: (_ glowAlpha: CGFloat) -> Void = { glowAlpha in
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.setShadow(offset: .zero, blur: s * 0.030, color: srgb(56, 189, 248, glowAlpha))
        ctx.addPath(fullOrbitRing)
        ctx.setFillColor(srgb(56, 189, 248, 0.42))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(fullOrbitRing)
        ctx.clip(using: .evenOdd)
        drawLinear(
            ctx,
            colors: [
                srgb(34, 211, 238, 0.96),
                srgb(240, 249, 255, 1.0),
                srgb(167, 139, 250, 0.96),
                srgb(244, 114, 182, 0.95)
            ],
            locations: [0.0, 0.40, 0.74, 1.0],
            start: CGPoint(x: gemCenter.x - ringRX, y: gemCenter.y - ringRY * 0.6),
            end: CGPoint(x: gemCenter.x + ringRX, y: gemCenter.y + ringRY * 0.9)
        )
        ctx.restoreGState()
    }

    // Major-axis half-plane vector for clean back/front split right through the center of the gem
    let axisDir = CGPoint(x: cos(ringTilt), y: sin(ringTilt))
    let normalFront = CGPoint(x: sin(ringTilt), y: -cos(ringTilt)) // points toward front-bottom-right
    let extent = s * 1.5

    // 5A. Back half-plane of seamless 3D ring (behind gem)
    ctx.saveGState()
    let backPlane = CGMutablePath()
    backPlane.move(to: CGPoint(x: gemCenter.x - axisDir.x * extent, y: gemCenter.y - axisDir.y * extent))
    backPlane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * extent, y: gemCenter.y + axisDir.y * extent))
    backPlane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * extent - normalFront.x * extent, y: gemCenter.y + axisDir.y * extent - normalFront.y * extent))
    backPlane.addLine(to: CGPoint(x: gemCenter.x - axisDir.x * extent - normalFront.x * extent, y: gemCenter.y - axisDir.y * extent - normalFront.y * extent))
    backPlane.closeSubpath()
    ctx.addPath(backPlane)
    ctx.clip()
    drawRingArtwork(0.65)
    ctx.restoreGState()

    // 6. Centerpiece: 3D Sculpted Cushion-Faceted Octahedral Prism Gem
    let gemR = topRect.width * (isTiny ? 0.42 : 0.375)
    let waist = gemR * 0.31
    let d = waist * 0.70710678
    let cx = gemCenter.x
    let cy = gemCenter.y

    let pN = CGPoint(x: cx, y: cy + gemR * 1.06)
    let pS = CGPoint(x: cx, y: cy - gemR * 1.02)
    let pE = CGPoint(x: cx + gemR, y: cy)
    let pW = CGPoint(x: cx - gemR, y: cy)
    let pNE = CGPoint(x: cx + d, y: cy + d)
    let pSE = CGPoint(x: cx + d, y: cy - d)
    let pSW = CGPoint(x: cx - d, y: cy - d)
    let pNW = CGPoint(x: cx - d, y: cy + d)

    let gemPath = CGMutablePath()
    gemPath.move(to: pN)
    gemPath.addQuadCurve(to: pE, control: pNE)
    gemPath.addQuadCurve(to: pS, control: pSE)
    gemPath.addQuadCurve(to: pW, control: pSW)
    gemPath.addQuadCurve(to: pN, control: pNW)
    gemPath.closeSubpath()

    // Gem 3D levitation drop shadow onto keycap dish
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.024), blur: s * 0.032, color: srgb(2, 5, 20, 0.82))
    ctx.addPath(gemPath)
    ctx.setFillColor(srgb(255, 255, 255, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(gemPath)
    ctx.clip()

    drawLinear(
        ctx,
        colors: [srgb(255, 255, 255), srgb(186, 230, 253), srgb(165, 180, 252), srgb(216, 180, 254)],
        locations: [0.0, 0.36, 0.70, 1.0],
        start: CGPoint(x: cx - gemR * 0.6, y: cy + gemR * 0.8),
        end: CGPoint(x: cx + gemR * 0.7, y: cy - gemR * 0.8)
    )

    let quadConfigs: [([CGPoint], CGColor, CGColor)] = [
        ([gemCenter, pN, CGPoint(x: cx - gemR, y: cy + gemR), pW], srgb(255, 255, 255, 0.98), srgb(224, 242, 254, 0.88)),
        ([gemCenter, pN, CGPoint(x: cx + gemR, y: cy + gemR), pE], srgb(240, 249, 255, 0.94), srgb(56, 189, 248, 0.86)),
        ([gemCenter, pE, CGPoint(x: cx + gemR, y: cy - gemR), pS], srgb(192, 132, 252, 0.90), srgb(236, 72, 153, 0.82)),
        ([gemCenter, pW, CGPoint(x: cx - gemR, y: cy - gemR), pS], srgb(125, 211, 252, 0.88), srgb(79, 70, 229, 0.90))
    ]
    for (poly, cStart, cEnd) in quadConfigs {
        ctx.saveGState()
        ctx.beginPath()
        ctx.move(to: poly[0])
        for pt in poly.dropFirst() { ctx.addLine(to: pt) }
        ctx.closePath()
        ctx.clip()
        drawLinear(ctx, colors: [cStart, cEnd], locations: [0.0, 1.0], start: gemCenter, end: poly[2])
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.setBlendMode(.screen)
    drawRadial(
        ctx,
        colors: [srgb(255, 255, 255, 1.0), srgb(224, 242, 254, 0.55), srgb(255, 255, 255, 0.0)],
        locations: [0.0, 0.34, 1.0],
        center: CGPoint(x: cx - gemR * 0.04, y: cy + gemR * 0.05),
        endRadius: gemR * 0.52
    )
    ctx.restoreGState()

    if !isTiny {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineWidth(max(1.0, s * 0.0065))
        ctx.setStrokeColor(srgb(255, 255, 255, 0.92))
        ctx.beginPath()
        ctx.move(to: pN); ctx.addLine(to: pS)
        ctx.move(to: pW); ctx.addLine(to: pE)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.restoreGState() // End gem clip

    if !isTiny {
        ctx.saveGState()
        ctx.addPath(gemPath)
        ctx.setLineWidth(max(0.8, s * 0.005))
        ctx.setStrokeColor(srgb(255, 255, 255, 0.84))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // 5B. Front half-plane of seamless 3D ring (sweeping cleanly IN FRONT of the gem, zero seam at turnarounds!)
    ctx.saveGState()
    let frontPlane = CGMutablePath()
    frontPlane.move(to: CGPoint(x: gemCenter.x - axisDir.x * extent, y: gemCenter.y - axisDir.y * extent))
    frontPlane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * extent, y: gemCenter.y + axisDir.y * extent))
    frontPlane.addLine(to: CGPoint(x: gemCenter.x + axisDir.x * extent + normalFront.x * extent, y: gemCenter.y + axisDir.y * extent + normalFront.y * extent))
    frontPlane.addLine(to: CGPoint(x: gemCenter.x - axisDir.x * extent + normalFront.x * extent, y: gemCenter.y - axisDir.y * extent + normalFront.y * extent))
    frontPlane.closeSubpath()
    ctx.addPath(frontPlane)
    ctx.clip()
    drawRingArtwork(0.92)
    ctx.restoreGState()

    // Luminous prism photon pearl gliding along upper-right orbit crest
    if !isTiny {
        let pearlPt = tiltedRingPoint(
            cx: gemCenter.x, cy: gemCenter.y,
            rx: ringRX, ry: ringRY,
            tilt: ringTilt, angle: .pi * 0.14
        )
        let pr = s * 0.017
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        drawRadial(
            ctx,
            colors: [srgb(255, 255, 255, 1.0), srgb(244, 114, 182, 0.85), srgb(244, 114, 182, 0.0)],
            locations: [0.0, 0.40, 1.0],
            center: pearlPt,
            endRadius: pr * 2.5
        )
        ctx.restoreGState()
    }

    ctx.restoreGState() // End chassis clip

    // 7. Fine Outer Studio Specular Hairline on Chassis
    ctx.saveGState()
    ctx.addPath(chassisPath)
    ctx.setLineWidth(max(0.9, s * 0.007))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    drawLinear(
        ctx,
        colors: [
            srgb(255, 255, 255, 0.82),
            srgb(125, 211, 252, 0.45),
            srgb(99, 102, 241, 0.22),
            srgb(244, 114, 182, 0.52)
        ],
        locations: [0.0, 0.32, 0.68, 1.0],
        start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY)
    )
    ctx.restoreGState()

    let cgImage = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

let slots: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for slot in slots {
    try renderIconPNG(pixelSize: slot.px).write(to: outputDir.appendingPathComponent(slot.name))
}
