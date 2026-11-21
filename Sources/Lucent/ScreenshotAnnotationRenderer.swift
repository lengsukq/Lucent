import AppKit
import LucentCore
import LucentMedia
import SwiftUI

enum ScreenshotAnnotationRenderer {
    static func renderMosaicMask(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        guard item.tool == .mosaic, !item.points.isEmpty else { return }
        let p = Path(AnnotationGeometry.smoothedFreehandPath(for: item.points))
        ctx.stroke(
            p,
            with: .color(.white),
            style: StrokeStyle(lineWidth: item.effectiveMosaicRadius * 1.6, lineCap: .round, lineJoin: .round)
        )
    }

    static func renderBlurMask(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        guard item.tool == .blur, let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 2, rect.height >= 2 else { return }
        let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: rect)
        ctx.fill(Path(roundedRect: rect, cornerRadius: cr), with: .color(.white))
    }

    static func renderSpotlightOverlay(_ items: [ScreenshotAnnotation], selection: CGRect, in ctx: inout GraphicsContext) {
        guard !items.isEmpty else { return }
        var p = Path()
        p.addRect(selection)
        for item in items {
            guard let hole = AnnotationGeometry.boxRect(for: item), hole.width >= 2, hole.height >= 2 else { continue }
            let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: hole)
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: cr, height: cr))
        }
        ctx.fill(p, with: .color(.black.opacity(0.54)), style: FillStyle(eoFill: true))
    }

    static func render(_ item: ScreenshotAnnotation, isEditingText: Bool = false, in ctx: inout GraphicsContext) {
        let lw = item.effectiveLineWidth
        let dash = item.lineStyle.dashPattern(for: lw)

        switch item.tool {
        case .move, .mosaic, .blur, .spotlight:
            break
        case .rect:
            guard let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 1, rect.height >= 1 else { break }
            let cr = AnnotationGeometry.clampedCornerRadius(for: item, in: rect)
            let path = Path(roundedRect: rect, cornerRadius: cr)
            if item.isFilled { ctx.fill(path, with: shading(for: item, bounds: rect, opacity: 0.22)) }
            ctx.stroke(path, with: shading(for: item, bounds: rect), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round, dash: dash))
        case .ellipse:
            guard let rect = AnnotationGeometry.boxRect(for: item), rect.width >= 1, rect.height >= 1 else { break }
            let path = Path(ellipseIn: rect)
            if item.isFilled { ctx.fill(path, with: shading(for: item, bounds: rect, opacity: 0.22)) }
            ctx.stroke(path, with: shading(for: item, bounds: rect), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round, dash: dash))
        case .line:
            guard item.points.count >= 2 else { break }
            var line = Path()
            line.move(to: item.points[0]); line.addLine(to: item.points[item.points.count - 1])
            let b = AnnotationGeometry.boundingRect(for: item)
            ctx.stroke(line, with: shading(for: item, bounds: b), style: StrokeStyle(lineWidth: lw, lineCap: .round, dash: dash))
        case .arrow:
            renderArrow(item, lineWidth: lw, dash: dash, in: &ctx)
        case .pen:
            guard !item.points.isEmpty else { break }
            let p = Path(AnnotationGeometry.smoothedFreehandPath(for: item.points))
            let b = AnnotationGeometry.boundingRect(for: item)
            ctx.stroke(p, with: shading(for: item, bounds: b), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round, dash: dash))
        case .highlighter:
            guard !item.points.isEmpty else { break }
            let p = Path(AnnotationGeometry.smoothedFreehandPath(for: item.points))
            let c = Color(cgColor: item.color.cgColor).opacity(0.48)
            ctx.drawLayer { layer in
                layer.blendMode = .multiply
                layer.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: lw * 3.0, lineCap: .round, lineJoin: .round))
            }
        case .counter:
            renderCounter(item, in: &ctx)
        case .text:
            guard !isEditingText, let pt = item.points.first, !item.text.isEmpty else { break }
            let c = Color(cgColor: item.color.cgColor)
            ctx.draw(Text(item.text).font(.system(size: item.effectiveFontSize, weight: .bold)).foregroundStyle(c), at: pt, anchor: .topLeading)
        }
    }

    static func renderSelectionGizmo(for item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        if item.tool == .arrow, let g = AnnotationGeometry.resolveArrow(item) {
            var guide = Path()
            guide.move(to: g.p0); guide.addLine(to: g.c1)
            guide.move(to: g.tip); guide.addLine(to: g.c2)
            ctx.stroke(guide, with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else if item.tool != .line && item.tool != .counter {
            let b = AnnotationGeometry.boundingRect(for: item)
            if !b.isNull {
                ctx.stroke(Path(b), with: .color(.cyan.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
        }
        for (handle, pt) in AnnotationGeometry.handles(for: item) {
            let isCorner = handle == .cornerRadius
            let isCurve = handle == .curveControl1 || handle == .curveControl2
            let radius: CGFloat = isCorner ? 4.2 : 4.6
            let rect = CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2)
            let fill: Color = isCorner ? .yellow : (isCurve ? .cyan : .white)
            let stroke: Color = isCorner ? .orange : .accentColor
            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.5)
        }
    }

    private static func renderArrow(_ item: ScreenshotAnnotation, lineWidth: CGFloat, dash: [CGFloat], in ctx: inout GraphicsContext) {
        guard let g = AnnotationGeometry.resolveArrow(item) else { return }
        var shaft = Path()
        shaft.move(to: g.p0)
        if g.isCurved { shaft.addCurve(to: g.shaftEnd, control1: g.c1, control2: g.c2) }
        else { shaft.addLine(to: g.shaftEnd) }
        let b = AnnotationGeometry.boundingRect(for: item)
        ctx.stroke(shaft, with: shading(for: item, bounds: b), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))
        var head = Path()
        head.move(to: g.tip); head.addLine(to: g.leftWing); head.addLine(to: g.rightWing); head.closeSubpath()
        ctx.fill(head, with: shading(for: item, bounds: b))
    }

    private static func renderCounter(_ item: ScreenshotAnnotation, in ctx: inout GraphicsContext) {
        guard let c = item.points.first else { return }
        let r = item.effectiveCounterRadius
        if item.points.count >= 2 {
            let tip = item.points[1]
            let dx = tip.x - c.x, dy = tip.y - c.y, dist = hypot(dx, dy)
            if dist > r + 4 {
                var arrow = item
                arrow.tool = .arrow
                arrow.points = [CGPoint(x: c.x + dx / dist * (r - 1), y: c.y + dy / dist * (r - 1)), tip]
                arrow.lineStyle = .solid
                renderArrow(arrow, lineWidth: max(2.2, r * 0.22), dash: [], in: &ctx)
            }
        }
        let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: circle), with: shading(for: item, bounds: circle))
        let fg: Color = (item.gradient == nil && item.color.relativeLuminance > 0.72) ? .black : .white
        ctx.draw(Text("\(item.counterIndex)").font(.system(size: r * 1.15, weight: .bold)).foregroundStyle(fg), at: c)
    }

    private static func shading(for item: ScreenshotAnnotation, bounds: CGRect, opacity: Double = 1.0) -> GraphicsContext.Shading {
        if let grad = item.gradient, !bounds.isNull {
            let colors = [
                Color(cgColor: grad.start.cgColor).opacity(opacity),
                Color(cgColor: grad.mid.cgColor).opacity(opacity),
                Color(cgColor: grad.end.cgColor).opacity(opacity)
            ]
            return .linearGradient(
                Gradient(colors: colors),
                startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
            )
        }
        return .color(Color(cgColor: item.color.cgColor).opacity(opacity))
    }
}
