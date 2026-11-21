import CoreGraphics
import Foundation

public enum PluginWindowEdge: String, Codable, Sendable, Hashable, CaseIterable {
    case left, right, top, bottom
}

public enum PluginWindowAnchor: String, Codable, Sendable, Hashable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case center, topCenter, bottomCenter, leftCenter, rightCenter
}

public enum PluginWindowEasing: String, Codable, Sendable, Hashable, CaseIterable {
    case easeOut, easeInOut, spring, linear
}

public struct PluginWindowScreenRect: Sendable, Hashable, Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let displayID: UInt32
    public let isMain: Bool

    public init(frame: CGRect, visibleFrame: CGRect, displayID: UInt32 = 0, isMain: Bool = false) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.displayID = displayID
        self.isMain = isMain
    }

    public static let fallback = PluginWindowScreenRect(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        displayID: 0,
        isMain: true
    )
}

public struct PluginWindowEdgeMetrics: Sendable, Hashable, Equatable {
    public let distLeft: Double
    public let distRight: Double
    public let distTop: Double
    public let distBottom: Double
    public let nearestEdge: PluginWindowEdge
    public let nearestDistance: Double
    public let outOfBounds: Bool

    public func edgeWithin(threshold: Double) -> PluginWindowEdge? {
        let clampedThreshold = max(0, threshold)
        return nearestDistance <= clampedThreshold ? nearestEdge : nil
    }
}

public enum PluginWindowGeometry {
    public static let minStandardWidth: CGFloat = 180
    public static let minStandardHeight: CGFloat = 96
    public static let minFloatingWidth: CGFloat = 64
    public static let minFloatingHeight: CGFloat = 36
    public static let maxWidth: CGFloat = 2400
    public static let maxHeight: CGFloat = 1600
    public static let defaultDurationMs: Double = 340
    public static let maxDurationMs: Double = 1200
    public static let defaultEdgeThreshold: Double = 28
    public static let minVisibleDragInset: CGFloat = 56

    public static func finiteDouble(_ raw: Double?, fallback: Double) -> Double {
        guard let raw, raw.isFinite else { return fallback }
        return raw
    }

    public static func clampDurationMs(_ raw: Double?) -> Double {
        let val = finiteDouble(raw, fallback: defaultDurationMs)
        return min(max(val, 0), maxDurationMs)
    }

    public static func clampSize(
        width: CGFloat,
        height: CGFloat,
        allowCompactFloating: Bool
    ) -> CGSize {
        let minW = allowCompactFloating ? minFloatingWidth : minStandardWidth
        let minH = allowCompactFloating ? minFloatingHeight : minStandardHeight
        let safeW = width.isFinite ? min(max(width, minW), maxWidth) : minW
        let safeH = height.isFinite ? min(max(height, minH), maxHeight) : minH
        return CGSize(width: safeW.rounded(), height: safeH.rounded())
    }

    public static func bestScreen(
        for frame: CGRect,
        screens: [PluginWindowScreenRect]
    ) -> PluginWindowScreenRect {
        guard !screens.isEmpty else { return .fallback }
        var bestByArea: (screen: PluginWindowScreenRect, area: CGFloat)?
        for screen in screens {
            let overlap = frame.intersection(screen.frame)
            if !overlap.isNull && overlap.width > 0 && overlap.height > 0 {
                let area = overlap.width * overlap.height
                if bestByArea == nil || area > bestByArea!.area {
                    bestByArea = (screen, area)
                }
            }
        }
        if let bestByArea { return bestByArea.screen }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { lhs, rhs in
            squaredDistance(from: center, to: lhs.visibleFrame) < squaredDistance(from: center, to: rhs.visibleFrame)
        } ?? screens.first(where: \.isMain) ?? screens[0]
    }

    public static func clampFrameToVisible(
        _ frame: CGRect,
        visibleFrame: CGRect,
        margin: CGFloat = 0
    ) -> CGRect {
        let safeMargin = max(0, margin.isFinite ? margin : 0)
        let maxW = max(minFloatingWidth, visibleFrame.width - safeMargin * 2)
        let maxH = max(minFloatingHeight, visibleFrame.height - safeMargin * 2)
        let w = min(frame.width.isFinite ? max(frame.width, minFloatingWidth) : minStandardWidth, maxW)
        let h = min(frame.height.isFinite ? max(frame.height, minFloatingHeight) : minStandardHeight, maxH)

        let minX = visibleFrame.minX + safeMargin
        let maxX = max(minX, visibleFrame.maxX - w - safeMargin)
        let minY = visibleFrame.minY + safeMargin
        let maxY = max(minY, visibleFrame.maxY - h - safeMargin)

        let rawX = frame.origin.x.isFinite ? frame.origin.x : minX
        let rawY = frame.origin.y.isFinite ? frame.origin.y : maxY
        return CGRect(
            x: min(max(rawX, minX), maxX).rounded(),
            y: min(max(rawY, minY), maxY).rounded(),
            width: w.rounded(),
            height: h.rounded()
        )
    }

