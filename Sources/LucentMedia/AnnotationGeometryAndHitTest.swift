import CoreGraphics
import Foundation

public enum AnnotationHandle: Equatable, Hashable, Sendable {
    case boundsTopLeft, boundsTop, boundsTopRight, boundsRight
    case boundsBottomRight, boundsBottom, boundsBottomLeft, boundsLeft
    case lineStart, lineEnd
    case curveControl1, curveControl2
    case cornerRadius
}

public enum AnnotationHitResult: Equatable, Sendable {
    case handle(UUID, AnnotationHandle)
    case borderMove(UUID)
    case interiorSelectOrDraw(UUID)
    case none
}

public struct ResolvedArrowGeometry: Equatable, Sendable {
    public let p0: CGPoint
    public let c1: CGPoint
    public let c2: CGPoint
    public let tip: CGPoint
    public let shaftEnd: CGPoint
    public let leftWing: CGPoint
    public let rightWing: CGPoint
    public let isCurved: Bool
}

public enum AnnotationGeometry {
    public static func snapEndpoint(
        from start: CGPoint,
        to rawEnd: CGPoint,
        tool: AnnotationToolKind,
        shiftHeld: Bool
    ) -> CGPoint {
        guard shiftHeld else { return rawEnd }
        let dx = rawEnd.x - start.x
        let dy = rawEnd.y - start.y
        switch tool {
        case .rect, .ellipse, .blur, .spotlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(
                x: start.x + (dx >= 0 ? side : -side),
                y: start.y + (dy >= 0 ? side : -side)
            )
        case .line, .arrow, .counter:
            let len = hypot(dx, dy)
            guard len > 1 else { return rawEnd }
            let step = CGFloat.pi / 4.0
            let snappedAngle = round(atan2(dy, dx) / step) * step
            return CGPoint(x: start.x + cos(snappedAngle) * len, y: start.y + sin(snappedAngle) * len)
        default:
            return rawEnd
        }
    }

    public static func appendSampledPoint(_ pt: CGPoint, to points: inout [CGPoint], minimumStep: CGFloat = 2.0) {
        guard let last = points.last else { points.append(pt); return }
        if hypot(pt.x - last.x, pt.y - last.y) >= minimumStep {
            points.append(pt)
        }
    }

