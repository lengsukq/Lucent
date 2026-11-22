import CoreGraphics
import Foundation
import LucentFoundation

public struct SystemDisplayRect: Codable, Equatable, Hashable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let isMain: Bool
    public let index: Int
    /// Full display frame in Quartz global coordinates (origin top-left of primary display).
    public let frame: CGRect
    /// Usable work area excluding menu bar and Dock, in Quartz global coordinates.
    public let visibleFrame: CGRect

    public init(
        displayID: UInt32,
        name: String,
        isMain: Bool,
        index: Int,
        frame: CGRect,
        visibleFrame: CGRect
    ) {
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.index = index
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public struct ManagedWindowInfo: Codable, Equatable, Hashable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let appName: String
    public let title: String
    public let windowIndex: Int
    public let frame: CGRect
    public let displayID: UInt32
    public let displayIndex: Int
    public let isFocused: Bool
    public let isMinimized: Bool
    public let isResizable: Bool

    public init(
        pid: Int32,
        bundleID: String,
        appName: String,
        title: String,
        windowIndex: Int,
        frame: CGRect,
        displayID: UInt32,
        displayIndex: Int,
        isFocused: Bool,
        isMinimized: Bool,
        isResizable: Bool
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.windowIndex = windowIndex
        self.frame = frame
        self.displayID = displayID
        self.displayIndex = displayIndex
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.isResizable = isResizable
    }

    public var stableUndoKey: String {
        "\(pid):\(windowIndex)"
    }
}

public enum WindowSnapPreset: String, Codable, CaseIterable, Sendable, Hashable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center, almostMax
    case nextDisplay, prevDisplay
    case restore

    public var localizedTitle: String {
        switch self {
        case .leftHalf: L10n.pick("左半屏", "Left Half")
        case .rightHalf: L10n.pick("右半屏", "Right Half")
        case .topHalf: L10n.pick("上半屏", "Top Half")
        case .bottomHalf: L10n.pick("下半屏", "Bottom Half")
        case .leftThird: L10n.pick("左三分之一", "Left Third")
        case .centerThird: L10n.pick("中三分之一", "Center Third")
        case .rightThird: L10n.pick("右三分之一", "Right Third")
        case .leftTwoThirds: L10n.pick("左三分之二", "Left Two Thirds")
        case .rightTwoThirds: L10n.pick("右三分之二", "Right Two Thirds")
        case .topLeft: L10n.pick("左上四分屏", "Top Left")
        case .topRight: L10n.pick("右上四分屏", "Top Right")
        case .bottomLeft: L10n.pick("左下四分屏", "Bottom Left")
        case .bottomRight: L10n.pick("右下四分屏", "Bottom Right")
        case .maximize: L10n.pick("最大化铺满", "Maximize")
        case .center: L10n.pick("居中窗口", "Center")
        case .almostMax: L10n.pick("几乎满屏", "Almost Maximize")
        case .nextDisplay: L10n.pick("移到下一屏", "Next Display")
        case .prevDisplay: L10n.pick("移到上一屏", "Previous Display")
        case .restore: L10n.pick("撤销上次分屏", "Restore Window")
        }
    }

    public var symbolName: String {
        switch self {
        case .leftHalf, .leftThird, .leftTwoThirds: "rectangle.lefthalf.filled"
        case .rightHalf, .rightThird, .rightTwoThirds: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .centerThird, .center: "rectangle.center.inset.filled"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: "rectangle.split.2x2"
        case .maximize, .almostMax: "arrow.up.left.and.arrow.down.right"
        case .nextDisplay, .prevDisplay: "display.2"
        case .restore: "arrow.uturn.backward.circle.fill"
        }
    }
}

public struct NormalizedWindowRect: Codable, Equatable, Hashable, Sendable {
    public let rx: Double
    public let ry: Double
    public let rw: Double
    public let rh: Double

    public init(rx: Double, ry: Double, rw: Double, rh: Double) {
        self.rx = rx
        self.ry = ry
        self.rw = rw
        self.rh = rh
    }
}

public struct WindowWorkspaceSlot: Codable, Equatable, Hashable, Sendable {
    public let bundleID: String
    public let appName: String
    public let windowTitle: String?
    public let windowIndex: Int
    public let displayIndex: Int
    public let displayID: UInt32?
    public let rx: Double
    public let ry: Double
    public let rw: Double
    public let rh: Double

    public init(
        bundleID: String,
        appName: String,
        windowTitle: String? = nil,
        windowIndex: Int = 0,
        displayIndex: Int = 0,
        displayID: UInt32? = nil,
        rx: Double,
        ry: Double,
        rw: Double,
        rh: Double
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.windowIndex = max(0, windowIndex)
        self.displayIndex = max(0, displayIndex)
        self.displayID = displayID
        self.rx = rx
        self.ry = ry
        self.rw = rw
        self.rh = rh
    }
}

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
