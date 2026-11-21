import AppKit
import CoreGraphics
import LucentCore
import LucentMedia
import LucentSystem
import SwiftUI

enum ScreenshotMode: Sendable {
    case interactiveAnnotate
    case quickOCR
}

enum ScreenshotResult: Sendable {
    case copied(URL)
    case saved(URL)
    case pinned(URL, NSRect, cleanBaseURL: URL?, annotations: [ScreenshotAnnotation])
    case pinEdited(URL, annotations: [ScreenshotAnnotation])
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
    case movingAnnotation(UUID, ScreenshotAnnotation, CGPoint)
    case transformingAnnotation(UUID, AnnotationHandle, ScreenshotAnnotation)
    case annotating(AnnotationToolKind, selectCandidateID: UUID?)
    case noop
}

@MainActor
final class ScreenshotSessionState: ObservableObject {
    static let maxUndoSteps = 100

    var topology: ScreenTopologySnapshot
    let mode: ScreenshotMode
    let previousSelectionRect: CGRect?
    let isPinEditSession: Bool

    var screenBounds: CGRect { topology.canvasBounds }
    var windows: [DetectedScreenWindow] { topology.windows }

    @Published var activeDisplayID: CGDirectDisplayID
    @Published var selectionRect: CGRect?
    @Published var hoveredWindow: DetectedScreenWindow?
    @Published var overlappingWindowCount: Int = 0
    @Published var windowCycleIndex: Int = 0
    @Published var selectedWindow: DetectedScreenWindow?
    @Published var excludeWindowShadow: Bool = false
    @Published var axControls: [DetectedAXControlRegion] = []
    @Published var axDepthIndex: Int = 0
    @Published var cursorPoint: CGPoint
    @Published var cursorHex: String = "#000000"
    @Published var cursorRGB: String = "rgb(0, 0, 0)"
    @Published var isDraggingSelection: Bool = false

    @Published var activeTool: AnnotationToolKind = .move
    @Published var swatches: [AnnotationRGBColor]
    @Published var selectedColor: AnnotationRGBColor
    @Published var isUsingGradient: Bool = false
    @Published var activeGradientIndex: Int = 0
    @Published var strokeSize: AnnotationStrokeSize = .medium
    @Published var activeCustomScale: CGFloat = 1.0
    @Published var activeLineStyle: AnnotationLineStyle = .solid
    @Published var activeIsFilled: Bool = false

    @Published var annotations: [ScreenshotAnnotation] = []
    @Published var selectedAnnotationID: UUID?
    @Published var undoSnapshots: [[ScreenshotAnnotation]] = []
    @Published var redoSnapshots: [[ScreenshotAnnotation]] = []
    @Published var draftAnnotation: ScreenshotAnnotation?
    @Published var nextCounterIndex: Int = 1

    @Published var pendingTextPoint: CGPoint?
    @Published var pendingTextValue: String = ""
    @Published var editingAnnotationID: UUID?
    @Published var isEditingCounterNumber: Bool = false
    @Published var bannerMessage: String?
    @Published var hasAutoCopied: Bool = false

    var activeDragMode: ScreenshotDragMode?
    var lastTapTimestamp: TimeInterval = 0
    var lastTapPoint: CGPoint = .zero
    var lastCancelWarnTimestamp: TimeInterval = 0
    var lastTopHitWindowID: CGWindowID?
    private var axProbeTask: Task<Void, Never>?
    private var lastAXProbePoint: CGPoint = .init(x: -999, y: -999)

    var activeGradient: AnnotationGradientPreset? {
        guard isUsingGradient else { return nil }
        let presets = AnnotationGradientPreset.presets
        return presets[activeGradientIndex % presets.count]
    }

    var activeHoveredSnapRect: CGRect? {
        if !axControls.isEmpty, axDepthIndex < axControls.count {
            let rect = topology.canvasRect(fromQuartzGlobal: axControls[axDepthIndex].quartzFrame)
            if !rect.isNull, rect.width >= 12, rect.height >= 12 { return rect }
        }
        return hoveredWindow?.frame
    }

    var activeHoveredSnapLabel: String? {
        if !axControls.isEmpty, axDepthIndex < axControls.count {
            let ctrl = axControls[axDepthIndex]
            let prefix = hoveredWindow.map { "\($0.ownerName) ▸ " } ?? ""
            return "\(prefix)\(ctrl.roleLabel)"
        }
        return hoveredWindow?.displayLabel
    }

