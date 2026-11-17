import AppKit
import LumakeyCore
import SwiftUI

struct ScreenshotCanvasView: View {
    @ObservedObject var session: ScreenshotSessionState
    let slice: ScreenDisplaySlice
    let onAction: (ScreenshotToolbarAction) -> Void

    private var origin: CGPoint { slice.canvasFrame.origin }
    private var viewSize: CGSize { slice.canvasFrame.size }

    private func toCanvas(_ local: CGPoint) -> CGPoint { CGPoint(x: local.x + origin.x, y: local.y + origin.y) }
    private func toLocal(_ canvasRect: CGRect) -> CGRect { canvasRect.offsetBy(dx: -origin.x, dy: -origin.y) }

    private var shouldHostToolbar: Bool {
        guard let sel = session.selectionRect?.standardized, sel.width >= 4, !session.isDraggingSelection else { return false }
        return session.topology.targetSlice(forSelection: sel, fallbackPoint: session.cursorPoint)?.displayID == slice.displayID
    }

    private var localToolbarPosition: CGPoint {
        guard let sel = session.selectionRect?.standardized else { return .zero }
        let localSel = toLocal(sel)
        let toolbarW: CGFloat = min(760, viewSize.width - 24)
        let toolbarH: CGFloat = session.activeTool == .move ? 48 : 82
        let minX = toolbarW / 2 + 12
        let maxX = max(minX, viewSize.width - toolbarW / 2 - 12)
        let x = min(max(localSel.maxX - toolbarW / 2, minX), maxX)
        let belowY = localSel.maxY + toolbarH / 2 + 10
        let aboveY = localSel.minY - toolbarH / 2 - 10
        let y: CGFloat
        if belowY + toolbarH / 2 <= viewSize.height - 10 { y = belowY }
        else if aboveY - toolbarH / 2 >= 10 { y = aboveY }
        else {
            let minY = toolbarH / 2 + 12
            let maxY = max(minY, viewSize.height - toolbarH / 2 - 12)
            y = min(max(localSel.maxY - toolbarH / 2 - 12, minY), maxY)
        }
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: slice.image, scale: slice.scale, orientation: .up)
                .resizable()
                .frame(width: viewSize.width, height: viewSize.height)
                .allowsHitTesting(false)

            dimmingOverlay

            if let sel = session.selectionRect?.standardized, sel.width >= 2, sel.height >= 2 {
                let localSel = toLocal(sel)
                let (pxW, pxH) = session.pixelDimensions(for: sel)
                mosaicOverlay(localSel: localSel)
                annotationCanvas(canvasSel: sel, localSel: localSel)

                ScreenshotSelectionChrome(
                    rect: localSel,
                    sliceSize: viewSize,
                    pixelSizeText: "\(pxW) × \(pxH) px",
                    windowTitle: session.selectedWindow?.displayLabel,
                    mode: session.mode
                )
            } else if let hover = session.hoveredWindow {
                ScreenshotWindowSnapOverlay(
                    rect: toLocal(hover.frame),
                    sliceSize: viewSize,
                    label: hover.displayLabel,
                    overlapCount: session.overlappingWindowCount
                )
            }

            Color.clear
                .frame(width: viewSize.width, height: viewSize.height)
                .contentShape(Rectangle())
                .onContinuousHover { if case .active(let pt) = $0 { session.updateHover(at: toCanvas(pt)) } }
                .gesture(DragGesture(minimumDistance: 0).onChanged(handleDragChanged).onEnded(handleDragEnded))

