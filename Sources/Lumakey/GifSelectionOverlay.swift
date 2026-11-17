import AppKit
import CoreGraphics
import LumakeyCore
import SwiftUI

struct GifSelectionOverlayView: View {
    @ObservedObject var session: GifSelectionSession
    let slice: ScreenDisplaySlice
    let onStartRecording: () -> Void
    let onCancel: () -> Void

    private var origin: CGPoint { slice.canvasFrame.origin }
    private var viewSize: CGSize { slice.canvasFrame.size }
    private func toCanvas(_ local: CGPoint) -> CGPoint { CGPoint(x: local.x + origin.x, y: local.y + origin.y) }
    private func toLocal(_ canvasRect: CGRect) -> CGRect { canvasRect.offsetBy(dx: -origin.x, dy: -origin.y) }

    private var shouldHostToolbar: Bool {
        if let sel = session.selectionRect?.standardized, sel.width >= 12 {
            return session.topology.targetSlice(forSelection: sel, fallbackPoint: session.cursorPoint)?.displayID == slice.displayID
        }
        return session.activeDisplayID == slice.displayID
    }

    private var controlBarPosition: CGPoint {
        guard let sel = session.selectionRect?.standardized, sel.width >= 12 else { return CGPoint(x: viewSize.width / 2, y: 44) }
        let localSel = toLocal(sel)
        let barW: CGFloat = min(560, viewSize.width - 24), barH: CGFloat = 46
        let minX = barW / 2 + 12, maxX = max(minX, viewSize.width - barW / 2 - 12)
        let x = min(max(localSel.midX, minX), maxX)
        let belowY = localSel.maxY + barH / 2 + 12, aboveY = localSel.minY - barH / 2 - 12
        if belowY + barH / 2 <= viewSize.height - 12 { return CGPoint(x: x, y: belowY) }
        if aboveY - barH / 2 >= 12 { return CGPoint(x: x, y: aboveY) }
        let minY = barH / 2 + 12, maxY = max(minY, viewSize.height - barH / 2 - 12)
        return CGPoint(x: x, y: min(max(localSel.maxY - barH / 2 - 12, minY), maxY))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: slice.image, scale: slice.scale, orientation: .up)
                .resizable().frame(width: viewSize.width, height: viewSize.height).allowsHitTesting(false)

