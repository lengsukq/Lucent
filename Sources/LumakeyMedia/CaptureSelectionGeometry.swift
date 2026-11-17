import CoreGraphics
import Foundation

public struct DetectedScreenWindow: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let ownerName: String
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, ownerName: String, title: String, frame: CGRect) {
        self.id = id
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
    }

    public var displayLabel: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if ownerName.isEmpty { return trimmedTitle }
        if trimmedTitle.isEmpty || trimmedTitle == ownerName { return ownerName }
        let short = trimmedTitle.count > 28 ? String(trimmedTitle.prefix(28)) + "…" : trimmedTitle
        return "\(ownerName) — \(short)"
    }
}

public struct SelectionCreationContext: Equatable, Sendable {
    public let startPoint: CGPoint
    public let previousSelection: CGRect?
    public let previousSelectedWindow: DetectedScreenWindow?
    public let pressHoveredWindow: DetectedScreenWindow?

    public init(
        startPoint: CGPoint,
        previousSelection: CGRect?,
        previousSelectedWindow: DetectedScreenWindow?,
        pressHoveredWindow: DetectedScreenWindow?
    ) {
        self.startPoint = startPoint
        self.previousSelection = previousSelection
        self.previousSelectedWindow = previousSelectedWindow
        self.pressHoveredWindow = pressHoveredWindow
    }
}

public enum CaptureCreationResolution: Equatable, Sendable {
    case snapToWindow(DetectedScreenWindow)
    case commitRegion(CGRect)
    case restorePrevious(selection: CGRect?, window: DetectedScreenWindow?)
}

public enum CaptureSelectionGeometry {
    public static let dragStartDistance: CGFloat = 3.0

    public static func shouldBeginDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragStartDistance
    }

    public static func rubberBandRect(from start: CGPoint, to current: CGPoint, clampedTo bounds: CGRect) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).intersection(bounds)
    }

    public static func topWindow(at point: CGPoint, in windows: [DetectedScreenWindow]) -> DetectedScreenWindow? {
        windows.first { $0.frame.contains(point) }
    }

    public static func resolveHover(
        at point: CGPoint,
        windows: [DetectedScreenWindow],
        lastTopWindowID: inout CGWindowID?,
        cycleIndex: inout Int
    ) -> (hovered: DetectedScreenWindow?, overlapCount: Int) {
        let hits = windows.filter { $0.frame.contains(point) }
        if hits.first?.id != lastTopWindowID {
            lastTopWindowID = hits.first?.id
            cycleIndex = 0
        }
        guard !hits.isEmpty else { return (nil, 0) }
        return (hits[cycleIndex % hits.count], hits.count)
    }

    public static func resolveCreationEnd(
        context: SelectionCreationContext,
        endPoint: CGPoint,
        currentSelection: CGRect?,
        currentHoveredWindow: DetectedScreenWindow?,
        windows: [DetectedScreenWindow],
        minimumSelectionSize: CGFloat
    ) -> CaptureCreationResolution {
        let dist = hypot(endPoint.x - context.startPoint.x, endPoint.y - context.startPoint.y)
        let hitWindow = context.pressHoveredWindow
            ?? currentHoveredWindow
            ?? topWindow(at: endPoint, in: windows)
            ?? topWindow(at: context.startPoint, in: windows)

        if dist < dragStartDistance {
            if let win = hitWindow {
                return .snapToWindow(win)
            }
            return .restorePrevious(
                selection: context.previousSelection,
                window: context.previousSelectedWindow
            )
        }

        if let sel = currentSelection?.standardized,
           !sel.isNull,
           sel.width >= minimumSelectionSize,
           sel.height >= minimumSelectionSize {
            return .commitRegion(sel)
        }

        if let win = hitWindow {
            return .snapToWindow(win)
        }
        return .restorePrevious(
            selection: context.previousSelection,
            window: context.previousSelectedWindow
        )
    }

    public static func resolvedWindowCaptureSize(
        filterContentRect: CGRect,
        fallbackWindowFrame: CGRect,
        minimumPoints: CGFloat = 4.0
    ) -> CGSize? {
        let stdFilter = filterContentRect.standardized
        if !stdFilter.isNull, stdFilter.width >= minimumPoints, stdFilter.height >= minimumPoints {
            return stdFilter.size
        }
        let stdFallback = fallbackWindowFrame.standardized
        if !stdFallback.isNull, stdFallback.width >= minimumPoints, stdFallback.height >= minimumPoints {
            return stdFallback.size
        }
        return nil
    }
}