    public static func smoothedFreehandPath(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) * 0.5, y: (points[i].y + points[i + 1].y) * 0.5)
            path.addQuadCurve(to: mid, control: points[i])
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    public static func resolveArrow(_ item: ScreenshotAnnotation) -> ResolvedArrowGeometry? {
        guard item.points.count >= 2 else { return nil }
        let p0 = item.points[0]
        let p3 = item.points[item.points.count - 1]
        let isCurved = item.points.count == 4
        let c1 = isCurved ? item.points[1] : CGPoint(x: p0.x + (p3.x - p0.x) / 3.0, y: p0.y + (p3.y - p0.y) / 3.0)
        let c2 = isCurved ? item.points[2] : CGPoint(x: p0.x + (p3.x - p0.x) * 2.0 / 3.0, y: p0.y + (p3.y - p0.y) * 2.0 / 3.0)
        var tx = p3.x - c2.x, ty = p3.y - c2.y
        if hypot(tx, ty) < 0.5 { tx = p3.x - c1.x; ty = p3.y - c1.y }
        if hypot(tx, ty) < 0.5 { tx = p3.x - p0.x; ty = p3.y - p0.y }
        let tLen = hypot(tx, ty)
        guard tLen > 0.5 else { return nil }
        let ux = tx / tLen, uy = ty / tLen
        let headLen = max(12.0, item.effectiveLineWidth * 3.2)
        let headHalfW = headLen * 0.48
        let shaftEnd = CGPoint(x: p3.x - ux * headLen * 0.74, y: p3.y - uy * headLen * 0.74)
        let left = CGPoint(x: p3.x - ux * headLen + uy * headHalfW, y: p3.y - uy * headLen - ux * headHalfW)
        let right = CGPoint(x: p3.x - ux * headLen - uy * headHalfW, y: p3.y - uy * headLen + ux * headHalfW)
        return ResolvedArrowGeometry(
            p0: p0, c1: c1, c2: c2, tip: p3, shaftEnd: shaftEnd,
            leftWing: left, rightWing: right, isCurved: isCurved
        )
    }

    public static func boxRect(for item: ScreenshotAnnotation) -> CGRect? {
        guard item.points.count >= 2 else { return nil }
        let a = item.points[0], b = item.points[item.points.count - 1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    public static func clampedCornerRadius(for item: ScreenshotAnnotation, in rect: CGRect) -> CGFloat {
        let maxR = min(rect.width, rect.height) * 0.5
        if item.tool == .spotlight && item.cornerRadius == 0 {
            return min(8, maxR * 0.5)
        }
        return min(max(0, item.cornerRadius), maxR)
    }

    public static func boundingRect(for item: ScreenshotAnnotation) -> CGRect {
        switch item.tool {
        case .move:
            return .null
        case .rect, .ellipse, .blur, .spotlight:
            return boxRect(for: item) ?? .null
        case .line:
            guard item.points.count >= 2 else { return .null }
            return pointsBounds(item.points).insetBy(dx: -4, dy: -4)
        case .arrow:
            guard let g = resolveArrow(item) else { return .null }
            return pointsBounds([g.p0, g.c1, g.c2, g.tip, g.leftWing, g.rightWing]).insetBy(dx: -4, dy: -4)
        case .pen, .highlighter, .mosaic:
            let pad = item.tool == .mosaic ? item.effectiveMosaicRadius : item.effectiveLineWidth * 1.6
            return pointsBounds(item.points).insetBy(dx: -pad, dy: -pad)
        case .counter:
            guard let c = item.points.first else { return .null }
            let r = item.effectiveCounterRadius
            var rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if item.points.count >= 2 {
                rect = rect.union(CGRect(origin: item.points[1], size: .zero).insetBy(dx: -6, dy: -6))
            }
            return rect
        case .text:
            guard let pt = item.points.first else { return .null }
            let fs = item.effectiveFontSize
            let lines = max(1, item.text.split(separator: "\n", omittingEmptySubsequences: false).count)
            let maxChars = max(2, item.text.split(separator: "\n").map(\.count).max() ?? item.text.count)
            let estW = max(36, CGFloat(maxChars) * fs * 0.68 + 8)
            let estH = max(fs * 1.35, CGFloat(lines) * fs * 1.32)
            return CGRect(x: pt.x, y: pt.y, width: estW, height: estH)
        }
    }

    public static func supportsCornerHandle(_ tool: AnnotationToolKind) -> Bool {
        tool == .rect || tool == .blur || tool == .spotlight
    }

    public static func handles(for item: ScreenshotAnnotation) -> [(AnnotationHandle, CGPoint)] {
        switch item.tool {
        case .line:
            guard item.points.count >= 2 else { return [] }
            return [(.lineStart, item.points[0]), (.lineEnd, item.points[item.points.count - 1])]
        case .arrow:
            guard let g = resolveArrow(item) else { return [] }
            return [(.lineStart, g.p0), (.curveControl1, g.c1), (.curveControl2, g.c2), (.lineEnd, g.tip)]
        case .counter:
            guard let c = item.points.first, item.points.count >= 2 else { return [] }
            return [(.lineStart, c), (.lineEnd, item.points[1])]
        default:
            let b = boundingRect(for: item)
            guard !b.isNull, b.width >= 4, b.height >= 4 else { return [] }
            var list: [(AnnotationHandle, CGPoint)] = [
                (.boundsTopLeft, CGPoint(x: b.minX, y: b.minY)),
                (.boundsTop, CGPoint(x: b.midX, y: b.minY)),
                (.boundsTopRight, CGPoint(x: b.maxX, y: b.minY)),
                (.boundsRight, CGPoint(x: b.maxX, y: b.midY)),
                (.boundsBottomRight, CGPoint(x: b.maxX, y: b.maxY)),
                (.boundsBottom, CGPoint(x: b.midX, y: b.maxY)),
                (.boundsBottomLeft, CGPoint(x: b.minX, y: b.maxY)),
                (.boundsLeft, CGPoint(x: b.minX, y: b.midY))
            ]
            if supportsCornerHandle(item.tool), min(b.width, b.height) >= 24 {
                let r = clampedCornerRadius(for: item, in: b)
                let offset = max(10, min(min(b.width, b.height) * 0.45, r + 10))
                list.append((.cornerRadius, CGPoint(x: b.maxX - offset, y: b.minY + offset)))
            }
            return list
        }
    }

    static func pointsBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}
