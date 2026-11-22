import CoreGraphics
import Foundation

public enum WindowLayoutGeometry {
    public static let maxGap: CGFloat = 32
    public static let minWindowWidth: CGFloat = 140
    public static let minWindowHeight: CGFloat = 100

    /// Converts a Cocoa-space rect (bottom-left primary origin) into Quartz-space (top-left primary origin).
    public static func quartzRect(fromCocoa cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: cocoaRect.origin.x.rounded(),
            y: (primaryScreenHeight - cocoaRect.maxY).rounded(),
            width: max(0, cocoaRect.size.width).rounded(),
            height: max(0, cocoaRect.size.height).rounded()
        )
    }

    public static func bestDisplayIndex(for frame: CGRect, in displays: [SystemDisplayRect]) -> Int {
        guard !displays.isEmpty else { return 0 }
        var bestIdx = displays.firstIndex(where: \.isMain) ?? 0
        var bestArea: CGFloat = -1
        for (idx, display) in displays.enumerated() {
            let inter = display.frame.intersection(frame)
            let area = inter.isNull ? 0 : (inter.width * inter.height)
            if area > bestArea {
                bestArea = area
                bestIdx = idx
            }
        }
        if bestArea > 0 { return bestIdx }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.enumerated().min { lhs, rhs in
            squaredDistance(center, to: lhs.element.frame) < squaredDistance(center, to: rhs.element.frame)
        }?.offset ?? bestIdx
    }

    public static func resolveDisplay(
        preferredID: UInt32?,
        preferredIndex: Int,
        in displays: [SystemDisplayRect]
    ) -> SystemDisplayRect? {
        guard !displays.isEmpty else { return nil }
        if let id = preferredID, let exact = displays.first(where: { $0.displayID == id }) {
            return exact
        }
        if displays.indices.contains(preferredIndex) {
            return displays[preferredIndex]
        }
        return displays.first(where: \.isMain) ?? displays.first
    }

    public static func normalizedRect(of frame: CGRect, in visibleFrame: CGRect) -> NormalizedWindowRect {
        let w = max(1, visibleFrame.width)
        let h = max(1, visibleFrame.height)
        let rx = clamp(Double((frame.minX - visibleFrame.minX) / w), min: 0, max: 0.95)
        let ry = clamp(Double((frame.minY - visibleFrame.minY) / h), min: 0, max: 0.95)
        let rw = clamp(Double(frame.width / w), min: 0.08, max: 1.0 - rx)
        let rh = clamp(Double(frame.height / h), min: 0.08, max: 1.0 - ry)
        return NormalizedWindowRect(rx: rx, ry: ry, rw: rw, rh: rh)
    }

    public static func denormalizedFrame(
        _ norm: NormalizedWindowRect,
        in visibleFrame: CGRect,
        gap: CGFloat = 0
    ) -> CGRect {
        let g = clampGap(gap)
        let inner = insetVisible(visibleFrame, gap: g)
        let rx = clamp(norm.rx, min: 0, max: 0.92)
        let ry = clamp(norm.ry, min: 0, max: 0.92)
        let rw = clamp(norm.rw, min: 0.12, max: 1.0 - rx)
        let rh = clamp(norm.rh, min: 0.12, max: 1.0 - ry)
        let width = max(minWindowWidth, (inner.width * CGFloat(rw)).rounded())
        let height = max(minWindowHeight, (inner.height * CGFloat(rh)).rounded())
        let x = clamp(inner.minX + (inner.width * CGFloat(rx)).rounded(), min: inner.minX, max: max(inner.minX, inner.maxX - width))
        let y = clamp(inner.minY + (inner.height * CGFloat(ry)).rounded(), min: inner.minY, max: max(inner.minY, inner.maxY - height))
        return CGRect(x: x, y: y, width: min(width, inner.width), height: min(height, inner.height))
    }

    public static func targetFrame(
        for preset: WindowSnapPreset,
        currentFrame: CGRect,
        displays: [SystemDisplayRect],
        currentDisplayIndex: Int,
        gap: CGFloat = 0
    ) -> (frame: CGRect, displayIndex: Int) {
        guard !displays.isEmpty else { return (currentFrame, 0) }
        let safeIdx = displays.indices.contains(currentDisplayIndex) ? currentDisplayIndex : 0
        let g = clampGap(gap)

        if preset == .nextDisplay || preset == .prevDisplay {
            guard displays.count > 1 else {
                return (clampFrame(currentFrame, to: insetVisible(displays[safeIdx].visibleFrame, gap: g)), safeIdx)
            }
            let delta = preset == .nextDisplay ? 1 : -1
            let nextIdx = (safeIdx + delta + displays.count) % displays.count
            let norm = normalizedRect(of: currentFrame, in: displays[safeIdx].visibleFrame)
            let moved = denormalizedFrame(norm, in: displays[nextIdx].visibleFrame, gap: g)
            return (moved, nextIdx)
        }

        let inner = insetVisible(displays[safeIdx].visibleFrame, gap: g)
        let halfW = floor((inner.width - g) / 2)
        let rightW = inner.width - halfW - g
        let halfH = floor((inner.height - g) / 2)
        let bottomH = inner.height - halfH - g
        let thirdW = floor((inner.width - 2 * g) / 3)
        let rightThirdW = inner.width - 2 * (thirdW + g)

        let rect: CGRect = switch preset {
        case .leftHalf: CGRect(x: inner.minX, y: inner.minY, width: halfW, height: inner.height)
        case .rightHalf: CGRect(x: inner.minX + halfW + g, y: inner.minY, width: rightW, height: inner.height)
        case .topHalf: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: halfH)
        case .bottomHalf: CGRect(x: inner.minX, y: inner.minY + halfH + g, width: inner.width, height: bottomH)
        case .leftThird: CGRect(x: inner.minX, y: inner.minY, width: thirdW, height: inner.height)
        case .centerThird: CGRect(x: inner.minX + thirdW + g, y: inner.minY, width: thirdW, height: inner.height)
        case .rightThird: CGRect(x: inner.minX + 2 * (thirdW + g), y: inner.minY, width: rightThirdW, height: inner.height)
        case .leftTwoThirds: CGRect(x: inner.minX, y: inner.minY, width: 2 * thirdW + g, height: inner.height)
        case .rightTwoThirds: CGRect(x: inner.minX + thirdW + g, y: inner.minY, width: inner.width - thirdW - g, height: inner.height)
        case .topLeft: CGRect(x: inner.minX, y: inner.minY, width: halfW, height: halfH)
        case .topRight: CGRect(x: inner.minX + halfW + g, y: inner.minY, width: rightW, height: halfH)
        case .bottomLeft: CGRect(x: inner.minX, y: inner.minY + halfH + g, width: halfW, height: bottomH)
        case .bottomRight: CGRect(x: inner.minX + halfW + g, y: inner.minY + halfH + g, width: rightW, height: bottomH)
        case .maximize: inner
        case .center: centeredRect(in: inner, widthRatio: 0.72, heightRatio: 0.80)
        case .almostMax: centeredRect(in: inner, widthRatio: 0.90, heightRatio: 0.90)
        case .nextDisplay, .prevDisplay, .restore: currentFrame
        }
        return (rect, safeIdx)
    }

    private static func centeredRect(in inner: CGRect, widthRatio: CGFloat, heightRatio: CGFloat) -> CGRect {
        let w = max(minWindowWidth, (inner.width * widthRatio).rounded())
        let h = max(minWindowHeight, (inner.height * heightRatio).rounded())
        let x = (inner.minX + (inner.width - w) / 2).rounded()
        let y = (inner.minY + (inner.height - h) / 2).rounded()
        return CGRect(x: x, y: y, width: min(w, inner.width), height: min(h, inner.height))
    }

    private static func insetVisible(_ visible: CGRect, gap: CGFloat) -> CGRect {
        let g = min(gap, max(0, min(visible.width - minWindowWidth, visible.height - minWindowHeight) / 2))
        return CGRect(
            x: (visible.minX + g).rounded(),
            y: (visible.minY + g).rounded(),
            width: max(minWindowWidth, (visible.width - 2 * g).rounded()),
            height: max(minWindowHeight, (visible.height - 2 * g).rounded())
        )
    }

    private static func clampFrame(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let w = min(max(minWindowWidth, frame.width), bounds.width)
        let h = min(max(minWindowHeight, frame.height), bounds.height)
        let x = clamp(frame.minX, min: bounds.minX, max: max(bounds.minX, bounds.maxX - w))
        let y = clamp(frame.minY, min: bounds.minY, max: max(bounds.minY, bounds.maxY - h))
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }

    private static func clampGap(_ gap: CGFloat) -> CGFloat {
        gap.isFinite ? min(max(0, gap.rounded()), maxGap) : 0
    }

    private static func clamp<T: Comparable>(_ v: T, min lo: T, max hi: T) -> T {
        Swift.min(Swift.max(v, lo), hi)
    }

    private static func squaredDistance(_ pt: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - pt.x, 0, pt.x - rect.maxX)
        let dy = max(rect.minY - pt.y, 0, pt.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
