import AppKit
import CoreGraphics
import LucentCore
import LucentMedia
import SwiftUI

@MainActor
extension ScreenCaptureCoordinator {
    func handleEvent(_ event: NSEvent, session current: ScreenshotSessionState) -> NSEvent? {
        if event.type == .scrollWheel {
            let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY * 10
            guard abs(dy) > 0.1 else { return event }
            if current.selectionRect == nil && !current.isPinEditSession {
                _ = current.stepAXDepth(scrollUp: dy > 0)
            } else if current.pendingTextPoint == nil {
                current.adjustScaleByScroll(deltaY: dy)
            }
            return nil
        }
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            let prevID = current.activeDisplayID
            current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
            if event.type == .mouseMoved, current.activeDisplayID != prevID,
               !current.isDraggingSelection, current.activeDragMode == nil, current.pendingTextPoint == nil {
                panelByDisplayID[current.activeDisplayID]?.makeKey()
            }
            return event
        }
        if event.type == .rightMouseDown {
            if current.pendingTextPoint != nil {
                current.commitTextAnnotation()
            } else if current.isPinEditSession {
                if current.confirmOrWarnBeforeDiscard() { finish(with: .cancelled) }
            } else if current.selectionRect != nil {
                guard current.confirmOrWarnBeforeDiscard() else { return nil }
                current.selectionRect = nil; current.selectedWindow = nil
                current.clearAnnotations(); current.activeTool = .move
                current.updateHover(at: current.topology.canvasPoint(fromAppKitGlobal: NSEvent.mouseLocation))
            } else {
                finish(with: .cancelled)
            }
            return nil
        }
        if event.keyCode == 53 {
            if current.pendingTextPoint != nil { current.cancelPendingText() }
            else if current.confirmOrWarnBeforeDiscard() { finish(with: .cancelled) }
            return nil
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 6 && mods.contains(.command) {
            if mods.contains(.shift) { current.redoAnnotation() } else { current.undoAnnotation() }
            return nil
        }
        guard current.pendingTextPoint == nil else { return event }

        let cleanMods = mods.subtracting([.numericPad, .function])
        if (event.keyCode == 51 || event.keyCode == 117) && cleanMods.isEmpty {
            if current.deleteSelectedAnnotation() { return nil }
        }
        if event.keyCode == 0 && cleanMods == [.command, .shift] && !current.isPinEditSession {
            Task { [weak self] in await self?.recaptureCurrentOverlay(session: current) }
            return nil
        }
        if event.keyCode == 48 && cleanMods.isEmpty && current.selectionRect == nil { _ = current.cycleHoveredWindow(); return nil }
        if event.keyCode == 3 && cleanMods.isEmpty && current.selectionRect == nil && !current.isPinEditSession {
            current.selectActiveScreenFull()
            handleAction(current.mode == .quickOCR ? .ocr : .syncClipboard)
            return nil
        }
        if (event.keyCode == 36 || event.keyCode == 76), current.selectionRect != nil {
            handleAction(current.mode == .quickOCR ? .ocr : .copy); return nil
        }
        if event.keyCode == 8 && mods.contains(.command), current.selectionRect != nil { handleAction(.copy); return nil }
        if event.keyCode == 1 && cleanMods == [.command], current.selectionRect != nil { handleAction(.save); return nil }
        if event.keyCode == 8 && !mods.contains(.command) {
            didModifyPasteboard = false
            let colorVal = mods.contains(.shift) ? current.cursorRGB : current.cursorHex
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(colorVal, forType: .string)
            current.bannerMessage = L10n.pick("已复制色值 \(colorVal)", "Copied color \(colorVal)")
            return nil
        }
        if current.selectionRect != nil, [123, 124, 125, 126].contains(event.keyCode), cleanMods.isSubset(of: [.shift]) {
            let step: CGFloat = cleanMods.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
            let dy: CGFloat = event.keyCode == 126 ? -step : (event.keyCode == 125 ? step : 0)
            if current.nudgeSelectedOrSelection(dx: dx, dy: dy) { syncSelectionIfPossible(session: current); return nil }
        }
        if event.keyCode == 15 && cleanMods.isEmpty && current.selectionRect == nil, let prev = current.previousSelectionRect {
            current.selectionRect = prev; current.selectedWindow = nil
            handleAction(current.mode == .quickOCR ? .ocr : .syncClipboard)
            return nil
        }
        if cleanMods.isEmpty, current.selectionRect != nil {
            if event.keyCode == 1 && !current.isPinEditSession { handleAction(.longShot); return nil }
            if event.keyCode == 35 && !current.isPinEditSession { handleAction(.pin); return nil }
            if event.keyCode == 31 && !current.isPinEditSession { handleAction(.ocr); return nil }
            if let shortcutTool = AnnotationToolKind.fromShortcutKeyCode(event.keyCode) {
                current.commitTextAnnotation(); current.activeTool = shortcutTool; return nil
            }
        }
        return event
    }