    init(
        topology: ScreenTopologySnapshot,
        initialCursorCanvasPoint: CGPoint,
        mode: ScreenshotMode,
        previousSelectionRect: CGRect? = nil,
        isPinEditSession: Bool = false,
        initialAnnotations: [ScreenshotAnnotation] = []
    ) {
        self.topology = topology
        self.mode = mode
        self.previousSelectionRect = previousSelectionRect
        self.isPinEditSession = isPinEditSession
        let prefs = GeneralPreferences.load()
        let loadedSwatches = prefs.customAnnotationSwatchHexes.compactMap { AnnotationRGBColor(hex: $0) }
        let finalSwatches = loadedSwatches.count == 5 ? loadedSwatches : Array(AnnotationRGBColor.presets.prefix(5))
        self.swatches = finalSwatches
        self.selectedColor = finalSwatches[0]
        self.annotations = initialAnnotations
        let maxCounter = initialAnnotations.filter { $0.tool == .counter }.map(\.counterIndex).max() ?? 0
        self.nextCounterIndex = max(1, maxCounter + 1)

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
        if !isPinEditSession { updateHover(at: clampedPt) }
    }

    func effectiveScale(for rect: CGRect) -> CGFloat { topology.effectiveScale(forSelection: rect) }

    func pixelDimensions(for rect: CGRect) -> (Int, Int) {
        let std = rect.standardized
        let scale = effectiveScale(for: std)
        return (max(1, Int(round(std.width * scale))), max(1, Int(round(std.height * scale))))
    }

    func recordUndoSnapshot(_ snapshot: [ScreenshotAnnotation]? = nil) {
        let state = snapshot ?? annotations
        if undoSnapshots.last == state { return }
        if undoSnapshots.count >= Self.maxUndoSteps { undoSnapshots.removeFirst() }
        undoSnapshots.append(state)
        redoSnapshots.removeAll()
    }

    func appendAnnotation(_ item: ScreenshotAnnotation) {
        recordUndoSnapshot()
        annotations.append(item)
        selectedAnnotationID = item.id
        if isUsingGradient {
            activeGradientIndex = (activeGradientIndex + 1) % AnnotationGradientPreset.presets.count
        }
    }

    func undoAnnotation() {
        guard let prev = undoSnapshots.popLast() else { return }
        redoSnapshots.append(annotations)
        annotations = prev
        if let selID = selectedAnnotationID, !annotations.contains(where: { $0.id == selID }) {
            selectedAnnotationID = nil
        }
        recomputeNextCounter()
    }

    func redoAnnotation() {
        guard let next = redoSnapshots.popLast() else { return }
        undoSnapshots.append(annotations)
        annotations = next
        recomputeNextCounter()
    }

    @discardableResult
    func deleteSelectedAnnotation() -> Bool {
        guard let selID = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == selID }) else { return false }
        recordUndoSnapshot()
        annotations.remove(at: idx)
        selectedAnnotationID = nil
        return true
    }

    func applyStyleMutation(_ mutate: (inout ScreenshotAnnotation) -> Void) {
        guard let selID = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == selID }) else { return }
        var updated = annotations[idx]
        mutate(&updated)
        guard updated != annotations[idx] else { return }
        recordUndoSnapshot()
        annotations[idx] = updated
    }

    func updateCustomSwatch(at index: Int, to color: AnnotationRGBColor) {
        guard swatches.indices.contains(index) else { return }
        swatches[index] = color
        isUsingGradient = false
        selectedColor = color
        applyStyleMutation { $0.color = color; $0.gradient = nil }
        var prefs = GeneralPreferences.load()
        prefs.customAnnotationSwatchHexes = swatches.map(\.hexString)
        prefs.save()
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        recordUndoSnapshot()
        annotations.removeAll()
        selectedAnnotationID = nil
        draftAnnotation = nil
        pendingTextPoint = nil; pendingTextValue = ""
        editingAnnotationID = nil; isEditingCounterNumber = false
        nextCounterIndex = 1
    }

    private func recomputeNextCounter() {
        let maxIdx = annotations.filter { $0.tool == .counter }.map(\.counterIndex).max() ?? 0
        nextCounterIndex = max(1, maxIdx + 1)
    }

    func screenRectForSelection() -> NSRect? {
        guard let rect = selectionRect?.standardized, rect.width >= 4, rect.height >= 4 else { return nil }
        return topology.clampedPinRect(fromCanvas: rect)
    }

    func cancelAXProbe() {
        axProbeTask?.cancel()
        axProbeTask = nil
    }

    func scheduleAXProbeIfNeeded(at point: CGPoint) {
        guard selectionRect == nil, GeneralPreferences.load().enableCaptureControlDrillDown else {
            axControls = []; axDepthIndex = 0; return
        }
        guard hypot(point.x - lastAXProbePoint.x, point.y - lastAXProbePoint.y) >= 4 else { return }
        lastAXProbePoint = point
        axProbeTask?.cancel()
        let quartzPt = topology.quartzGlobalPoint(fromCanvas: point)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        axProbeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled else { return }
            let chain = await AccessibilityElementMatcher.shared.probeHierarchy(atQuartzPoint: quartzPt, excludingPID: ownPID)
            guard !Task.isCancelled, let self, self.selectionRect == nil else { return }
            self.axControls = chain
            self.axDepthIndex = 0
        }
    }
}