            if session.activeDisplayID == slice.displayID {
                if session.selectionRect == nil {
                    ScreenshotModeGuidePill(
                        mode: session.mode,
                        hasLastSelection: session.previousSelectionRect != nil,
                        multiDisplay: session.topology.displays.count > 1
                    ).position(x: viewSize.width / 2, y: 34)
                }
                if (session.selectionRect == nil || session.isDraggingSelection) && session.pendingTextPoint == nil {
                    ScreenshotLoupeView(
                        session: session,
                        localCursor: CGPoint(x: session.cursorPoint.x - origin.x, y: session.cursorPoint.y - origin.y),
                        sliceSize: viewSize
                    )
                }
                if let banner = session.bannerMessage {
                    Text(banner).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.75), in: Capsule())
                        .position(x: viewSize.width / 2, y: 68).allowsHitTesting(false)
                }
            }

            if let pt = session.pendingTextPoint, slice.canvasFrame.contains(pt) {
                ScreenshotInlineTextEditor(
                    session: session,
                    localPoint: CGPoint(x: pt.x - origin.x, y: pt.y - origin.y), sliceSize: viewSize
                )
            }

            if shouldHostToolbar {
                ScreenshotToolbarView(session: session, onAction: onAction).position(localToolbarPosition)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .clipped()
        .onChange(of: session.annotations.count) { _, _ in
            if session.mode == .interactiveAnnotate && shouldHostToolbar { onAction(.syncClipboard) }
        }
    }

    private var dimmingOverlay: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: viewSize))
            if let hole = (session.selectionRect ?? session.hoveredWindowRect)?.standardized {
                let localHole = toLocal(hole).intersection(CGRect(origin: .zero, size: viewSize))
                if !localHole.isNull && localHole.width >= 2 && localHole.height >= 2 { path.addRect(localHole) }
            }
        }
        .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
        .frame(width: viewSize.width, height: viewSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func mosaicOverlay(localSel: CGRect) -> some View {
        let clippedLocal = localSel.intersection(CGRect(origin: .zero, size: viewSize))
        if let pix = slice.pixelatedImage, !clippedLocal.isNull, clippedLocal.width > 0, clippedLocal.height > 0 {
            Image(decorative: pix, scale: CGFloat(pix.width) / max(viewSize.width, 1), orientation: .up)
                .interpolation(.none).resizable()
                .frame(width: viewSize.width, height: viewSize.height)
                .mask(
                    Canvas { ctx, _ in
                        ctx.clip(to: Path(clippedLocal))
                        ctx.translateBy(x: -origin.x, y: -origin.y)
                        let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
                        for item in items where item.tool == .mosaic {
                            ScreenshotAnnotationRenderer.renderMosaicMask(item, in: &ctx)
                        }
                    }
                    .frame(width: viewSize.width, height: viewSize.height)
                )
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func annotationCanvas(canvasSel: CGRect, localSel: CGRect) -> some View {
        let clippedLocal = localSel.intersection(CGRect(origin: .zero, size: viewSize))
        if !clippedLocal.isNull, clippedLocal.width > 0, clippedLocal.height > 0 {
            Canvas { ctx, _ in
                ctx.clip(to: Path(clippedLocal))
                ctx.translateBy(x: -origin.x, y: -origin.y)
                let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
                ScreenshotAnnotationRenderer.renderSpotlightOverlay(items.filter { $0.tool == .spotlight }, selection: canvasSel, in: &ctx)
                for item in items where item.tool != .spotlight {
                    ScreenshotAnnotationRenderer.render(item, in: &ctx)
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .allowsHitTesting(false)
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        if session.activeDragMode == nil {
            session.updateHover(at: canvasStart)
            session.activeDragMode = resolveDragMode(start: canvasStart)
        }
        session.updateHover(at: canvasLoc)
        guard let mode = session.activeDragMode else { return }
        switch mode {
        case .noop: break
        case .creating(let ctx):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: ctx.startPoint, to: canvasLoc) else { return }
            session.isDraggingSelection = true; session.selectedWindow = nil
            session.selectionRect = CaptureSelectionGeometry.rubberBandRect(from: ctx.startPoint, to: canvasLoc, clampedTo: session.screenBounds)
        case .resizing(let handle, let initial, let startPt):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: startPt, to: canvasLoc) else { return }
            session.isDraggingSelection = true; session.selectedWindow = nil
            session.selectionRect = resizedRect(initial, handle: handle, to: canvasLoc).intersection(session.screenBounds)
        case .movingSelection(let initial, let start, let savedAnnotations):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: start, to: canvasLoc) else { return }
            session.isDraggingSelection = true
            session.moveSelection(from: initial, initialAnnotations: savedAnnotations, dx: canvasLoc.x - start.x, dy: canvasLoc.y - start.y)
        case .annotating(let tool):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: canvasStart, to: canvasLoc) else { return }
            if tool == .pen || tool == .highlighter || tool == .mosaic {
                var pts = session.draftAnnotation?.points ?? [canvasStart]; pts.append(canvasLoc)
                session.draftAnnotation = ScreenshotAnnotation(tool: tool, color: session.selectedColor, strokeSize: session.strokeSize, points: pts)
            } else if [.rect, .ellipse, .arrow, .line, .spotlight].contains(tool) {
                session.draftAnnotation = ScreenshotAnnotation(tool: tool, color: session.selectedColor, strokeSize: session.strokeSize, points: [canvasStart, canvasLoc])
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        let mode = session.activeDragMode
        session.activeDragMode = nil; session.isDraggingSelection = false
        if case .creating(let ctx) = mode {
            let resolution = CaptureSelectionGeometry.resolveCreationEnd(
                context: ctx, endPoint: canvasLoc, currentSelection: session.selectionRect,
                currentHoveredWindow: session.hoveredWindow, windows: session.windows, minimumSelectionSize: 6
            )
            switch resolution {
            case .snapToWindow(let win):
                session.selectWindow(win, excludeShadow: session.excludeWindowShadow || NSEvent.modifierFlags.contains(.option))
                onAction(session.mode == .quickOCR ? .ocr : .syncClipboard)
            case .commitRegion(let sel):
                session.selectionRect = sel; session.selectedWindow = nil
                if session.mode == .quickOCR, sel.width >= 8, sel.height >= 8 { onAction(.ocr); return }
                if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
            case .restorePrevious(let prevSel, let prevWin):
                session.selectionRect = prevSel; session.selectedWindow = prevWin
                session.updateHover(at: canvasLoc)
            }
            return
        }
        if !CaptureSelectionGeometry.shouldBeginDrag(from: canvasStart, to: canvasLoc) {
            session.draftAnnotation = nil; handleTapInsideSelection(at: canvasLoc); return
        }
        if case .resizing = mode, session.mode == .interactiveAnnotate {
            onAction(.syncClipboard)
        } else if case .movingSelection = mode, session.mode == .interactiveAnnotate {
            onAction(.syncClipboard)
        }
        if let draft = session.draftAnnotation { session.appendAnnotation(draft); session.draftAnnotation = nil }
    }

    private func handleTapInsideSelection(at point: CGPoint) {
        guard let sel = session.selectionRect, sel.contains(point) else { return }
        if session.activeTool == .counter {
            let idx = session.nextCounterIndex; session.nextCounterIndex += 1
            session.appendAnnotation(ScreenshotAnnotation(tool: .counter, color: session.selectedColor, strokeSize: session.strokeSize, points: [point], counterIndex: idx))
            return
        }
        if session.activeTool == .text { session.commitTextAnnotation(); session.pendingTextPoint = point; return }
        let now = Date().timeIntervalSinceReferenceDate
        if session.activeTool == .move && now - session.lastTapTimestamp < 0.32 && hypot(point.x - session.lastTapPoint.x, point.y - session.lastTapPoint.y) < 12 {
            onAction(session.mode == .quickOCR ? .ocr : .copy)
        }
        session.lastTapTimestamp = now; session.lastTapPoint = point
    }

    private func resolveDragMode(start: CGPoint) -> ScreenshotDragMode {
        let makeCreating = {
            ScreenshotDragMode.creating(SelectionCreationContext(
                startPoint: start, previousSelection: session.selectionRect,
                previousSelectedWindow: session.selectedWindow,
                pressHoveredWindow: session.hoveredWindow ?? session.topWindow(at: start)
            ))
        }
        guard let sel = session.selectionRect?.standardized else { return makeCreating() }
        for h in SelectionHandle.allCases where hypot(start.x - h.point(in: sel).x, start.y - h.point(in: sel).y) <= 12 {
            return .resizing(h, sel, start)
        }
        if sel.contains(start) {
            return session.activeTool == .move ? .movingSelection(sel, start, session.annotations) : .annotating(session.activeTool)
        }
        return session.annotations.isEmpty ? makeCreating() : .noop
    }

    private func resizedRect(_ r: CGRect, handle: SelectionHandle, to pt: CGPoint) -> CGRect {
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
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
