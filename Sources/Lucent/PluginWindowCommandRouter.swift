import AppKit
import Foundation
import LucentCore
import QuartzCore

@MainActor
extension PluginWindowMotionSession {
    func handleCommand(_ body: [String: Any], plugin: PluginDescriptor) -> [String: Any] {
        guard let win = window, let cmd = body["cmd"] as? String else { return ["ok": false] }
        switch cmd {
        case "getFrame":
            return snapshotPayload(for: win)
        case "startDrag":
            beginNativeMouseDrag(for: win)
            return ["ok": true]
        case "setEdgeBehavior":
            return applyEdgeBehavior(body)
        case "resize":
            return handleResize(body, window: win)
        case "moveTo":
            return handleMoveTo(body, window: win)
        case "animateFrame":
            return handleAnimateFrame(body, window: win)
        case "morph":
            return handleMorph(body, window: win)
        case "snapToEdge":
            return handleSnapToEdge(body, window: win)
        case "setPinned":
            guard plugin.grantedCapabilities.contains(.floatingWindow) else {
                return ["ok": false, "error": "floatingWindow_not_granted"]
            }
            let pinned = (body["pinned"] as? Bool) ?? true
            WindowLevelStore.shared.setPinned(pinned, forKey: windowKey)
            PluginCustomWebWindowController.shared.persistCanvasFrame(forKey: windowKey)
            return ["ok": true, "pinned": pinned]
        case "setShowInDock":
            let enabled = (body["enabled"] as? Bool) ?? false
            PluginCustomWebWindowController.shared.setShowInDock(enabled, forKey: windowKey)
            return ["ok": true, "showInDock": enabled]
        case "setClickThrough":
            guard plugin.grantedCapabilities.contains(.floatingWindow) else {
                return ["ok": false, "error": "floatingWindow_not_granted"]
            }
            let enabled = (body["enabled"] as? Bool) ?? false
            win.ignoresMouseEvents = enabled
            return ["ok": true, "clickThrough": enabled]
        case "setOpacity":
            return handleSetOpacity(body, window: win)
        case "resetFrame":
            PluginCustomWebWindowController.shared.resetCanvasToDefaults(forKey: windowKey, plugin: plugin)
            notifyNativeFrameChanged(settled: true)
            return snapshotPayload(for: win)
        case "minimize":
            win.miniaturize(nil)
            return ["ok": true]
        case "close":
            let key = windowKey
            DispatchQueue.main.async {
                _ = PluginCustomWebWindowController.shared.closeByKey(key)
            }
            return ["ok": true]
        default:
            return ["ok": false, "error": "unknown_window_cmd"]
        }
    }

    private func applyEdgeBehavior(_ body: [String: Any]) -> [String: Any] {
        if let keep = body["keepOnScreen"] as? Bool { keepOnScreen = keep }
        if let clampDrag = body["autoClampOnDrag"] as? Bool { autoClampOnDrag = clampDrag }
        if let rawThreshold = (body["edgeThreshold"] as? NSNumber)?.doubleValue {
            edgeThreshold = min(max(PluginWindowGeometry.finiteDouble(rawThreshold, fallback: edgeThreshold), 0), 240)
        }
        return [
            "ok": true,
            "keepOnScreen": keepOnScreen,
            "autoClampOnDrag": autoClampOnDrag,
            "edgeThreshold": edgeThreshold
        ]
    }

