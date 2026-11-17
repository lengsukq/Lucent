import AppKit
import CoreGraphics
import LumakeyCore
import SwiftUI

enum GifSelectionDragMode {
    case creating(CGPoint)
    case resizing(SelectionHandle, CGRect)
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
        let hits = windows.filter { $0.frame.contains(clamped) }
        overlappingWindowCount = hits.count
        if hits.first?.id != lastTopHitWindowID { lastTopHitWindowID = hits.first?.id; windowCycleIndex = 0 }
        hoveredWindow = hits.isEmpty ? nil : hits[windowCycleIndex % hits.count]
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
        selectedWindow = win; selectionRect = win.frame; hoveredWindow = nil
    }

    func outputDimensions(for rect: CGRect) -> (Int, Int) {
        let scale = topology.effectiveScale(forSelection: rect)
        let rawW = max(2, Int((rect.width * scale).rounded()))
        let rawH = max(2, Int((rect.height * scale).rounded()))
        return GifStreamEncoder.scaledDimensions(width: rawW, height: rawH, maxDimension: options.maxDimension)
    }

    func appKitScreenRect(for canvasRect: CGRect) -> NSRect { topology.appKitGlobalRect(fromCanvas: canvasRect) }
}

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
        guard let sel = session.selectionRect?.standardized else { return CGPoint(x: viewSize.width / 2, y: 44) }
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
                    if !localHole.isNull && localHole.width > 0 && localHole.height > 0 { path.addRect(localHole) }
                }
            }
            .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))
            .frame(width: viewSize.width, height: viewSize.height).allowsHitTesting(false)

            if let sel = session.selectionRect?.standardized { selectionChrome(for: sel) }
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
        session.updateHover(at: canvasLoc)
        if session.activeDrag == nil { session.activeDrag = resolveDragMode(at: canvasStart) }
        guard let mode = session.activeDrag else { return }
        if hypot(canvasLoc.x - canvasStart.x, canvasLoc.y - canvasStart.y) >= 2 { session.isDragging = true }
        switch mode {
        case .creating(let startPt):
            if session.isDragging { session.selectedWindow = nil }
            session.selectionRect = CGRect(x: min(startPt.x, canvasLoc.x), y: min(startPt.y, canvasLoc.y), width: abs(canvasLoc.x - startPt.x), height: abs(canvasLoc.y - startPt.y)).intersection(session.screenBounds)
        case .resizing(let handle, let initial):
            if session.isDragging { session.selectedWindow = nil }
            session.selectionRect = resized(initial, handle: handle, to: canvasLoc).intersection(session.screenBounds)
        case .moving(let initial, let start):
            if session.isDragging { session.selectedWindow = nil }
            let x = min(max(0, initial.minX + canvasLoc.x - start.x), session.screenBounds.width - initial.width)
            let y = min(max(0, initial.minY + canvasLoc.y - start.y), session.screenBounds.height - initial.height)
            session.selectionRect = CGRect(origin: CGPoint(x: x, y: y), size: initial.size)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let canvasLoc = toCanvas(value.location), canvasStart = toCanvas(value.startLocation)
        session.activeDrag = nil; session.isDragging = false
        if hypot(canvasLoc.x - canvasStart.x, canvasLoc.y - canvasStart.y) < 3 {
            if session.selectionRect == nil, let win = session.hoveredWindow { session.selectWindow(win); return }
            let now = Date().timeIntervalSinceReferenceDate
            if let sel = session.selectionRect, sel.contains(canvasLoc), now - session.lastClickTime < 0.32, hypot(canvasLoc.x - session.lastClickPoint.x, canvasLoc.y - session.lastClickPoint.y) < 12 {
                onStartRecording()
            }
            session.lastClickTime = now; session.lastClickPoint = canvasLoc
            return
        }
        if let sel = session.selectionRect, (sel.width < 12 || sel.height < 12), let win = session.hoveredWindow { session.selectWindow(win) }
    }

    private func resolveDragMode(at pt: CGPoint) -> GifSelectionDragMode {
        guard let sel = session.selectionRect?.standardized else { return .creating(pt) }
        for h in SelectionHandle.allCases where hypot(pt.x - h.point(in: sel).x, pt.y - h.point(in: sel).y) <= 12 { return .resizing(h, sel) }
        return sel.contains(pt) ? .moving(sel, pt) : .creating(pt)
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
