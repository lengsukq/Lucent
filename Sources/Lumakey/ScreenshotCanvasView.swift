import AppKit
import LumakeyCore
import SwiftUI

struct ScreenshotCanvasView: View {
    @ObservedObject var session: ScreenshotSessionState
    let slice: ScreenDisplaySlice
    let onAction: (ScreenshotToolbarAction) -> Void

    private var origin: CGPoint { slice.canvasFrame.origin }
    private var viewSize: CGSize { slice.canvasFrame.size }

    private var imageScale: CGFloat {
        guard session.screenBounds.width > 0 else { return slice.scale }
        return CGFloat(session.baseImage.width) / session.screenBounds.width
    }

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
        let x = min(max(localSel.maxX - toolbarW / 2, toolbarW / 2 + 12), viewSize.width - toolbarW / 2 - 12)
        let belowY = localSel.maxY + toolbarH / 2 + 10, aboveY = localSel.minY - toolbarH / 2 - 10
        let y: CGFloat
        if belowY + toolbarH / 2 <= viewSize.height - 10 { y = belowY }
        else if aboveY - toolbarH / 2 >= 10 { y = aboveY }
        else { y = min(max(toolbarH / 2 + 12, localSel.maxY - toolbarH / 2 - 12), viewSize.height - toolbarH / 2 - 12) }
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: session.baseImage, scale: imageScale, orientation: .up)
                .resizable()
                .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                .offset(x: -origin.x, y: -origin.y)
                .allowsHitTesting(false)

            dimmingOverlay

            if let sel = session.selectionRect?.standardized {
                mosaicOverlay(clippedTo: sel)
                annotationCanvas(clippedTo: sel)
                    .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                    .mask(Rectangle().frame(width: sel.width, height: sel.height).position(x: sel.midX, y: sel.midY))
                    .offset(x: -origin.x, y: -origin.y)

                ScreenshotSelectionChrome(
                    rect: toLocal(sel),
                    pixelSizeText: "\(Int(round(sel.width))) × \(Int(round(sel.height))) px",
                    windowTitle: session.selectedWindow?.displayLabel,
                    mode: session.mode
                )
            } else if let hover = session.hoveredWindow {
                ScreenshotWindowSnapOverlay(
                    rect: toLocal(hover.frame), label: hover.displayLabel, overlapCount: session.overlappingWindowCount
                )
            }

            Color.clear.contentShape(Rectangle())
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
                        sliceSize: viewSize, imageScale: imageScale
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
        .frame(width: viewSize.width, height: viewSize.height).clipped()
        .onChange(of: session.annotations.count) { _, _ in
            if session.mode == .interactiveAnnotate && shouldHostToolbar { onAction(.syncClipboard) }
        }
    }

    private var dimmingOverlay: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: viewSize))
            if let hole = (session.selectionRect ?? session.hoveredWindowRect)?.standardized {
                let localHole = toLocal(hole).intersection(CGRect(origin: .zero, size: viewSize))
                if !localHole.isNull && localHole.width > 0 && localHole.height > 0 { path.addRect(localHole) }
            }
        }
        .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true)).allowsHitTesting(false)
    }

    @ViewBuilder
    private func mosaicOverlay(clippedTo sel: CGRect) -> some View {
        if let pix = session.pixelatedImage {
            Image(decorative: pix, scale: CGFloat(pix.width) / max(session.screenBounds.width, 1), orientation: .up)
                .interpolation(.none).resizable()
                .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                .mask(
                    Canvas { ctx, _ in
                        let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
                        for item in items where item.tool == .mosaic {
                            ScreenshotAnnotationRenderer.renderMosaicMask(item, in: &ctx)
                        }
                    }
                    .frame(width: session.screenBounds.width, height: session.screenBounds.height)
                    .mask(Rectangle().frame(width: sel.width, height: sel.height).position(x: sel.midX, y: sel.midY))
                )
                .offset(x: -origin.x, y: -origin.y).allowsHitTesting(false)
        }
    }

    private func annotationCanvas(clippedTo sel: CGRect) -> some View {
        Canvas { ctx, _ in
            let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
            ScreenshotAnnotationRenderer.renderSpotlightOverlay(items.filter { $0.tool == .spotlight }, selection: sel, in: &ctx)
            for item in items where item.tool != .spotlight {
                ScreenshotAnnotationRenderer.render(item, in: &ctx)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        session.updateHover(at: canvasLoc)
        if session.activeDragMode == nil { session.activeDragMode = resolveDragMode(start: canvasStart) }
        guard let mode = session.activeDragMode else { return }
        let dist = hypot(canvasLoc.x - canvasStart.x, canvasLoc.y - canvasStart.y)
        switch mode {
        case .noop: break
        case .creating(let startPt):
            if dist >= 2 { session.isDraggingSelection = true; session.selectedWindow = nil }
            session.selectionRect = CGRect(
                x: min(startPt.x, canvasLoc.x), y: min(startPt.y, canvasLoc.y),
                width: abs(canvasLoc.x - startPt.x), height: abs(canvasLoc.y - startPt.y)
            ).intersection(session.screenBounds)
        case .resizing(let handle, let initial):
            if dist >= 2 { session.isDraggingSelection = true; session.selectedWindow = nil }
            session.selectionRect = resizedRect(initial, handle: handle, to: canvasLoc).intersection(session.screenBounds)
        case .movingSelection(let initial, let start, let savedAnnotations):
            if dist >= 2 { session.isDraggingSelection = true }
            session.moveSelection(from: initial, initialAnnotations: savedAnnotations, dx: canvasLoc.x - start.x, dy: canvasLoc.y - start.y)
        case .annotating(let tool):
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
        if hypot(canvasLoc.x - canvasStart.x, canvasLoc.y - canvasStart.y) < 3 {
            session.draftAnnotation = nil; handleSingleOrDoubleClick(at: canvasLoc); return
        }
        if case .creating = mode {
            if let sel = session.selectionRect, sel.width < 6 || sel.height < 6, let hover = session.hoveredWindow {
                session.selectWindow(hover, excludeShadow: NSEvent.modifierFlags.contains(.option))
            }
            if session.mode == .quickOCR, let sel = session.selectionRect?.standardized, sel.width >= 8, sel.height >= 8 {
                onAction(.ocr); return
            }
            if session.mode == .interactiveAnnotate { onAction(.syncClipboard) }
        } else if case .resizing = mode, session.mode == .interactiveAnnotate {
            onAction(.syncClipboard)
        } else if case .movingSelection = mode, session.mode == .interactiveAnnotate {
            onAction(.syncClipboard)
        }
        if let draft = session.draftAnnotation { session.appendAnnotation(draft); session.draftAnnotation = nil }
    }

    private func handleSingleOrDoubleClick(at point: CGPoint) {
        if session.selectionRect == nil, let hover = session.hoveredWindow {
            session.selectWindow(hover, excludeShadow: NSEvent.modifierFlags.contains(.option))
            onAction(session.mode == .quickOCR ? .ocr : .syncClipboard)
            return
        }
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
        guard let sel = session.selectionRect?.standardized else { return .creating(start) }
        for h in SelectionHandle.allCases where hypot(start.x - h.point(in: sel).x, start.y - h.point(in: sel).y) <= 12 { return .resizing(h, sel) }
        if sel.contains(start) {
            return session.activeTool == .move ? .movingSelection(sel, start, session.annotations) : .annotating(session.activeTool)
        }
        return session.annotations.isEmpty ? .creating(start) : .noop
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
