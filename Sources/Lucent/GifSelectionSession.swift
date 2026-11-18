import AppKit
import CoreGraphics
import LucentCore
import SwiftUI

enum GifSelectionDragMode {
    case creating(SelectionCreationContext)
    case resizing(SelectionHandle, CGRect, CGPoint)
    case moving(CGRect, CGPoint)
}

@MainActor
final class GifSelectionSession: ObservableObject {
    let topology: ScreenTopologySnapshot
    var screenBounds: CGRect { topology.canvasBounds }
    var windows: [DetectedScreenWindow] { topology.windows }

    @Published var activeDisplayID: CGDirectDisplayID
    @Published var cursorPoint: CGPoint
    @Published var selectionRect: CGRect?
    @Published var hoveredWindow: DetectedScreenWindow?
    @Published var overlappingWindowCount: Int = 0
    @Published var windowCycleIndex: Int = 0
    @Published var selectedWindow: DetectedScreenWindow?
    @Published var isDragging: Bool = false
    @Published var options: GifRecordingOptions

    var activeDrag: GifSelectionDragMode?
    var lastClickTime: TimeInterval = 0
    var lastClickPoint: CGPoint = .zero
    private var lastTopHitWindowID: CGWindowID?

    init(topology: ScreenTopologySnapshot, initialCursorCanvasPoint: CGPoint, options: GifRecordingOptions) {
        self.topology = topology; self.options = options
        let clamped = CGPoint(
            x: min(max(0, initialCursorCanvasPoint.x), topology.canvasBounds.width),
            y: min(max(0, initialCursorCanvasPoint.y), topology.canvasBounds.height)
        )
        self.cursorPoint = clamped
        self.activeDisplayID = topology.displaySlice(containingCanvasPoint: clamped)?.displayID
            ?? topology.displays.first?.displayID ?? CGMainDisplayID()
        updateHover(at: clamped)
    }

    func updateHover(at point: CGPoint) {
        let clamped = CGPoint(x: min(max(0, point.x), screenBounds.width), y: min(max(0, point.y), screenBounds.height))
        cursorPoint = clamped
        if let slice = topology.displaySlice(containingCanvasPoint: clamped), slice.displayID != activeDisplayID {
            activeDisplayID = slice.displayID
        }
        guard selectionRect == nil else { hoveredWindow = nil; overlappingWindowCount = 0; return }
        let resolved = CaptureSelectionGeometry.resolveHover(
            at: clamped, windows: windows,
            lastTopWindowID: &lastTopHitWindowID, cycleIndex: &windowCycleIndex
        )
        hoveredWindow = resolved.hovered
        overlappingWindowCount = resolved.overlapCount
    }

    func topWindow(at point: CGPoint) -> DetectedScreenWindow? {
        CaptureSelectionGeometry.topWindow(at: point, in: windows)
    }

    @discardableResult
    func cycleHoveredWindow() -> Bool {
        guard selectionRect == nil else { return false }
        let hits = windows.filter { $0.frame.contains(cursorPoint) }
        guard hits.count >= 2 else { return false }
        windowCycleIndex = (windowCycleIndex + 1) % hits.count
        hoveredWindow = hits[windowCycleIndex]
        return true
    }

    func selectWindow(_ win: DetectedScreenWindow) {
        selectedWindow = win; selectionRect = win.frame; hoveredWindow = nil; overlappingWindowCount = 0
    }

    func outputDimensions(for rect: CGRect) -> (Int, Int) {
        let scale = topology.effectiveScale(forSelection: rect)
        let rawW = max(2, Int((rect.width * scale).rounded()))
        let rawH = max(2, Int((rect.height * scale).rounded()))
        return GifStreamEncoder.scaledDimensions(width: rawW, height: rawH, maxDimension: options.maxDimension)
    }

    func appKitScreenRect(for canvasRect: CGRect) -> NSRect { topology.appKitGlobalRect(fromCanvas: canvasRect) }
}
