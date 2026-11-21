import CoreGraphics
import Foundation

public enum FileShelfDockEdge: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case left
    case right
    case top
}

public struct FileShelfWindowSettings: Codable, Sendable, Equatable {
    public var dockEdge: FileShelfDockEdge
    public var edgeAutoHide: Bool
    public var pinnedExpanded: Bool
    public var collapsedCapsule: Bool
    public var removeAfterDragOut: Bool
    public var anchorMidX: Double?
    public var anchorMidY: Double?

    public init(
        dockEdge: FileShelfDockEdge = .right,
        edgeAutoHide: Bool = true,
        pinnedExpanded: Bool = false,
        collapsedCapsule: Bool = false,
        removeAfterDragOut: Bool = false,
        anchorMidX: Double? = nil,
        anchorMidY: Double? = nil
    ) {
        self.dockEdge = dockEdge
        self.edgeAutoHide = edgeAutoHide
        self.pinnedExpanded = pinnedExpanded
        self.collapsedCapsule = collapsedCapsule
        self.removeAfterDragOut = removeAfterDragOut
        self.anchorMidX = anchorMidX
        self.anchorMidY = anchorMidY
    }
}

public enum FileShelfPresentationMode: Equatable, Sendable {
    case edgeTucked(FileShelfDockEdge)
    case capsule
    case expanded
}

public enum FileShelfEdgeGeometry {
    public static let expandedSize = CGSize(width: 320, height: 420)
    public static let emptySize = CGSize(width: 320, height: 260)
    public static let capsuleSize = CGSize(width: 96, height: 46)
    public static let tuckedTabSize = CGSize(width: 32, height: 116)
    public static let tuckedTopTabSize = CGSize(width: 132, height: 32)
    public static let dockEdgeInset: CGFloat = 0
    public static let screenInset: CGFloat = 10
    public static let snapThreshold: CGFloat = 32

    public static func detectSnapEdge(
        frame: CGRect,
        visibleFrame: CGRect,
        threshold: CGFloat = snapThreshold
    ) -> FileShelfDockEdge {
        let distLeft = frame.minX - visibleFrame.minX
        let distRight = visibleFrame.maxX - frame.maxX
        let distTop = visibleFrame.maxY - frame.maxY
        let candidates: [(FileShelfDockEdge, CGFloat)] = [
            (.top, distTop),
            (.left, distLeft),
            (.right, distRight)
        ]
        guard let best = candidates.filter({ $0.1 <= threshold }).min(by: { $0.1 < $1.1 }) else {
            return .none
        }
        return best.0
    }

    public static func resolveMode(
        settings: FileShelfWindowSettings,
        isHovered: Bool,
        isDraggingIntoShelf: Bool,
        isModalOrInputActive: Bool,
        isManuallyRevealed: Bool = false
    ) -> FileShelfPresentationMode {
        if settings.dockEdge != .none {
            if settings.edgeAutoHide && !settings.pinnedExpanded && !isHovered
                && !isDraggingIntoShelf && !isModalOrInputActive && !isManuallyRevealed {
                return .edgeTucked(settings.dockEdge)
            }
            return .expanded
        }
        if settings.collapsedCapsule && !isDraggingIntoShelf && !isManuallyRevealed {
            return .capsule
        }
        return .expanded
    }

    public static func targetSize(
        for mode: FileShelfPresentationMode,
        isEmpty: Bool,
        visibleFrame: CGRect
    ) -> CGSize {
        switch mode {
        case .edgeTucked(.top):
            return tuckedTopTabSize
        case .edgeTucked:
            return tuckedTabSize
        case .capsule:
            return capsuleSize
        case .expanded:
            let base = isEmpty ? emptySize : expandedSize
            let maxH = max(200, visibleFrame.height - screenInset * 2)
            return CGSize(width: base.width, height: min(base.height, maxH))
        }
    }

    public static func frame(
        for mode: FileShelfPresentationMode,
        dockEdge: FileShelfDockEdge,
        size: CGSize,
        currentFrame: CGRect,
        anchorMidX: CGFloat? = nil,
        anchorMidY: CGFloat?,
        visibleFrame: CGRect
    ) -> CGRect {
        let preferredMidX = anchorMidX ?? currentFrame.midX
        let preferredMidY = anchorMidY ?? currentFrame.midY
        let clampedX = clampX(originX: preferredMidX - size.width / 2, width: size.width, visibleFrame: visibleFrame)
        let clampedY = clampY(midY: preferredMidY, height: size.height, visibleFrame: visibleFrame)
        switch mode {
        case .edgeTucked(let edge):
            switch edge {
            case .top:
                return CGRect(x: clampedX, y: visibleFrame.maxY - size.height - dockEdgeInset, width: size.width, height: size.height)
            case .left:
                return CGRect(x: visibleFrame.minX, y: clampedY, width: size.width, height: size.height)
            case .right, .none:
                return CGRect(x: visibleFrame.maxX - size.width, y: clampedY, width: size.width, height: size.height)
            }
        case .expanded:
            switch dockEdge {
            case .top:
                return CGRect(x: clampedX, y: visibleFrame.maxY - size.height - dockEdgeInset, width: size.width, height: size.height)
            case .left:
                return CGRect(x: visibleFrame.minX + dockEdgeInset, y: clampedY, width: size.width, height: size.height)
            case .right:
                return CGRect(x: visibleFrame.maxX - size.width - dockEdgeInset, y: clampedY, width: size.width, height: size.height)
            case .none:
                let wasCompactTab = currentFrame.width <= tuckedTabSize.width + 1 || currentFrame.height <= tuckedTopTabSize.height + 1
                let rawX = wasCompactTab ? (currentFrame.midX - size.width / 2) : (currentFrame.maxX - size.width)
                let rawY = wasCompactTab ? (currentFrame.midY - size.height / 2) : (currentFrame.maxY - size.height)
                let floatX = clampX(originX: rawX, width: size.width, visibleFrame: visibleFrame)
                let floatY = clampOriginY(originY: rawY, height: size.height, visibleFrame: visibleFrame)
                return CGRect(x: floatX, y: floatY, width: size.width, height: size.height)
            }
        case .capsule:
            let clampedX = clampX(originX: currentFrame.maxX - size.width, width: size.width, visibleFrame: visibleFrame)
            let topAnchoredY = clampOriginY(originY: currentFrame.maxY - size.height, height: size.height, visibleFrame: visibleFrame)
            return CGRect(x: clampedX, y: topAnchoredY, width: size.width, height: size.height)
        }
    }

    private static func clampX(originX: CGFloat, width: CGFloat, visibleFrame: CGRect) -> CGFloat {
        let minX = visibleFrame.minX + screenInset
        let maxX = max(minX, visibleFrame.maxX - width - screenInset)
        return min(max(originX, minX), maxX)
    }

    private static func clampOriginY(originY: CGFloat, height: CGFloat, visibleFrame: CGRect) -> CGFloat {
        let minY = visibleFrame.minY + screenInset
        let maxY = max(minY, visibleFrame.maxY - height - screenInset)
        return min(max(originY, minY), maxY)
    }

    private static func clampY(midY: CGFloat, height: CGFloat, visibleFrame: CGRect) -> CGFloat {
        clampOriginY(originY: midY - height / 2, height: height, visibleFrame: visibleFrame)
    }
}
