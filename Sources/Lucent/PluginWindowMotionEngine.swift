import AppKit
import Foundation
import LucentCore
import QuartzCore
import WebKit

@MainActor
final class PluginWindowMotionSession {
    let windowKey: String
    let allowCompactFloating: Bool
    weak var window: NSWindow?
    private weak var webView: WKWebView?
    private var dragMonitors: [Any] = []
    var keepOnScreen: Bool = true
    var autoClampOnDrag: Bool = true
    var edgeThreshold: Double = PluginWindowGeometry.defaultEdgeThreshold
    private var animationGeneration: UInt64 = 0
    private var lastDragMoveDispatch: CFTimeInterval = 0
    private var lastFrameChangeDispatch: CFTimeInterval = 0
    private var lastNearEdge: PluginWindowEdge?

    init(windowKey: String, allowCompactFloating: Bool, window: NSWindow) {
        self.windowKey = windowKey
        self.allowCompactFloating = allowCompactFloating
        self.window = window
    }

    func bind(webView: WKWebView) {
        self.webView = webView
    }

    func tearDown() {
        animationGeneration &+= 1
        stopDragTracking(persist: false, dispatchEnd: false, startOrigin: nil)
        webView = nil
    }

    static func currentScreens() -> [PluginWindowScreenRect] {
        let main = NSScreen.main
        return NSScreen.screens.map { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return PluginWindowScreenRect(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                displayID: num?.uint32Value ?? 0,
                isMain: screen == main
            )
        }
    }

    func snapshotPayload(for win: NSWindow, extra: [String: Any] = [:]) -> [String: Any] {
        let screen = PluginWindowGeometry.bestScreen(for: win.frame, screens: Self.currentScreens())
        var merged = extra
        merged["opacity"] = Double(win.alphaValue)
        merged["pinned"] = WindowLevelStore.shared.isPinned(windowKey)
        merged["clickThrough"] = win.ignoresMouseEvents
        return PluginWindowGeometry.framePayload(
            frame: win.frame,
            screen: screen,
            edgeThreshold: edgeThreshold,
            extra: merged
        )
    }

    func targetPayload(for target: CGRect, window win: NSWindow, extra: [String: Any] = [:]) -> [String: Any] {
        let screen = PluginWindowGeometry.bestScreen(for: target, screens: Self.currentScreens())
        var merged = extra
        merged["opacity"] = Double(win.alphaValue)
        merged["pinned"] = WindowLevelStore.shared.isPinned(windowKey)
        merged["clickThrough"] = win.ignoresMouseEvents
        return PluginWindowGeometry.framePayload(
            frame: target,
            screen: screen,
            edgeThreshold: edgeThreshold,
            extra: merged
        )
    }

    func notifyNativeFrameChanged(settled: Bool = false) {
        guard let win = window else { return }
        let now = CACurrentMediaTime()
        if !settled && now - lastFrameChangeDispatch < 0.016 { return }
        lastFrameChangeDispatch = now
        dispatchEvent("lucent:frameChanged", payload: snapshotPayload(for: win, extra: ["settled": settled]))
    }

