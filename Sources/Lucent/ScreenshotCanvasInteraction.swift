import AppKit
import LucentCore
import LucentMedia
import SwiftUI

extension ScreenshotCanvasView {
    func handleDragChanged(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        let flags = NSEvent.modifierFlags
        let shiftHeld = flags.contains(.shift)
        if session.activeDragMode == nil {
            session.commitTextAnnotation()
            session.updateHover(at: canvasStart)
            session.activeDragMode = resolveDragMode(start: canvasStart, modifiers: flags)
        }
        session.updateHover(at: canvasLoc)
        guard let mode = session.activeDragMode else { return }

        switch mode {
        case .noop:
            break
        case .creating(let ctx):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: ctx.startPoint, to: canvasLoc) else { return }
            session.isDraggingSelection = true; session.selectedWindow = nil
            let target = shiftHeld
                ? AnnotationGeometry.snapEndpoint(from: ctx.startPoint, to: canvasLoc, tool: .rect, shiftHeld: true)
                : canvasLoc
            session.selectionRect = CaptureSelectionGeometry.rubberBandRect(from: ctx.startPoint, to: target, clampedTo: session.screenBounds)
        case .resizing(let handle, let initial, let startPt):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: startPt, to: canvasLoc) else { return }
            session.isDraggingSelection = true; session.selectedWindow = nil
            session.selectionRect = resizedSelectionRect(initial, handle: handle, to: canvasLoc, keepSquare: shiftHeld)
                .intersection(session.screenBounds)
        case .movingSelection(let initial, let start, let savedAnnotations):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: start, to: canvasLoc) else { return }
            session.isDraggingSelection = true
            var dx = canvasLoc.x - start.x, dy = canvasLoc.y - start.y
            if shiftHeld { if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 } }
            session.moveSelection(from: initial, initialAnnotations: savedAnnotations, dx: dx, dy: dy)
        case .movingAnnotation(let id, let initialItem, let start):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: start, to: canvasLoc),
                  let idx = session.annotations.firstIndex(where: { $0.id == id }) else { return }
            var dx = canvasLoc.x - start.x, dy = canvasLoc.y - start.y
            if shiftHeld { if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 } }
            session.annotations[idx] = AnnotationGeometry.translated(initialItem, dx: dx, dy: dy)
        case .transformingAnnotation(let id, let handle, let initialItem):
            guard let idx = session.annotations.firstIndex(where: { $0.id == id }) else { return }
            session.annotations[idx] = AnnotationGeometry.transformed(initialItem, handle: handle, to: canvasLoc, shiftHeld: shiftHeld)
        case .annotating(let tool, _):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: canvasStart, to: canvasLoc) else { return }
            session.selectedAnnotationID = nil
            updateDraftAnnotation(tool: tool, start: canvasStart, current: canvasLoc, shiftHeld: shiftHeld)
        }
    }

    func handleDragEnded(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        let mode = session.activeDragMode
        session.activeDragMode = nil; session.isDraggingSelection = false

        if case .creating(let ctx) = mode {
            finishSelectionCreation(context: ctx, endPoint: canvasLoc)
            return
        }

        let didDrag = CaptureSelectionGeometry.shouldBeginDrag(from: canvasStart, to: canvasLoc)
        if !didDrag {
            session.draftAnnotation = nil
            if case .annotating(_, let candidateID) = mode {
                handleTapInsideSelection(at: canvasLoc, hitCandidateID: candidateID)
            } else if case .movingAnnotation(let id, _, _) = mode {
                handleTapInsideSelection(at: canvasLoc, hitCandidateID: id)
            } else if case .transformingAnnotation(let id, let handle, let initialItem) = mode {
                handleZeroDragHandleTap(id: id, handle: handle, initialItem: initialItem, at: canvasLoc)
            } else {
                handleTapInsideSelection(at: canvasLoc, hitCandidateID: nil)
            }
            return
        }

        switch mode {
        case .resizing, .movingSelection:
            if session.mode == .interactiveAnnotate && !session.isPinEditSession { onAction(.syncClipboard) }
        case .movingAnnotation(let id, let initialItem, _), .transformingAnnotation(let id, _, let initialItem):
            if let cur = session.annotations.first(where: { $0.id == id }), cur != initialItem {
                var before = session.annotations
                if let idx = before.firstIndex(where: { $0.id == id }) { before[idx] = initialItem }
                session.recordUndoSnapshot(before)
            }
        case .annotating:
            if var draft = session.draftAnnotation {
                if draft.tool == .counter {
                    draft.counterIndex = session.nextCounterIndex
                    session.nextCounterIndex += 1
                }
                if !isDegenerateDraft(draft) { session.appendAnnotation(draft) }
                session.draftAnnotation = nil
            }
        default:
            break
        }
    }

    private func finishSelectionCreation(context ctx: SelectionCreationContext, endPoint: CGPoint) {
        let dist = hypot(endPoint.x - ctx.startPoint.x, endPoint.y - ctx.startPoint.y)
        if dist < CaptureSelectionGeometry.dragStartDistance,
           !session.axControls.isEmpty,
           session.axDepthIndex < session.axControls.count {
            let subRect = session.topology.canvasRect(fromQuartzGlobal: session.axControls[session.axDepthIndex].quartzFrame)
            if !subRect.isNull, subRect.width >= 8, subRect.height >= 8 {
                session.selectionRect = subRect
                session.selectedWindow = nil
                session.axControls = []
                onAction(session.mode == .quickOCR ? .ocr : .syncClipboard)
                return
            }
        }
        let resolution = CaptureSelectionGeometry.resolveCreationEnd(
            context: ctx, endPoint: endPoint, currentSelection: session.selectionRect,
            currentHoveredWindow: session.hoveredWindow, windows: session.windows, minimumSelectionSize: 6
        )
        switch resolution {
        case .snapToWindow(let win):
            session.selectWindow(win, excludeShadow: session.excludeWindowShadow || NSEvent.modifierFlags.contains(.option))
            onAction(session.mode == .quickOCR ? .ocr : .syncClipboard)
        case .commitRegion(let sel):
            session.selectionRect = sel; session.selectedWindow = nil; session.axControls = []
            if session.mode == .quickOCR, sel.width >= 8, sel.height >= 8 { onAction(.ocr); return }
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        case .restorePrevious(let prevSel, let prevWin):
            session.selectionRect = prevSel; session.selectedWindow = prevWin
            session.updateHover(at: endPoint)
        }
    }

    private func updateDraftAnnotation(tool: AnnotationToolKind, start: CGPoint, current: CGPoint, shiftHeld: Bool) {
        let snapped = AnnotationGeometry.snapEndpoint(from: start, to: current, tool: tool, shiftHeld: shiftHeld)
        if tool == .pen || tool == .highlighter || tool == .mosaic {
            var pts = session.draftAnnotation?.points ?? [start]
            AnnotationGeometry.appendSampledPoint(current, to: &pts)
            session.draftAnnotation = ScreenshotAnnotation(
                tool: tool, color: session.selectedColor, gradient: session.activeGradient,
                strokeSize: session.strokeSize, customScale: session.activeCustomScale,
                lineStyle: session.activeLineStyle, points: pts
            )
        } else if [.rect, .ellipse, .arrow, .line, .spotlight, .blur, .counter].contains(tool) {
            let previewIdx = session.nextCounterIndex
            session.draftAnnotation = ScreenshotAnnotation(
                tool: tool, color: session.selectedColor, gradient: session.activeGradient,
                strokeSize: session.strokeSize, customScale: session.activeCustomScale,
                lineStyle: session.activeLineStyle, isFilled: session.activeIsFilled,
                points: [start, snapped], counterIndex: previewIdx
            )
        }
    }

    private func isDegenerateDraft(_ item: ScreenshotAnnotation) -> Bool {
        if item.tool == .rect || item.tool == .ellipse || item.tool == .blur || item.tool == .spotlight {
            guard let b = AnnotationGeometry.boxRect(for: item) else { return true }
            return b.width < 3 || b.height < 3
        }
        return false
    }

    private func handleZeroDragHandleTap(id: UUID, handle: AnnotationHandle, initialItem: ScreenshotAnnotation, at pt: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        let isDouble = now - session.lastTapTimestamp < 0.34 && hypot(pt.x - session.lastTapPoint.x, pt.y - session.lastTapPoint.y) < 14
        session.lastTapTimestamp = now; session.lastTapPoint = pt
        if isDouble, (handle == .curveControl1 || handle == .curveControl2),
           let idx = session.annotations.firstIndex(where: { $0.id == id }), initialItem.points.count == 4 {
            session.recordUndoSnapshot()
            session.annotations[idx].points = [initialItem.points[0], initialItem.points[3]]
        }
    }

    private func handleTapInsideSelection(at point: CGPoint, hitCandidateID: UUID?) {
        guard let sel = session.selectionRect, sel.contains(point) else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let isDouble = now - session.lastTapTimestamp < 0.32 && hypot(point.x - session.lastTapPoint.x, point.y - session.lastTapPoint.y) < 12
        session.lastTapTimestamp = now; session.lastTapPoint = point

        if let hitID = hitCandidateID {
            session.selectedAnnotationID = hitID
            if isDouble { session.beginEditingAnnotation(hitID) }
            return
        }

        session.selectedAnnotationID = nil
        if session.activeTool == .counter {
            let idx = session.nextCounterIndex; session.nextCounterIndex += 1
            session.appendAnnotation(ScreenshotAnnotation(
                tool: .counter, color: session.selectedColor, gradient: session.activeGradient,
                strokeSize: session.strokeSize, customScale: session.activeCustomScale,
                points: [point], counterIndex: idx
            ))
            return
        }
        if session.activeTool == .text {
            session.pendingTextPoint = point
            return
        }
        if session.activeTool == .move && isDouble {
            if session.mode == .quickOCR { onAction(.ocr); return }
            if session.isPinEditSession { onAction(.copy); return }
            let dblAction = GeneralPreferences.load().captureDoubleClickAction
            onAction(dblAction == .pinToScreen ? .pin : .copy)
        }
    }

    private func resolveDragMode(start: CGPoint, modifiers: NSEvent.ModifierFlags) -> ScreenshotDragMode {
        let makeCreating = {
            ScreenshotDragMode.creating(SelectionCreationContext(
                startPoint: start, previousSelection: session.selectionRect,
                previousSelectedWindow: session.selectedWindow,
                pressHoveredWindow: session.hoveredWindow ?? session.topWindow(at: start)
            ))
        }
        guard let sel = session.selectionRect?.standardized else {
            return session.isPinEditSession ? .noop : makeCreating()
        }
        if !session.isPinEditSession {
            for h in SelectionHandle.allCases where hypot(start.x - h.point(in: sel).x, start.y - h.point(in: sel).y) <= 11 {
                return .resizing(h, sel, start)
            }
        }
        guard sel.contains(start) else {
            return (!session.isPinEditSession && session.annotations.isEmpty) ? makeCreating() : .noop
        }

        let forceMoveObj = modifiers.contains(.command) || modifiers.contains(.control)
        let hit = AnnotationGeometry.hitTest(
            at: start, annotations: session.annotations, selectedID: session.selectedAnnotationID,
            activeTool: session.activeTool, forceMoveModifier: forceMoveObj
        )
        switch hit {
        case .handle(let id, let h):
            if let item = session.annotations.first(where: { $0.id == id }) {
                session.selectedAnnotationID = id
                return .transformingAnnotation(id, h, item)
            }
        case .borderMove(let id):
            if let item = session.annotations.first(where: { $0.id == id }) {
                session.selectedAnnotationID = id
                return .movingAnnotation(id, item, start)
            }
        case .interiorSelectOrDraw(let id):
            return .annotating(session.activeTool, selectCandidateID: id)
        case .none:
            break
        }

        if modifiers.contains(.option) && session.activeTool != .move && !session.isPinEditSession {
            return .movingSelection(sel, start, session.annotations)
        }
        if session.activeTool == .move {
            session.selectedAnnotationID = nil
            return session.isPinEditSession ? .noop : .movingSelection(sel, start, session.annotations)
        }
        return .annotating(session.activeTool, selectCandidateID: nil)
    }

    private func resizedSelectionRect(_ r: CGRect, handle: SelectionHandle, to pt: CGPoint, keepSquare: Bool) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .topLeft: minX = min(pt.x, maxX - 10); minY = min(pt.y, maxY - 10)
        case .top: minY = min(pt.y, maxY - 10)
        case .topRight: maxX = max(pt.x, minX + 10); minY = min(pt.y, maxY - 10)
        case .right: maxX = max(pt.x, minX + 10)
        case .bottomRight: maxX = max(pt.x, minX + 10); maxY = max(pt.y, minY + 10)
        case .bottom: maxY = max(pt.y, minY + 10)
        case .bottomLeft: minX = min(pt.x, maxX - 10); maxY = max(pt.y, minY + 10)
        case .left: minX = min(pt.x, maxX - 10)
        }
        var out = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if keepSquare {
            let side = max(out.width, out.height)
            out.size = CGSize(width: side, height: side)
        }
        return out
    }
}
