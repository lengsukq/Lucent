import CoreGraphics
import Foundation

public extension AnnotationGeometry {
    static func hitTest(
        at point: CGPoint,
        annotations: [ScreenshotAnnotation],
        selectedID: UUID?,
        activeTool: AnnotationToolKind,
        forceMoveModifier: Bool
    ) -> AnnotationHitResult {
        if let selectedID, let selItem = annotations.first(where: { $0.id == selectedID }) {
            for (handle, hPt) in handles(for: selItem).reversed() where hypot(point.x - hPt.x, point.y - hPt.y) <= 9.5 {
                return .handle(selectedID, handle)
            }
            let b = boundingRect(for: selItem)
            if !b.isNull, b.insetBy(dx: -6, dy: -6).contains(point) {
                let smallObject = b.width <= 16 || b.height <= 16
                let inInner = !smallObject && b.insetBy(dx: 6, dy: 6).contains(point)
                if !inInner || activeTool == .move || forceMoveModifier {
                    if hitsShape(selItem, at: point, tolerance: 8) || !inInner {
                        return .borderMove(selectedID)
                    }
                }
            }
        }

        for item in annotations.reversed() where hitsShape(item, at: point, tolerance: 7) {
            if activeTool == .move || forceMoveModifier {
                return .borderMove(item.id)
            }
            return .interiorSelectOrDraw(item.id)
        }
        return .none
    }

    static func translated(_ item: ScreenshotAnnotation, dx: CGFloat, dy: CGFloat) -> ScreenshotAnnotation {
        var copy = item
        copy.points = item.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }

    static func transformed(
        _ item: ScreenshotAnnotation,
        handle: AnnotationHandle,
        to point: CGPoint,
        shiftHeld: Bool
    ) -> ScreenshotAnnotation {
        var copy = item
        switch handle {
        case .lineStart:
            guard copy.points.count >= 2 else { return copy }
            let anchor = copy.points[copy.points.count - 1]
            copy.points[0] = snapEndpoint(from: anchor, to: point, tool: item.tool, shiftHeld: shiftHeld)
            return copy
        case .lineEnd:
            guard !copy.points.isEmpty else { return copy }
            let anchor = copy.points[0]
            let snapped = snapEndpoint(from: anchor, to: point, tool: item.tool, shiftHeld: shiftHeld)
            if copy.points.count == 1 { copy.points.append(snapped) }
            else { copy.points[copy.points.count - 1] = snapped }
            return copy
        case .curveControl1, .curveControl2:
            guard let g = resolveArrow(copy) else { return copy }
            var pts = [g.p0, g.c1, g.c2, g.tip]
            pts[handle == .curveControl1 ? 1 : 2] = point
            copy.points = pts
            return copy
        case .cornerRadius:
            guard let b = boxRect(for: copy) else { return copy }
            let maxR = min(b.width, b.height) * 0.5
            let raw = max(b.maxX - point.x, point.y - b.minY) - 8
            copy.cornerRadius = min(max(0, raw), maxR)
            return copy
        default:
            let oldB = boundingRect(for: item)
            guard !oldB.isNull, oldB.width >= 2, oldB.height >= 2 else { return copy }
            let newB = resizedBounds(oldB, handle: handle, to: point, keepAspect: shiftHeld)
            if copy.tool == .text {
                let ratio = newB.height / max(oldB.height, 1)
                copy.customScale = min(max(item.customScale * ratio, 0.4), 3.5)
                copy.points = [newB.origin]
                return copy
            }
            copy.points = item.points.map { pt in
                let nx = (pt.x - oldB.minX) / oldB.width
                let ny = (pt.y - oldB.minY) / oldB.height
                return CGPoint(x: newB.minX + nx * newB.width, y: newB.minY + ny * newB.height)
            }
            return copy
        }
    }

    private static func hitsShape(_ item: ScreenshotAnnotation, at pt: CGPoint, tolerance: CGFloat) -> Bool {
        switch item.tool {
        case .move: return false
        case .rect, .ellipse, .blur, .spotlight:
            guard let b = boxRect(for: item) else { return false }
            return b.insetBy(dx: -tolerance, dy: -tolerance).contains(pt)
        case .text, .counter:
            let b = boundingRect(for: item)
            if b.insetBy(dx: -tolerance, dy: -tolerance).contains(pt) { return true }
            if item.tool == .counter, item.points.count >= 2 {
                return distanceToSegment(pt, item.points[0], item.points[1]) <= tolerance + 3
            }
            return false
        case .line:
            guard item.points.count >= 2 else { return false }
            return distanceToSegment(pt, item.points[0], item.points[1]) <= max(tolerance, item.effectiveLineWidth * 0.7)
        case .arrow:
            guard let g = resolveArrow(item) else { return false }
            let samples = sampleCubic(p0: g.p0, c1: g.c1, c2: g.c2, p3: g.tip, steps: 18)
            return distanceToPolyline(pt, samples) <= max(tolerance, item.effectiveLineWidth * 0.8 + 3)
        case .pen, .highlighter, .mosaic:
            let extra = item.tool == .mosaic ? item.effectiveMosaicRadius : item.effectiveLineWidth * 1.4
            return distanceToPolyline(pt, item.points) <= max(tolerance, extra)
        }
    }

    private static func sampleCubic(p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint, steps: Int) -> [CGPoint] {
        (0...steps).map { idx in
            let t = CGFloat(idx) / CGFloat(max(1, steps)), u = 1 - t
            let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
            let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
            return CGPoint(x: x, y: y)
        }
    }

    private static func distanceToPolyline(_ pt: CGPoint, _ poly: [CGPoint]) -> CGFloat {
        guard let first = poly.first else { return .greatestFiniteMagnitude }
        if poly.count == 1 { return hypot(pt.x - first.x, pt.y - first.y) }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(poly.count - 1) { best = min(best, distanceToSegment(pt, poly[i], poly[i + 1])) }
        return best
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let vx = b.x - a.x, vy = b.y - a.y, l2 = vx * vx + vy * vy
        guard l2 > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / l2, 0), 1)
        return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
    }

    private static func resizedBounds(_ r: CGRect, handle: AnnotationHandle, to pt: CGPoint, keepAspect: Bool) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .boundsTopLeft: minX = min(pt.x, maxX - 8); minY = min(pt.y, maxY - 8)
        case .boundsTop: minY = min(pt.y, maxY - 8)
        case .boundsTopRight: maxX = max(pt.x, minX + 8); minY = min(pt.y, maxY - 8)
        case .boundsRight: maxX = max(pt.x, minX + 8)
        case .boundsBottomRight: maxX = max(pt.x, minX + 8); maxY = max(pt.y, minY + 8)
        case .boundsBottom: maxY = max(pt.y, minY + 8)
        case .boundsBottomLeft: minX = min(pt.x, maxX - 8); maxY = max(pt.y, minY + 8)
        case .boundsLeft: minX = min(pt.x, maxX - 8)
        default: break
        }
        var out = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if keepAspect, r.height > 0 {
            let aspect = r.width / r.height
            let targetW = max(8, max(out.width, out.height * aspect))
            let targetH = max(8, targetW / max(aspect, 0.05))
            let anchorRight = handle == .boundsTopLeft || handle == .boundsLeft || handle == .boundsBottomLeft
            let anchorBottom = handle == .boundsTopLeft || handle == .boundsTop || handle == .boundsTopRight
            out = CGRect(
                x: anchorRight ? maxX - targetW : minX,
                y: anchorBottom ? maxY - targetH : minY,
                width: targetW,
                height: targetH
            )
        }
        return out
    }
}
