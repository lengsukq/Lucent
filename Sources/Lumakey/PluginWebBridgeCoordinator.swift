import AppKit
import Foundation
import LumakeyCore
import WebKit

@MainActor
final class PluginWebBridgeCoordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let pluginID: String
    let windowKey: String
    private weak var viewModel: AppViewModel?
    private weak var window: NSWindow?
    private var dragMonitors: [Any] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(pluginID: String, windowKey: String, viewModel: AppViewModel, window: NSWindow) {
        self.pluginID = pluginID
        self.windowKey = windowKey
        self.viewModel = viewModel
        self.window = window
        super.init()
    }

    func tearDown(webView: WKWebView?) {
        stopDragTracking()
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: PluginWebSDKBootstrap.handlerName)
        webView?.navigationDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["file", "about", "data", "blob"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        if ["lumakey", "http", "https"].contains(scheme) {
            viewModel?.handlePluginOpenURL(url)
        }
        decisionHandler(.cancel)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "Invalid bridge message")
            return
        }
        guard let vm = viewModel, let currentPlugin = vm.plugins.first(where: { $0.id == pluginID }) else {
            replyHandler(nil, "Plugin '\(pluginID)' is unavailable")
            return
        }

        switch op {
        case "win":
            replyHandler(handleWindowCommand(body, plugin: currentPlugin), nil)
        case "openURL":
            if let raw = body["url"] as? String, let url = URL(string: raw) {
                vm.handlePluginOpenURL(url)
                replyHandler(["ok": true], nil)
            } else {
                replyHandler(["ok": false, "error": "invalid_url"], nil)
            }
        case "permStatus":
            replyHandler([
                "ok": true,
                "declaredCapabilities": currentPlugin.declaredCapabilities.map(\.rawValue),
                "grantedCapabilities": currentPlugin.grantedCapabilities.map(\.rawValue).sorted(),
                "systemTCC": PluginHostTCCBroker.allTCCSnapshot()
            ], nil)
        case "permRequest":
            replyHandler(handlePermissionRequest(body, plugin: currentPlugin, vm: vm), nil)
        case "run":
            runPluginBackend(body: body, plugin: currentPlugin, vm: vm, replyHandler: replyHandler)
        case "bridge":
            dispatchBridgeCall(body: body, plugin: currentPlugin, vm: vm, replyHandler: replyHandler)
        default:
            replyHandler(nil, "Unsupported op '\(op)'")
        }
    }

    private func handlePermissionRequest(_ body: [String: Any], plugin: PluginDescriptor, vm: AppViewModel) -> [String: Any] {
        guard let rawCap = body["capability"] as? String, let cap = PluginCapability(rawValue: rawCap) else {
            return ["ok": false, "error": "invalid_capability"]
        }
        guard plugin.declaredCapabilities.contains(cap) else {
            return ["ok": false, "error": "capability_not_declared", "message": "plugin.json 未声明 '\(cap.rawValue)'"]
        }
        if !plugin.grantedCapabilities.contains(cap) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = L10n.pick("允许「\(plugin.displayName)」使用「\(cap.title)」权限？", "Allow '\(plugin.displayName)' to use '\(cap.title)'?")
            alert.informativeText = "\(cap.summary)\n\n\(cap.tccNote)"
            alert.addButton(withTitle: L10n.pick("始终允许", "Allow"))
            alert.addButton(withTitle: L10n.pick("拒绝", "Deny"))
            guard alert.runModal() == .alertFirstButtonReturn else {
                return ["ok": false, "granted": false, "error": "user_denied"]
            }
            try? vm.setPluginCapabilityGranted(plugin, capability: cap, granted: true)
        }
        var tccGranted = true
        var settingsURL = ""
        if let tcc = PluginHostTCCBroker.requiredTCC(for: cap) {
            tccGranted = PluginHostTCCBroker.requestAccessOnBehalfOfPlugin(tcc).isGranted
            settingsURL = tcc.systemSettingsURLString
        }
        return ["ok": true, "capability": cap.rawValue, "granted": true, "tccGranted": tccGranted, "settingsURL": settingsURL]
    }

    private func handleWindowCommand(_ body: [String: Any], plugin: PluginDescriptor) -> [String: Any] {
        guard let win = window, let cmd = body["cmd"] as? String else { return ["ok": false] }
        switch cmd {
        case "startDrag":
            beginNativeMouseDrag(for: win)
            return ["ok": true]
        case "resize":
            let w = PluginCustomWindowSpec.clampWidth((body["width"] as? NSNumber)?.intValue ?? Int(win.frame.width))
            let h = PluginCustomWindowSpec.clampHeight((body["height"] as? NSNumber)?.intValue ?? Int(win.frame.height))
            var frame = win.frame
            frame.origin.y += (frame.height - CGFloat(h))
            frame.size = NSSize(width: w, height: h)
            win.setFrame(frame, display: true, animate: (body["animate"] as? Bool) ?? true)
            return ["ok": true, "width": w, "height": h]
        case "moveTo":
            let x = CGFloat((body["x"] as? NSNumber)?.doubleValue ?? Double(win.frame.origin.x))
            let y = CGFloat((body["y"] as? NSNumber)?.doubleValue ?? Double(win.frame.origin.y))
            win.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: win.frame.size), display: true, animate: (body["animate"] as? Bool) ?? false)
            return ["ok": true]
        case "setPinned":
            guard plugin.grantedCapabilities.contains(.floatingWindow) else {
                return ["ok": false, "error": "floatingWindow_not_granted"]
            }
            let pinned = (body["pinned"] as? Bool) ?? true
            WindowLevelStore.shared.setPinned(pinned, forKey: windowKey)
            return ["ok": true, "pinned": pinned]
        case "setClickThrough":
            guard plugin.grantedCapabilities.contains(.floatingWindow) else {
                return ["ok": false, "error": "floatingWindow_not_granted"]
            }
            let enabled = (body["enabled"] as? Bool) ?? false
            win.ignoresMouseEvents = enabled
            return ["ok": true, "clickThrough": enabled]
        case "setOpacity":
            let raw = (body["opacity"] as? NSNumber)?.doubleValue ?? 1.0
            let clamped = min(max(raw, PluginCustomWindowSpec.minOpacity), 1.0)
            win.alphaValue = clamped
            return ["ok": true, "opacity": clamped]
        case "minimize":
            win.miniaturize(nil)
            return ["ok": true]
        case "close":
            win.close()
            return ["ok": true]
        default:
            return ["ok": false, "error": "unknown_window_cmd"]
        }
    }

    private func beginNativeMouseDrag(for win: NSWindow) {
        stopDragTracking()
        let startMouse = NSEvent.mouseLocation
        let startOrigin = win.frame.origin
        let dragMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak win] ev in
            guard let win else { return ev }
            let cur = NSEvent.mouseLocation
            win.setFrameOrigin(NSPoint(x: startOrigin.x + (cur.x - startMouse.x), y: startOrigin.y + (cur.y - startMouse.y)))
            return ev
        })
        if let dragMon { dragMonitors.append(dragMon) }
        let upMon = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] ev in
            self?.stopDragTracking()
            return ev
        })
        if let upMon { dragMonitors.append(upMon) }
    }

    private func stopDragTracking() {
        for mon in dragMonitors { NSEvent.removeMonitor(mon) }
        dragMonitors.removeAll()
    }

    private func runPluginBackend(
        body: [String: Any], plugin: PluginDescriptor, vm: AppViewModel,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let args = (body["args"] as? [String]) ?? []
        let query = (body["query"] as? String) ?? ""
        let clipText = NSPasteboard.general.string(forType: .string) ?? ""
        let bridgeCtx = vm.makePluginBridgeContext()
        let id = UUID()
        activeTasks[id] = Task { [weak self] in
            defer { self?.activeTasks.removeValue(forKey: id) }
            do {
                let res = try await PluginSystem.runPluginAsync(
                    plugin, query: query, clipboardText: clipText, arguments: args, hostContext: bridgeCtx
                )
                guard !Task.isCancelled else { return }
                if let eff = res.viewPayload?.effect {
                    vm.applyPluginPostActionEffect(eff, sourcePlugin: plugin, fromFloatingPanel: true)
                }
                let jsonObj = res.execution.stdout.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
                replyHandler([
                    "ok": res.execution.exitCode == 0, "exitCode": res.execution.exitCode,
                    "stdout": res.execution.stdout, "stderr": res.execution.stderr,
                    "durationMs": res.execution.durationMs, "data": jsonObj ?? NSNull()
                ], nil)
            } catch {
                guard !Task.isCancelled else { return }
                replyHandler(["ok": false, "error": error.localizedDescription], nil)
            }
        }
    }

    private func dispatchBridgeCall(
        body: [String: Any], plugin: PluginDescriptor, vm: AppViewModel,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let rawCap = body["capability"] as? String, let cap = PluginCapability(rawValue: rawCap) else {
            replyHandler(PluginHostBridgeHandlers.errorJSON("invalid_capability", "未知 capability"), nil)
            return
        }
        let action = (body["action"] as? String) ?? ""
        let params = (body["params"] as? [String: Any]) ?? [:]
        let isDeclared = plugin.declaredCapabilities.contains(cap) || (cap == .window && plugin.declaredCapabilities.contains(.floatingWindow))
        guard isDeclared else {
            replyHandler(PluginHostBridgeHandlers.errorJSON("capability_not_declared", "plugin.json 未声明 '\(cap.rawValue)'", capability: cap), nil)
            return
        }
        let isGranted = plugin.grantedCapabilities.contains(cap) || (cap == .window && plugin.grantedCapabilities.contains(.floatingWindow))
        guard isGranted else {
            replyHandler(PluginHostBridgeHandlers.errorJSON("capability_not_granted", "插件尚未获授 '\(cap.rawValue)'，可调用 lumakey.permissions.request('\(cap.rawValue)')", capability: cap), nil)
            return
        }
        let paramsData = (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8)
        let ctx = vm.makePluginBridgeContext().scoped(to: plugin)
        let id = UUID()
        activeTasks[id] = Task { [weak self] in
            defer { self?.activeTasks.removeValue(forKey: id) }
            let outData = await Task.detached(priority: .userInitiated) { () -> Data in
                let decodedParams = (try? JSONSerialization.jsonObject(with: paramsData) as? [String: Any]) ?? [:]
                let resp = PluginHostBridgeHandlers.dispatch(capability: cap, action: action, params: decodedParams, hostContext: ctx)
                return (try? JSONSerialization.data(withJSONObject: resp)) ?? Data("{}".utf8)
            }.value
            guard !Task.isCancelled else { return }
            let outObj = (try? JSONSerialization.jsonObject(with: outData)) ?? ["ok": false]
            replyHandler(outObj, nil)
        }
    }
}
