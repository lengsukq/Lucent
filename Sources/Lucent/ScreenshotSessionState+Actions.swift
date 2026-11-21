import AppKit
import LucentCore
import LucentMedia
import SwiftUI

@MainActor
extension ScreenshotSessionState {
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
            axControls = []
            return
        }
        let resolved = CaptureSelectionGeometry.resolveHover(
            at: clamped, windows: windows,
            lastTopWindowID: &lastTopHitWindowID, cycleIndex: &windowCycleIndex
        )
        hoveredWindow = resolved.hovered
        overlappingWindowCount = resolved.overlapCount
        scheduleAXProbeIfNeeded(at: clamped)
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
        axControls = []; axDepthIndex = 0
        bannerMessage = L10n.pick(
            "窗口层级 \(windowCycleIndex + 1)/\(hits.count)：\(picked.displayLabel)",
            "Window \(windowCycleIndex + 1)/\(hits.count): \(picked.displayLabel)"
        )
        return true
    }

    @discardableResult
    func stepAXDepth(scrollUp: Bool) -> Bool {
        guard selectionRect == nil, !axControls.isEmpty else { return false }
        let maxIdx = axControls.count // index == axControls.count means whole window
        let next = scrollUp ? min(maxIdx, axDepthIndex + 1) : max(0, axDepthIndex - 1)
        guard next != axDepthIndex else { return false }
        axDepthIndex = next
        if next < axControls.count {
            bannerMessage = L10n.pick("控件捕捉：\(axControls[next].roleLabel)", "Element: \(axControls[next].roleLabel)")
        } else if let win = hoveredWindow {
            bannerMessage = L10n.pick("整窗捕捉：\(win.displayLabel)", "Window: \(win.displayLabel)")
        }
        return true
    }

    func adjustScaleByScroll(deltaY: CGFloat) {
        let step: CGFloat = deltaY > 0 ? 0.08 : -0.08
        if let selID = selectedAnnotationID, let idx = annotations.firstIndex(where: { $0.id == selID }) {
            recordUndoSnapshot()
            let next = min(max(annotations[idx].customScale + step, 0.4), 3.5)
            annotations[idx].customScale = next
            activeCustomScale = next
            bannerMessage = L10n.pick("尺寸倍率 \(Int(round(next * 100)))%", "Scale \(Int(round(next * 100)))%")
        } else if activeTool != .move && activeTool != .spotlight {
            activeCustomScale = min(max(activeCustomScale + step, 0.4), 3.5)
            bannerMessage = L10n.pick("画笔倍率 \(Int(round(activeCustomScale * 100)))%", "Brush \(Int(round(activeCustomScale * 100)))%")
        }
    }

    func selectWindow(_ window: DetectedScreenWindow, excludeShadow: Bool) {
        selectedWindow = window
        excludeWindowShadow = excludeShadow
        selectionRect = window.frame
        hoveredWindow = nil
        overlappingWindowCount = 0
        axControls = []
    }

    func selectActiveScreenFull() {
        guard !isPinEditSession else { return }
        let slice = topology.displays.first { $0.displayID == activeDisplayID } ?? topology.displays.first
        guard let frame = slice?.canvasFrame else { return }
        selectedWindow = nil
        hoveredWindow = nil
        axControls = []
        selectionRect = frame
    }

    func beginEditingAnnotation(_ id: UUID) {
        guard let item = annotations.first(where: { $0.id == id }) else { return }
        commitTextAnnotation()
        if item.tool == .text, let pt = item.points.first {
            selectedAnnotationID = id
            editingAnnotationID = id
            isEditingCounterNumber = false
            pendingTextPoint = pt
            pendingTextValue = item.text
        } else if item.tool == .counter, let pt = item.points.first {
            selectedAnnotationID = id
            editingAnnotationID = id
            isEditingCounterNumber = true
            pendingTextPoint = pt
            pendingTextValue = "\(item.counterIndex)"
        }
    }

    func commitTextAnnotation() {
        guard let pt = pendingTextPoint else { return }
        let trimmed = pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editID = editingAnnotationID, let idx = annotations.firstIndex(where: { $0.id == editID }) {
            if isEditingCounterNumber {
                if let parsed = Int(trimmed), parsed > 0, parsed != annotations[idx].counterIndex {
                    recordUndoSnapshot()
                    annotations[idx].counterIndex = parsed
                    nextCounterIndex = max(nextCounterIndex, parsed + 1)
                }
            } else if !trimmed.isEmpty && trimmed != annotations[idx].text {
                recordUndoSnapshot()
                annotations[idx].text = trimmed
            }
        } else if !trimmed.isEmpty {
            appendAnnotation(ScreenshotAnnotation(
                tool: .text,
                color: selectedColor,
                gradient: activeGradient,
                strokeSize: strokeSize,
                customScale: activeCustomScale,
                points: [pt],
                text: trimmed
            ))
        }
        pendingTextPoint = nil
        pendingTextValue = ""
        editingAnnotationID = nil
        isEditingCounterNumber = false
    }

    func cancelPendingText() {
        pendingTextPoint = nil
        pendingTextValue = ""
        editingAnnotationID = nil
        isEditingCounterNumber = false
    }

    func moveSelection(from initial: CGRect, initialAnnotations: [ScreenshotAnnotation], dx: CGFloat, dy: CGFloat) {
        guard !isPinEditSession else { return }
        selectedWindow = nil
        let clampedX = min(max(0, initial.minX + dx), screenBounds.width - initial.width)
        let clampedY = min(max(0, initial.minY + dy), screenBounds.height - initial.height)
        let appliedDX = clampedX - initial.minX
        let appliedDY = clampedY - initial.minY
        selectionRect = CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: initial.size)
        if !initialAnnotations.isEmpty {
            annotations = initialAnnotations.map { AnnotationGeometry.translated($0, dx: appliedDX, dy: appliedDY) }
        }
    }

    @discardableResult
    func nudgeSelectedOrSelection(dx: CGFloat, dy: CGFloat) -> Bool {
        if let selID = selectedAnnotationID, let idx = annotations.firstIndex(where: { $0.id == selID }) {
            recordUndoSnapshot()
            annotations[idx] = AnnotationGeometry.translated(annotations[idx], dx: dx, dy: dy)
            return true
        }
        guard !isPinEditSession, let rect = selectionRect else { return false }
        moveSelection(from: rect, initialAnnotations: annotations, dx: dx, dy: dy)
        return true
    }

    func confirmOrWarnBeforeDiscard() -> Bool {
        guard !annotations.isEmpty, GeneralPreferences.load().confirmCancelAnnotatedCaptureWithDoublePress else {
            return true
        }
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastCancelWarnTimestamp <= 2.0 {
            lastCancelWarnTimestamp = 0
            return true
        }
        lastCancelWarnTimestamp = now
        bannerMessage = L10n.pick(
            "已有未保存标注，2 秒内再按一次 Esc / 右键确认放弃",
            "Unsaved annotations — press Esc / Right-click again within 2s to discard"
        )
        return false
    }
}
