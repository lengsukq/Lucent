import CoreGraphics
import Foundation

public enum FileShelfDockEdge: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case left
    case right
}

public struct FileShelfWindowSettings: Codable, Sendable, Equatable {
    public var dockEdge: FileShelfDockEdge
    public var edgeAutoHide: Bool
    public var pinnedExpanded: Bool
    public var collapsedCapsule: Bool
    public var removeAfterDragOut: Bool
    public var anchorMidY: Double?

    public init(
        dockEdge: FileShelfDockEdge = .right,
        edgeAutoHide: Bool = true,
        pinnedExpanded: Bool = false,
        collapsedCapsule: Bool = false,
        removeAfterDragOut: Bool = false,
        anchorMidY: Double? = nil
    ) {
        self.dockEdge = dockEdge
        self.edgeAutoHide = edgeAutoHide
        self.pinnedExpanded = pinnedExpanded
        self.collapsedCapsule = collapsedCapsule
        self.removeAfterDragOut = removeAfterDragOut
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
    public static let tuckedTabSize = CGSize(width: 24, height: 108)
    public static let screenInset: CGFloat = 10
    public static let snapThreshold: CGFloat = 28

    public static func detectSnapEdge(
        frame: CGRect,
        visibleFrame: CGRect,
        threshold: CGFloat = snapThreshold
    ) -> FileShelfDockEdge {
        let distLeft = abs(frame.minX - visibleFrame.minX)
        let distRight = abs(visibleFrame.maxX - frame.maxX)
        if distLeft <= threshold && distLeft <= distRight {
            return .left
        }
        if distRight <= threshold {
            return .right
        }
        return .none
    }

    public static func resolveMode(
        settings: FileShelfWindowSettings,
        isHovered: Bool,
        isDraggingIntoShelf: Bool,
        isModalOrInputActive: Bool
    ) -> FileShelfPresentationMode {
        if settings.dockEdge != .none {
            if settings.edgeAutoHide && !settings.pinnedExpanded && !isHovered && !isDraggingIntoShelf && !isModalOrInputActive {
                return .edgeTucked(settings.dockEdge)
            }
            return .expanded
        }
        if settings.collapsedCapsule && !isDraggingIntoShelf {
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
        anchorMidY: CGFloat?,
        visibleFrame: CGRect
    ) -> CGRect {
        let preferredMidY = anchorMidY ?? currentFrame.midY
        let clampedY = clampY(midY: preferredMidY, height: size.height, visibleFrame: visibleFrame)
        switch mode {
        case .edgeTucked(let edge):
            let x = edge == .left ? visibleFrame.minX : (visibleFrame.maxX - size.width)
            return CGRect(x: x, y: clampedY, width: size.width, height: size.height)
        case .expanded:
            switch dockEdge {
            case .left:
                return CGRect(x: visibleFrame.minX + screenInset, y: clampedY, width: size.width, height: size.height)
            case .right:
                return CGRect(x: visibleFrame.maxX - size.width - screenInset, y: clampedY, width: size.width, height: size.height)
            case .none:
                let clampedX = clampX(originX: currentFrame.maxX - size.width, width: size.width, visibleFrame: visibleFrame)
                let topAnchoredY = clampOriginY(originY: currentFrame.maxY - size.height, height: size.height, visibleFrame: visibleFrame)
                return CGRect(x: clampedX, y: topAnchoredY, width: size.width, height: size.height)
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
