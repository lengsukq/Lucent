import AppKit
import LucentCore
import LucentMedia
import SwiftUI

struct ScreenshotCanvasView: View {
    @ObservedObject var session: ScreenshotSessionState
    @ObservedObject private var effectsCache: SliceLazyEffectsCache
    let slice: ScreenDisplaySlice
    let onAction: (ScreenshotToolbarAction) -> Void

    init(
        session: ScreenshotSessionState,
        slice: ScreenDisplaySlice,
        onAction: @escaping (ScreenshotToolbarAction) -> Void
    ) {
        self.session = session
        self._effectsCache = ObservedObject(wrappedValue: session.topology.effectsCache)
        self.slice = slice
        self.onAction = onAction
    }

    var origin: CGPoint { slice.canvasFrame.origin }
    var viewSize: CGSize { slice.canvasFrame.size }

    func toCanvas(_ local: CGPoint) -> CGPoint { CGPoint(x: local.x + origin.x, y: local.y + origin.y) }
    func toLocal(_ canvasRect: CGRect) -> CGRect { canvasRect.offsetBy(dx: -origin.x, dy: -origin.y) }

    private var shouldHostToolbar: Bool {
        guard let sel = session.selectionRect?.standardized, sel.width >= 4, !session.isDraggingSelection else { return false }
        return session.topology.targetSlice(forSelection: sel, fallbackPoint: session.cursorPoint)?.displayID == slice.displayID
    }

    private var hasMosaicItems: Bool {
        session.activeTool == .mosaic
            || session.draftAnnotation?.tool == .mosaic
            || session.annotations.contains(where: { $0.tool == .mosaic })
    }

    private var hasBlurItems: Bool {
        session.activeTool == .blur
            || session.draftAnnotation?.tool == .blur
            || session.annotations.contains(where: { $0.tool == .blur })
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
                blurOverlay(localSel: localSel)
                annotationCanvas(canvasSel: sel, localSel: localSel)

                ScreenshotSelectionChrome(
                    rect: localSel,
                    sliceSize: viewSize,
                    pixelSizeText: "\(pxW) × \(pxH) px",
                    windowTitle: session.selectedWindow?.displayLabel,
                    mode: session.mode,
                    isLockedPinEdit: session.isPinEditSession
                )
            } else if let snapRect = session.activeHoveredSnapRect, let label = session.activeHoveredSnapLabel {
                let isSubCtrl = !session.axControls.isEmpty && session.axDepthIndex < session.axControls.count
                ScreenshotWindowSnapOverlay(
                    rect: toLocal(snapRect),
                    sliceSize: viewSize,
                    label: label,
                    overlapCount: session.overlappingWindowCount,
                    isSubControl: isSubCtrl
                )
            }

            Color.clear
                .frame(width: viewSize.width, height: viewSize.height)
                .contentShape(Rectangle())
                .onContinuousHover { if case .active(let pt) = $0 { session.updateHover(at: toCanvas(pt)) } }
                .gesture(DragGesture(minimumDistance: 0).onChanged(handleDragChanged).onEnded(handleDragEnded))

