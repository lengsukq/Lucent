import AppKit
import LucentCore
import SwiftUI

@MainActor
final class FileShelfPanelState: ObservableObject {
    @Published var settings: FileShelfWindowSettings
    @Published var mode: FileShelfPresentationMode
    @Published var nearDockEdge: FileShelfDockEdge = .none

    init(settings: FileShelfWindowSettings, mode: FileShelfPresentationMode) {
        self.settings = settings
        self.mode = mode
    }
}

@MainActor
final class FileShelfHoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?
    override var mouseDownCanMoveWindow: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

final class UnconstrainedFileShelfHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

final class FileShelfDragNSView: NSView {
    var onTap: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragWillStart: (() -> Void)?
    var onDragMoved: ((CGRect, CGRect) -> Void)?
    var onDragEnded: ((CGRect) -> Void)?

    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 1) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
            return
        }
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var hasStartedDrag = false
        var lastVisible = activeVisibleFrame(for: window)

        while let next = NSApp.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            if next.type == .leftMouseUp {
                if hasStartedDrag {
                    onDragEnded?(lastVisible)
                } else {
                    onTap?()
                }
                return
            }

            let curMouse = NSEvent.mouseLocation
            let dx = curMouse.x - startMouse.x
            let dy = curMouse.y - startMouse.y
            if !hasStartedDrag {
                guard hypot(dx, dy) >= 3.0 else { continue }
                hasStartedDrag = true
                onDragWillStart?()
            }

            let rawOrigin = CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)
            let visible = activeVisibleFrame(for: window)
            lastVisible = visible
            let clamped = PluginWindowGeometry.clampDragOrigin(
                rawOrigin,
                size: window.frame.size,
                visibleFrame: visible,
                keepFullyOnScreen: true
            )
            window.setFrameOrigin(clamped)
            onDragMoved?(window.frame, visible)
        }

        if hasStartedDrag {
            onDragEnded?(lastVisible)
        }
    }

    private func activeVisibleFrame(for window: NSWindow) -> CGRect {
        ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

struct FileShelfDragOverlay: NSViewRepresentable {
    var onTap: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onDragWillStart: (() -> Void)? = nil
    var onDragMoved: ((CGRect, CGRect) -> Void)? = nil
    var onDragEnded: ((CGRect) -> Void)? = nil

    func makeNSView(context: Context) -> FileShelfDragNSView {
        let view = FileShelfDragNSView()
        sync(view)
        return view
    }

    func updateNSView(_ nsView: FileShelfDragNSView, context: Context) {
        sync(nsView)
    }

    private func sync(_ view: FileShelfDragNSView) {
        view.onTap = onTap
        view.onDoubleClick = onDoubleClick
        view.onDragWillStart = onDragWillStart
        view.onDragMoved = onDragMoved
        view.onDragEnded = onDragEnded
    }
}

struct FileShelfEdgeAccentOverlay: View {
    let dockedEdge: FileShelfDockEdge
    let nearDockEdge: FileShelfDockEdge
    let isExpanded: Bool

    var body: some View {
        ZStack {
            if isExpanded && dockedEdge != .none && nearDockEdge == .none {
                edgeBar(edge: dockedEdge, width: 2.5, opacity: 0.72, glowWidth: 0)
            }
            if nearDockEdge != .none {
                edgeBar(edge: nearDockEdge, width: 3.5, opacity: 0.96, glowWidth: 26)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeBar(edge: FileShelfDockEdge, width: CGFloat, opacity: Double, glowWidth: CGFloat) -> some View {
        if edge == .top {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if glowWidth > 0 {
                        LinearGradient(
                            colors: [Color.teal.opacity(0.28), Color.teal.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: glowWidth)
                    }
                    Rectangle()
                        .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .leading, endPoint: .trailing))
                        .opacity(opacity)
                        .frame(height: width)
                }
                Spacer(minLength: 0)
            }
        } else {
            let isLeft = edge == .left
            HStack(spacing: 0) {
                if !isLeft { Spacer(minLength: 0) }
                ZStack(alignment: isLeft ? .leading : .trailing) {
                    if glowWidth > 0 {
                        LinearGradient(
                            colors: [Color.teal.opacity(0.28), Color.teal.opacity(0.0)],
                            startPoint: isLeft ? .leading : .trailing,
                            endPoint: isLeft ? .trailing : .leading
                        )
                        .frame(width: glowWidth)
                    }
                    Rectangle()
                        .fill(LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom))
                        .opacity(opacity)
                        .frame(width: width)
                }
                if isLeft { Spacer(minLength: 0) }
            }
        }
    }
}