    private func recaptureCurrentOverlay(session: ScreenshotSessionState) async {
        guard let fresh = try? await ScreenTopologyAndWindowMatcher.captureSnapshot(includeOwnOverlayWindows: true) else { return }
        session.topology = fresh
        session.selectionRect = nil
        session.selectedWindow = nil
        session.annotations.removeAll()
        session.undoSnapshots.removeAll()
        session.redoSnapshots.removeAll()
        session.selectedAnnotationID = nil
        session.activeTool = .move
        session.bannerMessage = L10n.pick("已将当前画面烘焙为新底图，请重新框选", "Overlay baked into fresh canvas — select region")
        for slice in fresh.displays {
            panelByDisplayID[slice.displayID]?.contentView = FirstMouseHostingView(rootView: LocalizedRootContainer {
                ScreenshotCanvasView(session: session, slice: slice, onAction: { [weak self] a in self?.handleAction(a) })
            })
        }
    }

    func handleAction(_ action: ScreenshotToolbarAction) {
        guard let session = activeSession else { return }
        session.commitTextAnnotation()
        switch action {
        case .cancel:
            if session.confirmOrWarnBeforeDiscard() { finish(with: .cancelled) }
        case .undo: session.undoAnnotation()
        case .redo: session.redoAnnotation()
        case .deleteSelected: _ = session.deleteSelectedAnnotation()
        case .clear: session.clearAnnotations()
        case .syncClipboard: syncSelectionIfPossible(session: session)
        case .longShot:
            guard !session.isPinEditSession,
                  let sel = session.selectionRect?.standardized, sel.width >= 32, sel.height >= 48 else { return }
            lastSelectionRect = sel
            let targetWinID = session.selectedWindow?.id
            let topology = session.topology
            finish(with: .cancelled, animated: false)
            ScrollingCaptureController.shared.start(selectionCanvasRect: sel, lockedWindowID: targetWinID, topology: topology)
        case .copy, .pin, .ocr, .cutout, .save:
            guard let sel = session.selectionRect?.standardized, sel.width >= 4, sel.height >= 4 else { return }
            if !session.isPinEditSession { lastSelectionRect = sel }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let includeAll = action != .ocr
                    let rendered = try await self.renderCaptureImage(session: session, selection: sel, includeOverlayShapes: includeAll)
                    let cleanBase = action == .pin
                        ? (try? await self.renderCaptureImage(session: session, selection: sel, includeOverlayShapes: false, excludeRedactions: true))
                        : nil
                    self.performExport(action: action, image: rendered.image, scale: rendered.scale, cleanBase: cleanBase?.image, selection: sel, session: session)
                } catch {
                    session.bannerMessage = error.localizedDescription
                }
            }
        }
    }

    func renderCaptureImage(
        session: ScreenshotSessionState,
        selection: CGRect,
        includeOverlayShapes: Bool = true,
        excludeRedactions: Bool = false
    ) async throws -> (image: CGImage, scale: CGFloat) {
        let filteredAnnotations: [ScreenshotAnnotation]
        if excludeRedactions {
            filteredAnnotations = []
        } else if includeOverlayShapes {
            filteredAnnotations = session.annotations
        } else {
            filteredAnnotations = session.annotations.filter { $0.tool == .mosaic || $0.tool == .blur }
        }
        let fallbackScale = session.effectiveScale(for: selection)
        if !session.isPinEditSession,
           let win = session.selectedWindow,
           let winCapture = try? await ScreenTopologyAndWindowMatcher.captureIndependentWindowImage(
               windowID: win.id, ignoreShadow: session.excludeWindowShadow, fallbackScale: fallbackScale
           ) {
            let composed = try ScreenshotCompositor.compositeAnnotationsOntoWindowImage(
                windowImage: winCapture.image, windowCanvasFrame: win.frame, annotations: filteredAnnotations
            )
            return (composed, winCapture.scale)
        }
        return try ScreenshotCompositor.renderMultiDisplaySelection(
            slices: session.topology.compositorSlices, canvasBounds: session.screenBounds,
            selectionRect: selection, annotations: filteredAnnotations
        )
    }

    func syncSelectionIfPossible(session: ScreenshotSessionState) {
        guard session.mode == .interactiveAnnotate, !session.isPinEditSession,
              let sel = session.selectionRect?.standardized, sel.width >= 4, sel.height >= 4 else { return }
        Task { [weak self] in
            guard let self, self.activeSession === session else { return }
            if let rendered = try? await self.renderCaptureImage(session: session, selection: sel) {
                ScreenshotCompositor.copyImageToPasteboard(rendered.image, scale: rendered.scale, lazy: true)
                self.didModifyPasteboard = true; session.hasAutoCopied = true
                if session.bannerMessage == nil {
                    let prefix = session.selectedWindow != nil ? L10n.pick("✓ 已捕获独立窗口", "✓ Window captured") : L10n.pick("✓ 已就绪剪贴板", "✓ Ready in clipboard")
                    session.bannerMessage = "\(prefix) · " + L10n.pick("1–0/B 标注 · S 长图 · P 钉图 · 回车完成", "1–0/B annotate · S scroll · P pin")
                }
            }
        }
    }

    private func performExport(
        action: ScreenshotToolbarAction,
        image: CGImage,
        scale: CGFloat,
        cleanBase: CGImage?,
        selection: CGRect,
        session: ScreenshotSessionState
    ) {
        do {
            if session.isPinEditSession && action == .copy {
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
                finish(with: .pinEdited(url, annotations: normalizedAnnotations(session.annotations, in: selection)), animated: false)
                return
            }

            switch action {
            case .copy:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
                didModifyPasteboard = true; finish(with: .copied(url))
            case .pin:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                let baseURL = try cleanBase.map { try ScreenshotCompositor.saveTempCapture($0, scale: scale) }
                ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
                didModifyPasteboard = true
                let rect = session.screenRectForSelection() ?? NSRect(x: 200, y: 260, width: 360, height: 240)
                finish(with: .pinned(url, rect, cleanBaseURL: baseURL, annotations: normalizedAnnotations(session.annotations, in: selection)), animated: false)
            case .ocr:
                finish(with: .ocrRequested(try ScreenshotCompositor.saveTempCapture(image, scale: scale)))
            case .cutout:
                let url = try ScreenshotCompositor.saveTempCapture(image, scale: scale)
                ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
                didModifyPasteboard = true; finish(with: .cutoutRequested(url))
            case .save:
                try saveExportImage(image, scale: scale, session: session)
            default: break
            }
        } catch { session.bannerMessage = error.localizedDescription }
    }

    private func normalizedAnnotations(_ items: [ScreenshotAnnotation], in selection: CGRect) -> [ScreenshotAnnotation] {
        items.map { item in
            var copy = item
            copy.points = item.points.map {
                CGPoint(x: max(0, $0.x - selection.minX) / max(selection.width, 1), y: max(0, $0.y - selection.minY) / max(selection.height, 1))
            }
            return copy
        }
    }
}