            if session.activeDisplayID == slice.displayID {
                if session.selectionRect == nil && !session.isPinEditSession {
                    ScreenshotModeGuidePill(
                        mode: session.mode,
                        hasLastSelection: session.previousSelectionRect != nil,
                        multiDisplay: session.topology.displays.count > 1
                    ).position(x: viewSize.width / 2, y: 34)
                }
                if (session.selectionRect == nil || session.isDraggingSelection)
                    && session.pendingTextPoint == nil && !session.isPinEditSession {
                    ScreenshotLoupeView(
                        session: session,
                        localCursor: CGPoint(x: session.cursorPoint.x - origin.x, y: session.cursorPoint.y - origin.y),
                        sliceSize: viewSize
                    )
                }
                if let banner = session.bannerMessage {
                    Text(banner).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.76), in: Capsule())
                        .position(x: viewSize.width / 2, y: 68).allowsHitTesting(false)
                }
            }

            if let pt = session.pendingTextPoint, slice.canvasFrame.contains(pt) {
                ScreenshotInlineTextEditor(
                    session: session,
                    localPoint: CGPoint(x: pt.x - origin.x, y: pt.y - origin.y), sliceSize: viewSize
                )
            }

            if shouldHostToolbar, let sel = session.selectionRect?.standardized {
                CaptureClampedToolbarLayout(
                    localSelection: toLocal(sel),
                    horizontalAlign: (session.selectedWindow != nil || session.isPinEditSession) ? .center : .trailing
                ) {
                    ScreenshotToolbarView(
                        session: session,
                        maxAvailableWidth: viewSize.width - 28,
                        onAction: onAction
                    )
                }
                .frame(width: viewSize.width, height: viewSize.height)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .clipped()
        .onAppear { warmLazyEffectsIfNeeded() }
        .onChange(of: session.activeTool) { _, _ in warmLazyEffectsIfNeeded() }
        .onChange(of: session.annotations) { _, _ in
            warmLazyEffectsIfNeeded()
            if session.mode == .interactiveAnnotate && !session.isPinEditSession && shouldHostToolbar {
                onAction(.syncClipboard)
            }
        }
    }

    private func warmLazyEffectsIfNeeded() {
        if hasMosaicItems { _ = effectsCache.ensurePixelated(for: slice) }
        if hasBlurItems { _ = effectsCache.ensureBlurred(for: slice) }
    }

    private var dimmingOverlay: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: viewSize))
            if let hole = (session.selectionRect ?? session.activeHoveredSnapRect)?.standardized {
                let localHole = toLocal(hole).intersection(CGRect(origin: .zero, size: viewSize))
                if !localHole.isNull && localHole.width >= 2 && localHole.height >= 2 { path.addRect(localHole) }
            }
        }
        .fill(Color.black.opacity(session.isPinEditSession ? 0.26 : 0.42), style: FillStyle(eoFill: true))
        .frame(width: viewSize.width, height: viewSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func mosaicOverlay(localSel: CGRect) -> some View {
        let clippedLocal = localSel.intersection(CGRect(origin: .zero, size: viewSize))
        if hasMosaicItems,
           let pix = effectsCache.pixelatedByDisplay[slice.displayID],
           !clippedLocal.isNull, clippedLocal.width > 0, clippedLocal.height > 0 {
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
    private func blurOverlay(localSel: CGRect) -> some View {
        let clippedLocal = localSel.intersection(CGRect(origin: .zero, size: viewSize))
        if hasBlurItems,
           let blurred = effectsCache.blurredByDisplay[slice.displayID],
           !clippedLocal.isNull, clippedLocal.width > 0, clippedLocal.height > 0 {
            Image(decorative: blurred, scale: CGFloat(blurred.width) / max(viewSize.width, 1), orientation: .up)
                .resizable()
                .frame(width: viewSize.width, height: viewSize.height)
                .mask(
                    Canvas { ctx, _ in
                        ctx.clip(to: Path(clippedLocal))
                        ctx.translateBy(x: -origin.x, y: -origin.y)
                        let items = session.annotations + (session.draftAnnotation.map { [$0] } ?? [])
                        for item in items where item.tool == .blur {
                            ScreenshotAnnotationRenderer.renderBlurMask(item, in: &ctx)
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
                    ScreenshotAnnotationRenderer.render(item, isEditingText: session.editingAnnotationID == item.id && !session.isEditingCounterNumber, in: &ctx)
                }
                if let selID = session.selectedAnnotationID,
                   let selected = session.annotations.first(where: { $0.id == selID }) {
                    ScreenshotAnnotationRenderer.renderSelectionGizmo(for: selected, in: &ctx)
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .allowsHitTesting(false)
        }
    }
}