    func applyFrame(
        window win: NSWindow,
        target rawTarget: CGRect,
        durationMs: Double,
        easing: PluginWindowEasing,
        keepOnScreen: Bool
    ) -> CGRect {
        let screen = PluginWindowGeometry.bestScreen(for: rawTarget, screens: Self.currentScreens())
        let finalFrame = keepOnScreen
            ? PluginWindowGeometry.clampFrameToVisible(rawTarget, visibleFrame: screen.visibleFrame, margin: 0)
            : rawTarget

        if allowCompactFloating {
            win.minSize = NSSize(
                width: max(PluginWindowGeometry.minFloatingWidth, min(win.minSize.width, finalFrame.width)),
                height: max(PluginWindowGeometry.minFloatingHeight, min(win.minSize.height, finalFrame.height))
            )
        }

        animationGeneration &+= 1
        let gen = animationGeneration
        let effectiveMs = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : durationMs
        if effectiveMs <= 0 {
            win.setFrame(finalFrame, display: true, animate: false)
            PluginCustomWebWindowController.shared.persistCanvasFrame(forKey: windowKey)
            notifyNativeFrameChanged(settled: true)
            return finalFrame
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = effectiveMs / 1000.0
            ctx.timingFunction = Self.timingFunction(for: easing)
            ctx.allowsImplicitAnimation = true
            win.animator().setFrame(finalFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == gen else { return }
                PluginCustomWebWindowController.shared.persistCanvasFrame(forKey: self.windowKey)
                self.notifyNativeFrameChanged(settled: true)
            }
        })
        return finalFrame
    }

    func beginNativeMouseDrag(for win: NSWindow) {
        stopDragTracking(persist: false, dispatchEnd: false, startOrigin: nil)
        let startMouse = NSEvent.mouseLocation
        let startOrigin = win.frame.origin
        lastNearEdge = nil
        dispatchEvent("lucent:dragStart", payload: snapshotPayload(for: win))

        let dragMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self, weak win] ev in
            guard let self, let win else { return ev }
            let cur = NSEvent.mouseLocation
            let rawOrigin = CGPoint(x: startOrigin.x + (cur.x - startMouse.x), y: startOrigin.y + (cur.y - startMouse.y))
            let activeVis = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
                ?? PluginWindowGeometry.bestScreen(
                    for: CGRect(origin: rawOrigin, size: win.frame.size),
                    screens: Self.currentScreens()
                ).visibleFrame
            let nextOrigin = self.autoClampOnDrag
                ? PluginWindowGeometry.clampDragOrigin(
                    rawOrigin, size: win.frame.size, visibleFrame: activeVis, keepFullyOnScreen: self.keepOnScreen
                )
                : rawOrigin
            win.setFrameOrigin(nextOrigin)
            self.emitDragMoveEvents(for: win, visibleFrame: activeVis)
            return ev
        })
        if let dragMon { dragMonitors.append(dragMon) }

        let upMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] ev in
            self?.stopDragTracking(persist: true, dispatchEnd: true, startOrigin: startOrigin)
            return ev
        })
        if let upMon { dragMonitors.append(upMon) }
    }

    private func emitDragMoveEvents(for win: NSWindow, visibleFrame: CGRect) {
        let metrics = PluginWindowGeometry.computeEdgeMetrics(frame: win.frame, visibleFrame: visibleFrame)
        let near = metrics.edgeWithin(threshold: edgeThreshold)
        if near != lastNearEdge {
            lastNearEdge = near
            dispatchEvent("lucent:edgeProximity", payload: snapshotPayload(for: win, extra: ["edge": near?.rawValue ?? NSNull()]))
        }
        let now = CACurrentMediaTime()
        if now - lastDragMoveDispatch >= 0.016 {
            lastDragMoveDispatch = now
            let payload = snapshotPayload(for: win)
            dispatchEvent("lucent:dragMove", payload: payload)
            dispatchEvent("lucent:frameChanged", payload: payload)
        }
    }

    private func stopDragTracking(persist: Bool, dispatchEnd: Bool, startOrigin: CGPoint?) {
        let hadMonitors = !dragMonitors.isEmpty
        for mon in dragMonitors { NSEvent.removeMonitor(mon) }
        dragMonitors.removeAll()
        guard hadMonitors else { return }
        if persist {
            PluginCustomWebWindowController.shared.persistCanvasFrame(forKey: windowKey)
        }
        if dispatchEnd, let win = window {
            let movedDist = startOrigin.map {
                hypot(Double(win.frame.origin.x - $0.x), Double(win.frame.origin.y - $0.y)).rounded()
            } ?? 0
            var extra: [String: Any] = ["movedDistance": movedDist]
            if let near = lastNearEdge { extra["edge"] = near.rawValue }
            let payload = snapshotPayload(for: win, extra: extra)
            lastNearEdge = nil
            dispatchEvent("lucent:dragEnd", payload: payload)
            dispatchEvent("lucent:frameChanged", payload: payload)
        }
    }

    func dispatchEvent(_ name: String, payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__lucentDispatchWindowEvent && window.__lucentDispatchWindowEvent(\"\(name)\", \(json));")
    }

    private static func timingFunction(for easing: PluginWindowEasing) -> CAMediaTimingFunction {
        switch easing {
        case .spring: CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut: CAMediaTimingFunction(name: .easeInEaseOut)
        case .linear: CAMediaTimingFunction(name: .linear)
        }
    }
}