    public static func clampDragOrigin(
        _ origin: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        keepFullyOnScreen: Bool
    ) -> CGPoint {
        let rawX = origin.x.isFinite ? origin.x : visibleFrame.minX
        let rawY = origin.y.isFinite ? origin.y : visibleFrame.minY
        if keepFullyOnScreen {
            let clamped = clampFrameToVisible(CGRect(origin: CGPoint(x: rawX, y: rawY), size: size), visibleFrame: visibleFrame, margin: 0)
            return clamped.origin
        }
        let keepX = min(size.width, max(minVisibleDragInset, size.width * 0.45))
        let keepY = min(size.height, max(minVisibleDragInset, size.height * 0.5))
        let minX = visibleFrame.minX - (size.width - keepX)
        let maxX = visibleFrame.maxX - keepX
        let minY = visibleFrame.minY - (size.height - keepY)
        let maxY = visibleFrame.maxY - keepY
        return CGPoint(
            x: min(max(rawX, minX), maxX).rounded(),
            y: min(max(rawY, minY), maxY).rounded()
        )
    }

    public static func computeEdgeMetrics(
        frame: CGRect,
        visibleFrame: CGRect
    ) -> PluginWindowEdgeMetrics {
        let distLeft = Double(frame.minX - visibleFrame.minX)
        let distRight = Double(visibleFrame.maxX - frame.maxX)
        let distTop = Double(visibleFrame.maxY - frame.maxY)
        let distBottom = Double(frame.minY - visibleFrame.minY)
        let candidates: [(PluginWindowEdge, Double)] = [
            (.left, distLeft),
            (.right, distRight),
            (.top, distTop),
            (.bottom, distBottom)
        ]
        let nearest = candidates.min(by: { $0.1 < $1.1 }) ?? (.right, distRight)
        let outOfBounds = distLeft < -0.5 || distRight < -0.5 || distTop < -0.5 || distBottom < -0.5
        return PluginWindowEdgeMetrics(
            distLeft: distLeft.rounded(),
            distRight: distRight.rounded(),
            distTop: distTop.rounded(),
            distBottom: distBottom.rounded(),
            nearestEdge: nearest.0,
            nearestDistance: nearest.1.rounded(),
            outOfBounds: outOfBounds
        )
    }

    public static func anchoredFrame(
        current: CGRect,
        targetSize: CGSize,
        anchor: PluginWindowAnchor
    ) -> CGRect {
        let dw = targetSize.width - current.width
        let dh = targetSize.height - current.height
        let x: CGFloat
        switch anchor {
        case .topLeft, .bottomLeft, .leftCenter: x = current.origin.x
        case .topRight, .bottomRight, .rightCenter: x = current.origin.x - dw
        case .center, .topCenter, .bottomCenter: x = current.origin.x - dw / 2
        }
        let y: CGFloat
        switch anchor {
        case .bottomLeft, .bottomRight, .bottomCenter: y = current.origin.y
        case .topLeft, .topRight, .topCenter: y = current.origin.y - dh
        case .center, .leftCenter, .rightCenter: y = current.origin.y - dh / 2
        }
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: targetSize)
    }

    public static func snappedFrame(
        current: CGRect,
        targetSize: CGSize?,
        edge: PluginWindowEdge,
        margin: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let size = targetSize ?? current.size
        let safeMargin = max(0, margin.isFinite ? margin : 0)
        var origin = CGPoint(
            x: current.midX - size.width / 2,
            y: current.midY - size.height / 2
        )
        switch edge {
        case .left: origin.x = visibleFrame.minX + safeMargin
        case .right: origin.x = visibleFrame.maxX - size.width - safeMargin
        case .top: origin.y = visibleFrame.maxY - size.height - safeMargin
        case .bottom: origin.y = visibleFrame.minY + safeMargin
        }
        return clampFrameToVisible(CGRect(origin: origin, size: size), visibleFrame: visibleFrame, margin: safeMargin)
    }

    public static func framePayload(
        frame: CGRect,
        screen: PluginWindowScreenRect,
        edgeThreshold: Double = defaultEdgeThreshold,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        let metrics = computeEdgeMetrics(frame: frame, visibleFrame: screen.visibleFrame)
        let nearEdge = metrics.edgeWithin(threshold: edgeThreshold)?.rawValue
        var edges: [String: Any] = [
            "distLeft": metrics.distLeft,
            "distRight": metrics.distRight,
            "distTop": metrics.distTop,
            "distBottom": metrics.distBottom,
            "nearestEdge": metrics.nearestEdge.rawValue,
            "nearestDistance": metrics.nearestDistance,
            "outOfBounds": metrics.outOfBounds
        ]
        if let nearEdge { edges["nearEdge"] = nearEdge }
        var out: [String: Any] = [
            "ok": true,
            "x": Int(frame.origin.x.rounded()),
            "y": Int(frame.origin.y.rounded()),
            "width": Int(frame.size.width.rounded()),
            "height": Int(frame.size.height.rounded()),
            "screen": [
                "x": Int(screen.frame.origin.x.rounded()),
                "y": Int(screen.frame.origin.y.rounded()),
                "width": Int(screen.frame.size.width.rounded()),
                "height": Int(screen.frame.size.height.rounded()),
                "visibleX": Int(screen.visibleFrame.origin.x.rounded()),
                "visibleY": Int(screen.visibleFrame.origin.y.rounded()),
                "visibleWidth": Int(screen.visibleFrame.size.width.rounded()),
                "visibleHeight": Int(screen.visibleFrame.size.height.rounded()),
                "displayId": Int(screen.displayID),
                "isMain": screen.isMain
            ],
            "edges": edges
        ]
        for (k, v) in extra { out[k] = v }
        return out
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