            Path { path in
                path.addRect(CGRect(origin: .zero, size: viewSize))
                if let hole = (session.selectionRect ?? session.hoveredWindow?.frame)?.standardized {
                    let localHole = toLocal(hole).intersection(CGRect(origin: .zero, size: viewSize))
                    if !localHole.isNull && localHole.width >= 2 && localHole.height >= 2 { path.addRect(localHole) }
                }
            }
            .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))
            .frame(width: viewSize.width, height: viewSize.height).allowsHitTesting(false)

            if let sel = session.selectionRect?.standardized, sel.width >= 2, sel.height >= 2 { selectionChrome(for: sel) }
            else if let win = session.hoveredWindow { hoveredWindowChrome(for: win) }

            Color.clear.frame(width: viewSize.width, height: viewSize.height).contentShape(Rectangle())
                .onContinuousHover { if case .active(let pt) = $0 { session.updateHover(at: toCanvas(pt)) } }
                .gesture(DragGesture(minimumDistance: 0).onChanged(handleDragChanged).onEnded(handleDragEnded))

            if !session.isDragging && shouldHostToolbar { presetAndActionToolbar.position(controlBarPosition) }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading).clipped()
    }

    private func selectionChrome(for canvasRect: CGRect) -> some View {
        let rect = toLocal(canvasRect)
        let (outW, outH) = session.outputDimensions(for: canvasRect)
        let accent = Color(red: 1.0, green: 0.30, blue: 0.28)
        let winBadge = session.selectedWindow.map { "\($0.displayLabel) · " } ?? ""
        let badgeVisible = rect.minX < viewSize.width && rect.maxX > 0
        let badgeX = min(max(110, rect.minX + 100), max(110, viewSize.width - 110))
        let badgeY = rect.minY > 30 ? rect.minY - 15 : max(16, rect.minY + 16)
        return ZStack(alignment: .topLeading) {
            Rectangle().strokeBorder(accent, lineWidth: 1.8).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                Circle().fill(Color.white).overlay(Circle().strokeBorder(accent, lineWidth: 1.6)).frame(width: 9, height: 9).position(handle.point(in: rect))
            }
            if badgeVisible {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("\(winBadge)GIF \(outW)×\(outH) px · \(session.options.fps) FPS").lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4).background(.black.opacity(0.78), in: Capsule())
                .position(x: badgeX, y: min(badgeY, viewSize.height - 18))
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading).allowsHitTesting(false)
    }

    private func hoveredWindowChrome(for win: DetectedScreenWindow) -> some View {
        let rect = toLocal(win.frame)
        let subHint = session.overlappingWindowCount >= 2 ? " · Tab 切下层 (\(session.overlappingWindowCount))" : " · 单击锁定窗口录制"
        let label = (win.displayLabel.isEmpty ? "窗口" : win.displayLabel) + subHint
        let badgeVisible = rect.intersects(CGRect(origin: .zero, size: viewSize))
        let badgeX = min(max(130, rect.minX + 118), max(130, viewSize.width - 130))
        let badgeY = rect.minY > 24 ? rect.minY - 15 : max(18, rect.minY + 18)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.cyan.opacity(0.95), lineWidth: 2.2)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            if badgeVisible {
                Text(label).lineLimit(1).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.76), in: Capsule())
                    .position(x: badgeX, y: min(badgeY, viewSize.height - 18))
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading).allowsHitTesting(false)
    }

    private var presetAndActionToolbar: some View {
        let hasSelection = (session.selectionRect?.standardized.width ?? 0) >= 12
        return HStack(spacing: 8) {
            if !hasSelection {
                Text("单击锁定应用窗 (Tab 切下层) 或跨屏框选 · Esc 取消")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).padding(.leading, 4)
            }
            HStack(spacing: 3) {
                ForEach(GifRecordingOptions.fpsPresets, id: \.self) { fps in
                    presetChip("\(fps)FPS", active: session.options.fps == fps) { session.options.fps = fps }
                }
            }.padding(3).background(.white.opacity(0.08), in: Capsule())

            HStack(spacing: 3) {
                ForEach(GifRecordingOptions.dimensionPresets, id: \.self) { dim in
                    presetChip(GifRecordingOptions.dimensionLabel(for: dim), active: session.options.maxDimension == dim) { session.options.maxDimension = dim }
                }
            }.padding(3).background(.white.opacity(0.08), in: Capsule())

            Button(action: onCancel) {
                Text("取消").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
            }.buttonStyle(.plain)

            if hasSelection {
                Button(action: onStartRecording) {
                    HStack(spacing: 5) {
                        Circle().fill(.white).frame(width: 7, height: 7)
                        Text("开始录制 ⏎").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 6)
                    .background(LinearGradient(colors: [Color(red: 1.0, green: 0.27, blue: 0.25), Color(red: 0.90, green: 0.14, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule()).background(Color.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.9))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }

    private func presetChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: active ? .bold : .medium, design: .rounded))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 4).background(active ? Color.white : Color.clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        if session.activeDrag == nil {
            session.updateHover(at: canvasStart)
            session.activeDrag = resolveDragMode(at: canvasStart)
        }
        session.updateHover(at: canvasLoc)
        guard let mode = session.activeDrag else { return }
        switch mode {
        case .creating(let ctx):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: ctx.startPoint, to: canvasLoc) else { return }
            session.isDragging = true; session.selectedWindow = nil
            session.selectionRect = CaptureSelectionGeometry.rubberBandRect(from: ctx.startPoint, to: canvasLoc, clampedTo: session.screenBounds)
        case .resizing(let handle, let initial, let startPt):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: startPt, to: canvasLoc) else { return }
            session.isDragging = true; session.selectedWindow = nil
            session.selectionRect = resized(initial, handle: handle, to: canvasLoc).intersection(session.screenBounds)
        case .moving(let initial, let start):
            guard CaptureSelectionGeometry.shouldBeginDrag(from: start, to: canvasLoc) else { return }
            session.isDragging = true; session.selectedWindow = nil
            let x = min(max(0, initial.minX + canvasLoc.x - start.x), session.screenBounds.width - initial.width)
            let y = min(max(0, initial.minY + canvasLoc.y - start.y), session.screenBounds.height - initial.height)
            session.selectionRect = CGRect(origin: CGPoint(x: x, y: y), size: initial.size)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        let mode = session.activeDrag
        session.activeDrag = nil; session.isDragging = false
        if case .creating(let ctx) = mode {
            let resolution = CaptureSelectionGeometry.resolveCreationEnd(
                context: ctx, endPoint: canvasLoc, currentSelection: session.selectionRect,
                currentHoveredWindow: session.hoveredWindow, windows: session.windows, minimumSelectionSize: 12
            )
            switch resolution {
            case .snapToWindow(let win): session.selectWindow(win)
            case .commitRegion(let sel): session.selectionRect = sel; session.selectedWindow = nil
            case .restorePrevious(let prevSel, let prevWin):
                session.selectionRect = prevSel; session.selectedWindow = prevWin
                session.updateHover(at: canvasLoc)
            }
            return
        }
        if !CaptureSelectionGeometry.shouldBeginDrag(from: canvasStart, to: canvasLoc) {
            let now = Date().timeIntervalSinceReferenceDate
            if let sel = session.selectionRect, sel.contains(canvasLoc), now - session.lastClickTime < 0.32, hypot(canvasLoc.x - session.lastClickPoint.x, canvasLoc.y - session.lastClickPoint.y) < 12 {
                onStartRecording()
            }
            session.lastClickTime = now; session.lastClickPoint = canvasLoc
        }
    }

    private func resolveDragMode(at pt: CGPoint) -> GifSelectionDragMode {
        let makeCreating = {
            GifSelectionDragMode.creating(SelectionCreationContext(
                startPoint: pt, previousSelection: session.selectionRect,
                previousSelectedWindow: session.selectedWindow,
                pressHoveredWindow: session.hoveredWindow ?? session.topWindow(at: pt)
            ))
        }
        guard let sel = session.selectionRect?.standardized else { return makeCreating() }
        for h in SelectionHandle.allCases where hypot(pt.x - h.point(in: sel).x, pt.y - h.point(in: sel).y) <= 12 {
            return .resizing(h, sel, pt)
        }
        return sel.contains(pt) ? .moving(sel, pt) : makeCreating()
    }

    private func resized(_ r: CGRect, handle: SelectionHandle, to pt: CGPoint) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .topLeft: minX = min(pt.x, maxX - 16); minY = min(pt.y, maxY - 16)
        case .top: minY = min(pt.y, maxY - 16)
        case .topRight: maxX = max(pt.x, minX + 16); minY = min(pt.y, maxY - 16)
        case .right: maxX = max(pt.x, minX + 16)
        case .bottomRight: maxX = max(pt.x, minX + 16); maxY = max(pt.y, minY + 16)
        case .bottom: maxY = max(pt.y, minY + 16)
        case .bottomLeft: minX = min(pt.x, maxX - 16); maxY = max(pt.y, minY + 16)
        case .left: minX = min(pt.x, maxX - 16)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
