import CoreGraphics
import Foundation
import LucentFoundation

public struct DisplaySliceDescriptor: Equatable, Sendable, Identifiable {
    public var id: CGDirectDisplayID { displayID }
    public let displayID: CGDirectDisplayID
    public let appKitFrame: CGRect
    public let appKitVisibleFrame: CGRect
    public let cgFrame: CGRect
    public let canvasFrame: CGRect
    public let scale: CGFloat

    public init(
        displayID: CGDirectDisplayID,
        appKitFrame: CGRect,
        appKitVisibleFrame: CGRect,
        cgFrame: CGRect,
        canvasFrame: CGRect,
        scale: CGFloat
    ) {
        self.displayID = displayID
        self.appKitFrame = appKitFrame
        self.appKitVisibleFrame = appKitVisibleFrame
        self.cgFrame = cgFrame
        self.canvasFrame = canvasFrame
        self.scale = max(scale, 1.0)
    }
}

public struct MultiDisplayLayout: Equatable, Sendable {
    public let slices: [DisplaySliceDescriptor]
    public let cgUnionBounds: CGRect
    public let canvasBounds: CGRect
    public let primaryScreenHeight: CGFloat
    public let maxScale: CGFloat

    public init(
        screens: [(displayID: CGDirectDisplayID, appKitFrame: CGRect, appKitVisibleFrame: CGRect, scale: CGFloat)],
        mainDisplayID: CGDirectDisplayID
    ) {
        let primaryScreen = screens.first(where: { $0.displayID == mainDisplayID })
            ?? screens.first(where: { abs($0.appKitFrame.minX) < 0.5 && abs($0.appKitFrame.minY) < 0.5 })
            ?? screens.first
        let primaryH = primaryScreen?.appKitFrame.height ?? 900
        self.primaryScreenHeight = primaryH

        let raw: [(id: CGDirectDisplayID, ak: CGRect, vis: CGRect, cg: CGRect, scale: CGFloat)] = screens.map { item in
            let cg = CGRect(
                x: item.appKitFrame.minX,
                y: primaryH - item.appKitFrame.maxY,
                width: item.appKitFrame.width,
                height: item.appKitFrame.height
            )
            return (item.displayID, item.appKitFrame, item.appKitVisibleFrame, cg, max(item.scale, 1.0))
        }

        let union = raw.reduce(CGRect.null) { $0.union($1.cg) }
        let safeUnion = union.isNull ? CGRect(x: 0, y: 0, width: 1440, height: 900) : union
        self.cgUnionBounds = safeUnion
        self.canvasBounds = CGRect(origin: .zero, size: safeUnion.size)
        self.maxScale = raw.map(\.scale).max() ?? 2.0
        self.slices = raw.map { item in
            DisplaySliceDescriptor(
                displayID: item.id,
                appKitFrame: item.ak,
                appKitVisibleFrame: item.vis,
                cgFrame: item.cg,
                canvasFrame: item.cg.offsetBy(dx: -safeUnion.minX, dy: -safeUnion.minY),
                scale: item.scale
            )
        }
    }

    public func canvasPoint(fromAppKitGlobal nsPt: CGPoint) -> CGPoint {
        let cgX = nsPt.x
        let cgY = primaryScreenHeight - nsPt.y
        return CGPoint(x: cgX - cgUnionBounds.minX, y: cgY - cgUnionBounds.minY)
    }

    public func appKitGlobalPoint(fromCanvas pt: CGPoint) -> CGPoint {
        let cgX = pt.x + cgUnionBounds.minX
        let cgY = pt.y + cgUnionBounds.minY
        return CGPoint(x: cgX, y: primaryScreenHeight - cgY)
    }

