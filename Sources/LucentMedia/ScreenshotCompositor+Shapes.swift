import AppKit
import CoreGraphics
import Foundation

extension ScreenshotCompositor {
    static func drawSpotlights(_ items: [ScreenshotAnnotation], selectionRect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let path = CGMutablePath()
        path.addRect(selectionRect)
        for item in items {
            guard let hole = AnnotationGeometry.boxRect(for: item), hole.width >= 2, hole.height >= 2 else { continue }
            let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: hole)
            path.addRoundedRect(in: hole, cornerWidth: cr, cornerHeight: cr)
        }
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.54))
        ctx.drawPath(using: .eoFill)
    }

    static func drawAnnotationShape(
        _ item: ScreenshotAnnotation,
        into ctx: CGContext,
        baseCropped: CGImage,
        origin: CGPoint,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let color = item.color.cgColor
        let lw = item.effectiveLineWidth
        let dash = item.lineStyle.dashPattern(for: lw)

        switch item.tool {
        case .move, .spotlight:
            break
        case .rect:
            guard let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 1, rect.height >= 1 else { break }
            let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: rect)
            let path = CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil)
            if item.isFilled {
                fillPath(path, item: item, alpha: 0.22, in: ctx)
            }
            strokePath(path, item: item, lineWidth: lw, dash: dash, lineCap: .round, lineJoin: .round, in: ctx)
        case .ellipse:
            guard let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 1, rect.height >= 1 else { break }
            let path = CGPath(ellipseIn: rect, transform: nil)
            if item.isFilled {
                fillPath(path, item: item, alpha: 0.22, in: ctx)
            }
            strokePath(path, item: item, lineWidth: lw, dash: dash, lineCap: .round, lineJoin: .round, in: ctx)
        case .line:
            guard item.points.count >= 2 else { break }
            let p = CGMutablePath()
            p.move(to: item.points[0]); p.addLine(to: item.points[item.points.count - 1])
            strokePath(p, item: item, lineWidth: lw, dash: dash, lineCap: .round, lineJoin: .round, in: ctx)
        case .arrow:
            drawArrow(item, lineWidth: lw, dash: dash, in: ctx)
        case .pen:
            guard !item.points.isEmpty else { break }
            let p = AnnotationGeometry.smoothedFreehandPath(for: item.points)
            strokePath(p, item: item, lineWidth: lw, dash: dash, lineCap: .round, lineJoin: .round, in: ctx)
        case .highlighter:
            guard !item.points.isEmpty else { break }
            let p = AnnotationGeometry.smoothedFreehandPath(for: item.points)
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(color.copy(alpha: 0.48) ?? color)
            ctx.setLineWidth(lw * 3.0)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(p); ctx.strokePath()
        case .mosaic:
            drawMosaic(
                points: item.points, brushRadius: item.effectiveMosaicRadius,
                baseCropped: baseCropped, origin: origin, scaleX: scaleX, scaleY: scaleY, in: ctx
            )
        case .blur:
            drawBlurRegion(item, baseCropped: baseCropped, origin: origin, scaleX: scaleX, scaleY: scaleY, in: ctx)
        case .counter:
            drawCounter(item, in: ctx)
        case .text:
            guard let pt = item.points.first, !item.text.isEmpty else { break }
            drawText(
                item.text, at: pt, fontSize: item.effectiveFontSize,
                color: NSColor(cgColor: color) ?? .systemRed, centeredWidth: nil, in: ctx
            )
        }
    }

    private static func strokePath(
        _ path: CGPath,
        item: ScreenshotAnnotation,
        lineWidth: CGFloat,
        dash: [CGFloat],
        lineCap: CGLineCap,
        lineJoin: CGLineJoin,
        in ctx: CGContext
    ) {
        if let grad = item.gradient {
            ctx.saveGState()
            defer { ctx.restoreGState() }
            let stroked = path.copy(
                strokingWithWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, miterLimit: 4,
                transform: .identity
            )
            if dash.isEmpty {
                ctx.addPath(stroked)
                ctx.clip()
                drawLinearGradient(grad, over: stroked.boundingBoxOfPath, alpha: 1.0, in: ctx)
                return
            }
        }
        ctx.setStrokeColor(item.gradient?.start.cgColor ?? item.color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(lineCap); ctx.setLineJoin(lineJoin)
        if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.addPath(path); ctx.strokePath()
    }

    private static func fillPath(_ path: CGPath, item: ScreenshotAnnotation, alpha: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if let grad = item.gradient {
            ctx.addPath(path); ctx.clip()
            drawLinearGradient(grad, over: path.boundingBoxOfPath, alpha: alpha, in: ctx)
        } else {
            ctx.setFillColor(item.color.cgColor.copy(alpha: alpha) ?? item.color.cgColor)
            ctx.addPath(path); ctx.fillPath()
        }
    }

    private static func drawLinearGradient(_ grad: AnnotationGradientPreset, over bounds: CGRect, alpha: CGFloat, in ctx: CGContext) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let c0 = grad.start.cgColor.copy(alpha: alpha) ?? grad.start.cgColor
        let c1 = grad.mid.cgColor.copy(alpha: alpha) ?? grad.mid.cgColor
        let c2 = grad.end.cgColor.copy(alpha: alpha) ?? grad.end.cgColor
        guard let cgGrad = CGGradient(colorsSpace: srgb, colors: [c0, c1, c2] as CFArray, locations: [0, 0.5, 1]) else { return }
        ctx.drawLinearGradient(
            cgGrad,
            start: CGPoint(x: bounds.minX, y: bounds.minY),
            end: CGPoint(x: bounds.maxX, y: bounds.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func drawArrow(_ item: ScreenshotAnnotation, lineWidth: CGFloat, dash: [CGFloat], in ctx: CGContext) {
        guard let g = AnnotationGeometry.resolveArrow(item) else { return }
        let shaft = CGMutablePath()
        shaft.move(to: g.p0)
        if g.isCurved {
            shaft.addCurve(to: g.shaftEnd, control1: g.c1, control2: g.c2)
        } else {
            shaft.addLine(to: g.shaftEnd)
        }
        strokePath(shaft, item: item, lineWidth: lineWidth, dash: dash, lineCap: .round, lineJoin: .round, in: ctx)
        let head = CGMutablePath()
        head.move(to: g.tip); head.addLine(to: g.leftWing); head.addLine(to: g.rightWing); head.closeSubpath()
        if let grad = item.gradient {
            ctx.saveGState(); ctx.addPath(head); ctx.clip()
            drawLinearGradient(grad, over: head.boundingBoxOfPath, alpha: 1.0, in: ctx)
            ctx.restoreGState()
        } else {
            ctx.setFillColor(item.color.cgColor); ctx.addPath(head); ctx.fillPath()
        }
    }

    private static func drawCounter(_ item: ScreenshotAnnotation, in ctx: CGContext) {
        guard let center = item.points.first else { return }
        let r = item.effectiveCounterRadius
        if item.points.count >= 2 {
            let tip = item.points[1]
            let dx = tip.x - center.x, dy = tip.y - center.y, dist = hypot(dx, dy)
            if dist > r + 4 {
                let startOnRim = CGPoint(x: center.x + dx / dist * (r - 1), y: center.y + dy / dist * (r - 1))
                var arrowItem = item
                arrowItem.tool = .arrow
                arrowItem.points = [startOnRim, tip]
                arrowItem.lineStyle = .solid
                drawArrow(arrowItem, lineWidth: max(2.2, r * 0.22), dash: [], in: ctx)
            }
        }
        let circleRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        let circlePath = CGPath(ellipseIn: circleRect, transform: nil)
        fillPath(circlePath, item: item, alpha: 1.0, in: ctx)
        let fg: NSColor = (item.gradient == nil && item.color.relativeLuminance > 0.72) ? .black : .white
        drawText("\(item.counterIndex)", at: CGPoint(x: center.x - r, y: center.y - r * 0.68), fontSize: r * 1.15, color: fg, centeredWidth: r * 2, in: ctx)
    }

    private static func drawBlurRegion(
        _ item: ScreenshotAnnotation,
        baseCropped: CGImage,
        origin: CGPoint,
        scaleX: CGFloat,
        scaleY: CGFloat,
        in ctx: CGContext
    ) {
        guard let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 2, rect.height >= 2 else { return }
        let pxRect = CGRect(
            x: (rect.minX - origin.x) * scaleX,
            y: (rect.minY - origin.y) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let blurred = blurSubimage(baseCropped, pixelRect: pxRect, radius: Double(item.effectiveBlurRadius * max(scaleX, 1))) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: rect)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cr, cornerHeight: cr, transform: nil))
        ctx.clip()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(blurred, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    }

    private static func drawMosaic(
        points: [CGPoint], brushRadius: CGFloat, baseCropped: CGImage, origin: CGPoint, scaleX: CGFloat, scaleY: CGFloat, in ctx: CGContext
    ) {
        let cellSize: CGFloat = max(8, brushRadius * 0.75)
        let bounds = CGRect(x: 0, y: 0, width: baseCropped.width, height: baseCropped.height)
        var visited = Set<Int64>()
        for pt in points {
            let minCol = Int32(floor((pt.x - brushRadius) / cellSize)), maxCol = Int32(floor((pt.x + brushRadius) / cellSize))
            let minRow = Int32(floor((pt.y - brushRadius) / cellSize)), maxRow = Int32(floor((pt.y + brushRadius) / cellSize))
            for row in minRow...maxRow {
                for col in minCol...maxCol {
                    let key = (Int64(col) << 32) | Int64(UInt32(bitPattern: row))
                    guard visited.insert(key).inserted else { continue }
                    let cellRect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                    let samplePt = CGPoint(x: (cellRect.midX - origin.x) * scaleX, y: (cellRect.midY - origin.y) * scaleY)
                    if let (r, g, b) = samplePixelRGB(in: baseCropped, point: samplePt, screenBounds: bounds) {
                        ctx.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1))
                    } else {
                        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                    }
                    ctx.fill(cellRect)
                }
            }
        }
    }

    private static func drawText(_ text: String, at origin: CGPoint, fontSize: CGFloat, color: NSColor, centeredWidth: CGFloat?, in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let para = NSMutableParagraphStyle()
        para.alignment = centeredWidth == nil ? .left : .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        if let w = centeredWidth { str.draw(in: CGRect(x: origin.x, y: origin.y, width: w, height: fontSize * 1.4)) }
        else { str.draw(at: origin) }
        NSGraphicsContext.restoreGraphicsState()
    }
}
