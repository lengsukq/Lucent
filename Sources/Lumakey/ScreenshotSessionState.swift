import AppKit
import CoreGraphics
import LumakeyCore
import SwiftUI

enum ScreenshotMode: Sendable {
    case interactiveAnnotate
    case quickOCR
}

enum ScreenshotResult: Sendable {
    case copied(URL)
    case saved(URL)
    case pinned(URL, NSRect)
    case ocrRequested(URL)
    case cutoutRequested(URL)
    case cancelled
}

enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum ScreenshotDragMode {
    case creating(SelectionCreationContext)
    case resizing(SelectionHandle, CGRect, CGPoint)
    case movingSelection(CGRect, CGPoint, [ScreenshotAnnotation])
    case annotating(AnnotationToolKind)
    case noop
}

@MainActor
final class ScreenshotSessionState: ObservableObject {
    let topology: ScreenTopologySnapshot
    let mode: ScreenshotMode
    let previousSelectionRect: CGRect?

    var screenBounds: CGRect { topology.canvasBounds }
    var windows: [DetectedScreenWindow] { topology.windows }

    @Published var activeDisplayID: CGDirectDisplayID
    @Published var selectionRect: CGRect?
    @Published var hoveredWindow: DetectedScreenWindow?
    @Published var overlappingWindowCount: Int = 0
    @Published var windowCycleIndex: Int = 0
    @Published var selectedWindow: DetectedScreenWindow?
    @Published var excludeWindowShadow: Bool = false
    @Published var cursorPoint: CGPoint
    @Published var cursorHex: String = "#000000"
    @Published var cursorRGB: String = "rgb(0, 0, 0)"
    @Published var isDraggingSelection: Bool = false
    @Published var activeTool: AnnotationToolKind = .move
    @Published var selectedColor: AnnotationRGBColor = AnnotationRGBColor.presets[0]
    @Published var strokeSize: AnnotationStrokeSize = .medium
    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var redoStack: [ScreenshotAnnotation] = []
    @Published var draftAnnotation: ScreenshotAnnotation?
    @Published var nextCounterIndex: Int = 1
    @Published var pendingTextPoint: CGPoint?
    @Published var pendingTextValue: String = ""
    @Published var bannerMessage: String?
    @Published var hasAutoCopied: Bool = false

    var hoveredWindowRect: CGRect? { hoveredWindow?.frame }

    var activeDragMode: ScreenshotDragMode?
    var lastTapTimestamp: TimeInterval = 0
    var lastTapPoint: CGPoint = .zero
    private var lastTopHitWindowID: CGWindowID?

    init(
        topology: ScreenTopologySnapshot,
        initialCursorCanvasPoint: CGPoint,
        mode: ScreenshotMode,
        previousSelectionRect: CGRect? = nil
    ) {
        self.topology = topology
        self.mode = mode
        self.previousSelectionRect = previousSelectionRect
        let clampedPt = CGPoint(
            x: min(max(0, initialCursorCanvasPoint.x), topology.canvasBounds.width),
            y: min(max(0, initialCursorCanvasPoint.y), topology.canvasBounds.height)
        )
        self.cursorPoint = clampedPt
        self.activeDisplayID = topology.displaySlice(containingCanvasPoint: clampedPt)?.displayID
            ?? topology.displays.first?.displayID ?? CGMainDisplayID()
        let sampled = ScreenshotCompositor.sampleColorFromSlices(topology.colorSampleSlices, at: clampedPt)
        self.cursorHex = sampled.hex
        self.cursorRGB = sampled.rgb
        updateHover(at: clampedPt)
    }

    func effectiveScale(for rect: CGRect) -> CGFloat {
        topology.effectiveScale(forSelection: rect)
    }

    func pixelDimensions(for rect: CGRect) -> (Int, Int) {
        let std = rect.standardized
        let scale = effectiveScale(for: std)
        return (max(1, Int(round(std.width * scale))), max(1, Int(round(std.height * scale))))
    }

    func updateHover(at point: CGPoint) {
        let clamped = CGPoint(
            x: min(max(0, point.x), screenBounds.width),
            y: min(max(0, point.y), screenBounds.height)
        )
        cursorPoint = clamped
        if let slice = topology.displaySlice(containingCanvasPoint: clamped), slice.displayID != activeDisplayID {
            activeDisplayID = slice.displayID
        }
        let sampled = ScreenshotCompositor.sampleColorFromSlices(topology.colorSampleSlices, at: clamped)
        cursorHex = sampled.hex
        cursorRGB = sampled.rgb
        guard selectionRect == nil else {
            hoveredWindow = nil
            overlappingWindowCount = 0
            return
        }
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
        let picked = hits[windowCycleIndex]
        hoveredWindow = picked
        bannerMessage = L10n.pick(
            "窗口层级 \(windowCycleIndex + 1)/\(hits.count)：\(picked.displayLabel)",
            "Window \(windowCycleIndex + 1)/\(hits.count): \(picked.displayLabel)"
        )
        return true
    }

    func selectWindow(_ window: DetectedScreenWindow, excludeShadow: Bool) {
        selectedWindow = window
        excludeWindowShadow = excludeShadow
        selectionRect = window.frame
        hoveredWindow = nil
        overlappingWindowCount = 0
    }

    func appendAnnotation(_ item: ScreenshotAnnotation) {
        redoStack.removeAll()
        annotations.append(item)
    }

    func commitTextAnnotation() {
        guard let pt = pendingTextPoint else { return }
        let trimmed = pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appendAnnotation(ScreenshotAnnotation(
                tool: .text, color: selectedColor, strokeSize: strokeSize, points: [pt], text: trimmed
            ))
        }
        pendingTextPoint = nil
        pendingTextValue = ""
    }

    func undoAnnotation() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        redoStack.append(removed)
        if removed.tool == .counter { nextCounterIndex = max(1, removed.counterIndex) }
    }

    func redoAnnotation() {
        guard let restored = redoStack.popLast() else { return }
        annotations.append(restored)
        if restored.tool == .counter { nextCounterIndex = max(nextCounterIndex, restored.counterIndex + 1) }
    }

    func moveSelection(from initial: CGRect, initialAnnotations: [ScreenshotAnnotation], dx: CGFloat, dy: CGFloat) {
        selectedWindow = nil
        let clampedX = min(max(0, initial.minX + dx), screenBounds.width - initial.width)
        let clampedY = min(max(0, initial.minY + dy), screenBounds.height - initial.height)
        let appliedDX = clampedX - initial.minX
        let appliedDY = clampedY - initial.minY
        selectionRect = CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: initial.size)
        if !initialAnnotations.isEmpty {
            annotations = initialAnnotations.map { item in
                var moved = item
                moved.points = item.points.map { CGPoint(x: $0.x + appliedDX, y: $0.y + appliedDY) }
                return moved
            }
        }
    }

    @discardableResult
    func nudgeSelection(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let rect = selectionRect else { return false }
        moveSelection(from: rect, initialAnnotations: annotations, dx: dx, dy: dy)
        return true
    }

    func clearAnnotations() {
        annotations.removeAll(); redoStack.removeAll()
        draftAnnotation = nil; pendingTextPoint = nil; pendingTextValue = ""
        nextCounterIndex = 1
    }

    func screenRectForSelection() -> NSRect? {
        guard let rect = selectionRect?.standardized, rect.width >= 4, rect.height >= 4 else { return nil }
        return topology.clampedPinRect(fromCanvas: rect)
    }
}