    private func handleResize(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        let rawW = PluginWindowGeometry.finiteDouble((body["width"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.width))
        let rawH = PluginWindowGeometry.finiteDouble((body["height"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.height))
        let size = PluginWindowGeometry.clampSize(width: CGFloat(rawW), height: CGFloat(rawH), allowCompactFloating: allowCompactFloating)
        let anchor = (body["anchor"] as? String).flatMap(PluginWindowAnchor.init(rawValue:)) ?? .topLeft
        let target = PluginWindowGeometry.anchoredFrame(current: win.frame, targetSize: size, anchor: anchor)
        let animate = (body["animate"] as? Bool) ?? true
        let durationMs = animate ? PluginWindowGeometry.clampDurationMs((body["durationMs"] as? NSNumber)?.doubleValue) : 0
        let easing = (body["easing"] as? String).flatMap(PluginWindowEasing.init(rawValue:)) ?? .spring
        let clamp = (body["keepOnScreen"] as? Bool) ?? keepOnScreen
        let applied = applyFrame(window: win, target: target, durationMs: durationMs, easing: easing, keepOnScreen: clamp)
        return targetPayload(for: applied, window: win)
    }

    private func handleMoveTo(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        let x = PluginWindowGeometry.finiteDouble((body["x"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.origin.x))
        let y = PluginWindowGeometry.finiteDouble((body["y"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.origin.y))
        let target = CGRect(origin: CGPoint(x: x, y: y), size: win.frame.size)
        let animate = (body["animate"] as? Bool) ?? false
        let durationMs = animate ? PluginWindowGeometry.clampDurationMs((body["durationMs"] as? NSNumber)?.doubleValue) : 0
        let easing = (body["easing"] as? String).flatMap(PluginWindowEasing.init(rawValue:)) ?? .spring
        let clamp = (body["keepOnScreen"] as? Bool) ?? keepOnScreen
        let applied = applyFrame(window: win, target: target, durationMs: durationMs, easing: easing, keepOnScreen: clamp)
        return targetPayload(for: applied, window: win)
    }

    private func handleAnimateFrame(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        let rawW = PluginWindowGeometry.finiteDouble((body["width"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.width))
        let rawH = PluginWindowGeometry.finiteDouble((body["height"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.height))
        let size = PluginWindowGeometry.clampSize(width: CGFloat(rawW), height: CGFloat(rawH), allowCompactFloating: allowCompactFloating)
        let anchor = (body["anchor"] as? String).flatMap(PluginWindowAnchor.init(rawValue:)) ?? .topLeft
        var target = PluginWindowGeometry.anchoredFrame(current: win.frame, targetSize: size, anchor: anchor)
        if let xNum = body["x"] as? NSNumber, xNum.doubleValue.isFinite { target.origin.x = CGFloat(xNum.doubleValue) }
        if let yNum = body["y"] as? NSNumber, yNum.doubleValue.isFinite { target.origin.y = CGFloat(yNum.doubleValue) }
        let durationMs = PluginWindowGeometry.clampDurationMs((body["durationMs"] as? NSNumber)?.doubleValue)
        let easing = (body["easing"] as? String).flatMap(PluginWindowEasing.init(rawValue:)) ?? .spring
        let clamp = (body["keepOnScreen"] as? Bool) ?? keepOnScreen
        let applied = applyFrame(window: win, target: target, durationMs: durationMs, easing: easing, keepOnScreen: clamp)
        return targetPayload(for: applied, window: win)
    }

    private func handleMorph(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        var copy = body
        if copy["anchor"] == nil { copy["anchor"] = PluginWindowAnchor.topRight.rawValue }
        return handleAnimateFrame(copy, window: win)
    }

    private func handleSnapToEdge(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        let screen = PluginWindowGeometry.bestScreen(for: win.frame, screens: Self.currentScreens())
        let rawEdge = (body["edge"] as? String)?.lowercased() ?? "nearest"
        let edge: PluginWindowEdge
        if rawEdge == "nearest" {
            edge = PluginWindowGeometry.computeEdgeMetrics(frame: win.frame, visibleFrame: screen.visibleFrame).nearestEdge
        } else if let parsed = PluginWindowEdge(rawValue: rawEdge) {
            edge = parsed
        } else {
            return ["ok": false, "error": "invalid_edge"]
        }
        var targetSize: CGSize?
        if body["width"] != nil || body["height"] != nil {
            let rawW = PluginWindowGeometry.finiteDouble((body["width"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.width))
            let rawH = PluginWindowGeometry.finiteDouble((body["height"] as? NSNumber)?.doubleValue, fallback: Double(win.frame.height))
            targetSize = PluginWindowGeometry.clampSize(width: CGFloat(rawW), height: CGFloat(rawH), allowCompactFloating: allowCompactFloating)
        }
        let margin = CGFloat(min(max(PluginWindowGeometry.finiteDouble((body["margin"] as? NSNumber)?.doubleValue, fallback: 8), 0), 120))
        let target = PluginWindowGeometry.snappedFrame(
            current: win.frame, targetSize: targetSize, edge: edge, margin: margin, visibleFrame: screen.visibleFrame
        )
        let durationMs = PluginWindowGeometry.clampDurationMs((body["durationMs"] as? NSNumber)?.doubleValue ?? 240)
        let easing = (body["easing"] as? String).flatMap(PluginWindowEasing.init(rawValue:)) ?? .spring
        let applied = applyFrame(window: win, target: target, durationMs: durationMs, easing: easing, keepOnScreen: true)
        return targetPayload(for: applied, window: win, extra: ["snappedEdge": edge.rawValue])
    }

    private func handleSetOpacity(_ body: [String: Any], window win: NSWindow) -> [String: Any] {
        let raw = PluginWindowGeometry.finiteDouble((body["opacity"] as? NSNumber)?.doubleValue, fallback: Double(win.alphaValue))
        let clamped = min(max(raw, PluginCustomWindowSpec.minOpacity), 1.0)
        let animate = (body["animate"] as? Bool) ?? false
        let durationMs = animate ? PluginWindowGeometry.clampDurationMs((body["durationMs"] as? NSNumber)?.doubleValue ?? 180) : 0
        if durationMs > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = durationMs / 1000.0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = clamped
            }
        } else {
            win.alphaValue = clamped
        }
        PluginCustomWebWindowController.shared.persistCanvasFrame(forKey: windowKey)
        return ["ok": true, "opacity": clamped]
    }
}
