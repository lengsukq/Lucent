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

public enum FloatingOverlayHorizontalAlign: Equatable, Sendable {
    case leading
    case center
    case trailing
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

    /// Computes exact viewport-clamped center for Screenshot / GIF bottom floating toolbars
    /// using the real measured toolbar size so neither left nor right screen edges ever clip.
    public static func clampedFloatingToolbarCenter(
        selection localSelection: CGRect?,
        viewportSize: CGSize,
        toolbarSize: CGSize,
        horizontalAlign: FloatingOverlayHorizontalAlign,
        edgeMargin: CGFloat = 14.0,
        selectionGap: CGFloat = 10.0,
        fallbackTopY: CGFloat = 44.0
    ) -> CGPoint {
        let marginX = min(edgeMargin, max(4, viewportSize.width * 0.04))
        let marginY = min(edgeMargin, max(4, viewportSize.height * 0.04))
        let halfW = toolbarSize.width * 0.5
        let halfH = toolbarSize.height * 0.5

        let minCenterX = marginX + halfW
        let maxCenterX = viewportSize.width - marginX - halfW
        let minCenterY = marginY + halfH
        let maxCenterY = viewportSize.height - marginY - halfH

        let clampX: (CGFloat) -> CGFloat = { desired in
            guard minCenterX <= maxCenterX else { return viewportSize.width * 0.5 }
            return min(max(desired, minCenterX), maxCenterX)
        }
        let clampY: (CGFloat) -> CGFloat = { desired in
            guard minCenterY <= maxCenterY else { return viewportSize.height * 0.5 }
            return min(max(desired, minCenterY), maxCenterY)
        }

        guard let rawSel = localSelection?.standardized, !rawSel.isNull else {
            return CGPoint(x: clampX(viewportSize.width * 0.5), y: clampY(fallbackTopY))
        }

        let viewportBounds = CGRect(origin: .zero, size: viewportSize)
        let clipped = rawSel.intersection(viewportBounds)
        let visSel: CGRect
        if !clipped.isNull, clipped.width > 0, clipped.height > 0 {
            visSel = clipped
        } else {
            let cx0 = min(max(rawSel.minX, 0), viewportSize.width)
            let cy0 = min(max(rawSel.minY, 0), viewportSize.height)
            let cx1 = min(max(rawSel.maxX, cx0), viewportSize.width)
            let cy1 = min(max(rawSel.maxY, cy0), viewportSize.height)
            visSel = CGRect(x: cx0, y: cy0, width: cx1 - cx0, height: cy1 - cy0)
        }

        let desiredX: CGFloat
        switch horizontalAlign {
        case .leading: desiredX = visSel.minX + halfW
        case .center: desiredX = visSel.midX
        case .trailing: desiredX = visSel.maxX - halfW
        }

        let belowY = visSel.maxY + selectionGap + halfH
        let aboveY = visSel.minY - selectionGap - halfH
        let finalY: CGFloat
        if minCenterY <= maxCenterY && belowY <= maxCenterY {
            finalY = max(minCenterY, belowY)
        } else if minCenterY <= maxCenterY && aboveY >= minCenterY {
            finalY = min(maxCenterY, aboveY)
        } else {
            finalY = clampY(visSel.maxY - marginY - halfH)
        }

        return CGPoint(x: clampX(desiredX), y: finalY)
    }

    /// Computes exact viewport-clamped center for window / selection top info badges
    /// using the real measured badge size so long window titles never clip at left/right edges.
    public static func clampedSelectionBadgeCenter(
        selection localSelection: CGRect,
        viewportSize: CGSize,
        badgeSize: CGSize,
        edgeMargin: CGFloat = 12.0,
        verticalGap: CGFloat = 6.0
    ) -> CGPoint {
        let marginX = min(edgeMargin, max(4, viewportSize.width * 0.03))
        let marginY = min(edgeMargin, max(4, viewportSize.height * 0.03))
        let halfW = badgeSize.width * 0.5
        let halfH = badgeSize.height * 0.5

        let viewportBounds = CGRect(origin: .zero, size: viewportSize)
        let std = localSelection.standardized
        let clipped = std.intersection(viewportBounds)
        let visSel = (!clipped.isNull && clipped.width > 0) ? clipped : std

        let minCenterX = marginX + halfW
        let maxCenterX = viewportSize.width - marginX - halfW
        let x: CGFloat
        if minCenterX <= maxCenterX {
            x = min(max(visSel.minX + halfW, minCenterX), maxCenterX)
        } else {
            x = viewportSize.width * 0.5
        }

        let minCenterY = marginY + halfH
        let maxCenterY = max(minCenterY, viewportSize.height - marginY - halfH)
        let aboveY = visSel.minY - verticalGap - halfH
        let insideTopY = visSel.minY + verticalGap + halfH
        let rawY = aboveY >= minCenterY ? aboveY : insideTopY
        let y = min(max(rawY, minCenterY), maxCenterY)

        return CGPoint(x: x, y: y)
    }
}