    public func appKitGlobalRect(fromCanvas rect: CGRect) -> CGRect {
        let std = rect.standardized
        let cgRect = std.offsetBy(dx: cgUnionBounds.minX, dy: cgUnionBounds.minY)
        return CGRect(
            x: cgRect.minX,
            y: primaryScreenHeight - cgRect.maxY,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    public func canvasRect(fromQuartzGlobal cgRect: CGRect) -> CGRect {
        cgRect.offsetBy(dx: -cgUnionBounds.minX, dy: -cgUnionBounds.minY)
    }

    public func quartzGlobalRect(fromCanvas rect: CGRect) -> CGRect {
        rect.standardized.offsetBy(dx: cgUnionBounds.minX, dy: cgUnionBounds.minY)
    }

    public func slice(containingCanvasPoint pt: CGPoint) -> DisplaySliceDescriptor? {
        if let exact = slices.first(where: { $0.canvasFrame.contains(pt) }) {
            return exact
        }
        return slices.min { lhs, rhs in
            Self.distanceSquared(from: pt, to: lhs.canvasFrame) < Self.distanceSquared(from: pt, to: rhs.canvasFrame)
        }
    }

    public func targetSlice(forSelection sel: CGRect, fallbackPoint: CGPoint) -> DisplaySliceDescriptor? {
        let std = sel.standardized
        let bottomRight = CGPoint(x: std.maxX - 0.5, y: std.maxY - 0.5)
        if let hit = slices.first(where: { $0.canvasFrame.contains(bottomRight) }) {
            return hit
        }
        let bestOverlap = slices
            .compactMap { s -> (DisplaySliceDescriptor, CGFloat)? in
                let inter = s.canvasFrame.intersection(std)
                guard !inter.isNull, inter.width > 0, inter.height > 0 else { return nil }
                return (s, inter.width * inter.height)
            }
            .max(by: { $0.1 < $1.1 })?.0
        return bestOverlap ?? slice(containingCanvasPoint: fallbackPoint)
    }

    public func intersectingSlices(forSelection sel: CGRect) -> [DisplaySliceDescriptor] {
        let std = sel.standardized
        return slices.filter { s in
            let inter = s.canvasFrame.intersection(std)
            return !inter.isNull && inter.width >= 0.5 && inter.height >= 0.5
        }
    }

    public func effectiveScale(forSelection sel: CGRect) -> CGFloat {
        let hits = intersectingSlices(forSelection: sel)
        if let best = hits.map(\.scale).max() {
            return best
        }
        let center = CGPoint(x: sel.midX, y: sel.midY)
        return slice(containingCanvasPoint: center)?.scale ?? maxScale
    }

    public static func clampedLocalSourceRect(forSelection canvasRect: CGRect, in sliceFrame: CGRect) -> CGRect? {
        let std = canvasRect.standardized
        let inter = sliceFrame.intersection(std)
        guard !inter.isNull, inter.width >= 1.0, inter.height >= 1.0 else { return nil }
        let localBounds = CGRect(origin: .zero, size: sliceFrame.size)
        let rawLocal = CGRect(
            x: max(0, inter.minX - sliceFrame.minX),
            y: max(0, inter.minY - sliceFrame.minY),
            width: inter.width,
            height: inter.height
        ).intersection(localBounds)
        guard !rawLocal.isNull, rawLocal.width >= 1.0, rawLocal.height >= 1.0 else { return nil }
        return rawLocal
    }

    public static func clampedHUDFrame(preferredSize: CGSize, near region: CGRect, visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 8
        let safeW = min(preferredSize.width, max(280, visibleFrame.width - margin * 2))
        let safeH = min(preferredSize.height, max(44, visibleFrame.height - margin * 2))
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - safeW - margin)
        let x = min(max(region.midX - safeW / 2, minX), maxX)

        let aboveY = region.maxY + 10
        let belowY = region.minY - safeH - 10
        let y: CGFloat
        if aboveY + safeH <= visibleFrame.maxY - 4 {
            y = aboveY
        } else if belowY >= visibleFrame.minY + 4 {
            y = belowY
        } else {
            let minY = visibleFrame.minY + margin
            let maxY = max(minY, visibleFrame.maxY - safeH - margin)
            y = min(max(visibleFrame.maxY - safeH - margin, minY), maxY)
        }
        return CGRect(x: x, y: y, width: safeW, height: safeH)
    }

    public func clampedPinFrame(forAppKitSelection rect: CGRect) -> CGRect {
        let matching = slices.filter { !$0.appKitFrame.intersection(rect).isNull }
        if matching.count <= 1 {
            return rect
        }
        guard let dominant = matching.max(by: {
            let a = $0.appKitFrame.intersection(rect)
            let b = $1.appKitFrame.intersection(rect)
            return (a.width * a.height) < (b.width * b.height)
        }) else {
            return rect
        }
        let vis = dominant.appKitVisibleFrame
        let ratio = max(rect.width / max(rect.height, 1), 0.1)
        var w = min(rect.width, max(120, vis.width - 24))
        var h = w / ratio
        if h > vis.height - 24 {
            h = max(90, vis.height - 24)
            w = h * ratio
        }
        let minX = vis.minX + 12
        let maxX = max(minX, vis.maxX - w - 12)
        let minY = vis.minY + 12
        let maxY = max(minY, vis.maxY - h - 12)
        let x = min(max(rect.midX - w / 2, minX), maxX)
        let y = min(max(rect.midY - h / 2, minY), maxY)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func distanceSquared(from pt: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - pt.x, 0, pt.x - rect.maxX)
        let dy = max(rect.minY - pt.y, 0, pt.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
