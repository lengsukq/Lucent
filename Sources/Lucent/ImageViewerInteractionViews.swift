import AppKit
import SwiftUI

struct AnimatedOrStaticImageRepresentable: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
    }
}

struct ImageCanvasInteractionOverlay: NSViewRepresentable {
    let canPan: Bool
    let onScrollZoom: (CGFloat) -> Void
    let onPanDelta: (CGFloat, CGFloat) -> Void
    let onDoubleClick: () -> Void
    let onKeyCommand: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ImageCanvasInteractionNSView {
        let view = ImageCanvasInteractionNSView()
        sync(view)
        view.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: ImageCanvasInteractionNSView, context: Context) {
        sync(nsView)
        nsView.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: ImageCanvasInteractionNSView, coordinator: ()) {
        nsView.removeMonitor()
    }

    private func sync(_ view: ImageCanvasInteractionNSView) {
        view.canPan = canPan
        view.onScrollZoom = onScrollZoom
        view.onPanDelta = onPanDelta
        view.onDoubleClick = onDoubleClick
        view.onKeyCommand = onKeyCommand
    }
}

@MainActor
final class ImageCanvasInteractionNSView: NSView {
    var canPan: Bool = false {
        didSet { if oldValue != canPan { window?.invalidateCursorRects(for: self) } }
    }
    var onScrollZoom: ((CGFloat) -> Void)?
    var onPanDelta: ((CGFloat, CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onKeyCommand: ((NSEvent) -> Bool)?

    private var isDragging = false
    private var lastDragPoint: NSPoint = .zero
    nonisolated(unsafe) private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? removeMonitor() : installMonitorIfNeeded()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if canPan {
            addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        guard canPan else { return }
        isDragging = true
        lastDragPoint = convert(event.locationInWindow, from: nil)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, canPan else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let dx = pt.x - lastDragPoint.x
        let dy = pt.y - lastDragPoint.y
        lastDragPoint = pt
        onPanDelta?(dx, dy)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            window?.invalidateCursorRects(for: self)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 12
        guard abs(dy) > 0.2 else { return }
        if canPan && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) && event.hasPreciseScrollingDeltas {
            onPanDelta?(event.scrollingDeltaX, -event.scrollingDeltaY)
            return
        }
        let step = min(max(dy * 0.0045, -0.22), 0.22)
        onScrollZoom?(1.0 + step)
    }

    override func magnify(with event: NSEvent) {
        let factor = max(0.5, min(1.8, 1.0 + event.magnification))
        onScrollZoom?(factor)
    }

    func installMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let targetWin = self.window,
                  event.window === targetWin,
                  targetWin.isKeyWindow,
                  targetWin.attachedSheet == nil else { return event }
            if let resp = targetWin.firstResponder, resp is NSText || resp is NSTextField {
                return event
            }
            return self.onKeyCommand?(event) == true ? nil : event
        }
    }

    func removeMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
