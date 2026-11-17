import AppKit
import Foundation
import LumakeyCore
import SwiftUI
import WebKit

private final class PluginFramelessCanvasWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class PluginHUDCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PluginCustomWebWindowController: NSObject, NSWindowDelegate {
    static let shared = PluginCustomWebWindowController()

    private struct ManagedCanvas {
        let pluginID: String
        let windowID: String
        let spec: PluginCustomWindowSpec
        let window: NSWindow
        let webView: WKWebView?
        let coordinator: PluginWebBridgeCoordinator?
    }

    private var activeCanvases: [String: ManagedCanvas] = [:]
    var onWindowVisibilityChanged: (() -> Void)?

    private override init() { super.init() }

    var hasStandardWindows: Bool {
        activeCanvases.values.contains { $0.spec.chrome != .hud && $0.window.isVisible }
    }

    var activeWindowCount: Int { activeCanvases.count }

    @discardableResult
    func open(spec rawSpec: PluginCustomWindowSpec, viewModel: AppViewModel) -> Bool {
        guard let plugin = viewModel.plugins.first(where: { $0.id == rawSpec.pluginID }),
              plugin.isBuiltin || plugin.isEnabled else {
            viewModel.serviceMessage = L10n.pick("未找到可用插件 '\(rawSpec.pluginID)'", "Plugin '\(rawSpec.pluginID)' not available")
            return false
        }
        let spec = PluginCustomWindowSpec.resolve(plugin: plugin, baseSpec: rawSpec)
        let reqCap = spec.requiredCapability
        let isDeclared = plugin.declaredCapabilities.contains(reqCap)
            || (reqCap == .window && plugin.declaredCapabilities.contains(.floatingWindow))
        guard isDeclared else {
            viewModel.serviceMessage = L10n.pick(
                "插件「\(plugin.displayName)」未在 plugin.json 声明 '\(reqCap.rawValue)' 窗口权限",
                "Plugin '\(plugin.displayName)' has not declared '\(reqCap.rawValue)'"
            )
            return false
        }

        let key = canvasKey(pluginID: spec.pluginID, windowID: spec.windowID)
        if activeCanvases[key] == nil {
            let countForPlugin = activeCanvases.values.filter { $0.pluginID == spec.pluginID }.count
            if countForPlugin >= PluginCustomWindowSpec.maxConcurrentWindowsPerPlugin,
               let oldestKey = activeCanvases.first(where: { $0.value.pluginID == spec.pluginID })?.key {
                _ = close(key: oldestKey)
            }
        } else {
            _ = close(key: key)
        }

        if !spec.isSatisfied(by: plugin.grantedCapabilities) {
            presentPermissionGateWindow(key: key, plugin: plugin, spec: spec, viewModel: viewModel)
            return true
        }

        guard let contentSource = resolveHTMLSource(for: spec, plugin: plugin) else {
            viewModel.serviceMessage = L10n.pick("插件自由窗口缺少有效 HTML 入口文件", "Plugin custom window is missing a valid HTML entry")
            return false
        }
        presentWebCanvas(key: key, plugin: plugin, spec: spec, source: contentSource, viewModel: viewModel)
        return true
    }

    @discardableResult
    func close(pluginID: String, windowID: String) -> Bool {
        close(key: canvasKey(pluginID: pluginID, windowID: windowID))
    }

    @discardableResult
    private func close(key: String) -> Bool {
        guard let managed = activeCanvases.removeValue(forKey: key) else { return false }
        WindowLevelStore.shared.detach(key: key)
        managed.coordinator?.tearDown(webView: managed.webView)
        managed.window.delegate = nil
        managed.window.contentView = nil
        managed.window.close()
        onWindowVisibilityChanged?()
        MemoryStats.reclaimFreeHeapPages()
        return true
    }

    func closeAll() {
        for key in Array(activeCanvases.keys) { _ = close(key: key) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWin = notification.object as? NSWindow,
              let key = activeCanvases.first(where: { $0.value.window === closedWin })?.key,
              let managed = activeCanvases.removeValue(forKey: key) else { return }
        WindowLevelStore.shared.detach(key: key)
        managed.coordinator?.tearDown(webView: managed.webView)
        closedWin.delegate = nil
        closedWin.contentView = nil
        onWindowVisibilityChanged?()
        MemoryStats.reclaimFreeHeapPages()
    }

    private enum HTMLContentSource {
        case localFile(fileURL: URL, readAccessRoot: URL)
        case inlineHTML(String, baseURL: URL)
    }

    private func resolveHTMLSource(for spec: PluginCustomWindowSpec, plugin: PluginDescriptor) -> HTMLContentSource? {
        if let rel = spec.htmlPath, !rel.isEmpty,
           let fileURL = PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: rel, bundleDirectory: plugin.directoryURL) {
            return .localFile(fileURL: fileURL, readAccessRoot: plugin.directoryURL)
        }
        if let rawHTML = spec.html, !rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .inlineHTML(rawHTML, baseURL: plugin.directoryURL)
        }
        return nil
    }

    private func presentPermissionGateWindow(
        key: String, plugin: PluginDescriptor, spec: PluginCustomWindowSpec, viewModel: AppViewModel
    ) {
        let reqCap = spec.requiredCapability
        let gateWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        gateWindow.title = "\(plugin.displayName) · \(L10n.pick("窗口权限确认", "Window Permission"))"
        gateWindow.titlebarAppearsTransparent = true
        gateWindow.isReleasedWhenClosed = false
        gateWindow.delegate = self
        gateWindow.center()

        let gateView = PluginWindowPermissionGateView(
            plugin: plugin, capability: reqCap,
            onAllow: { [weak self] in
                try? viewModel.setPluginCapabilityGranted(plugin, capability: reqCap, granted: true)
                _ = self?.close(key: key)
                _ = self?.open(spec: spec, viewModel: viewModel)
            },
            onOpenSettings: { [weak self] in
                _ = self?.close(key: key)
                viewModel.openPluginSettings(id: plugin.id)
            },
            onCancel: { [weak self] in _ = self?.close(key: key) }
        )
        gateWindow.contentView = NSHostingView(rootView: LocalizedRootContainer { gateView })
        activeCanvases[key] = ManagedCanvas(
            pluginID: plugin.id, windowID: spec.windowID, spec: spec, window: gateWindow, webView: nil, coordinator: nil
        )
        onWindowVisibilityChanged?()
        NSApp.activate(ignoringOtherApps: true)
        gateWindow.makeKeyAndOrderFront(nil)
    }

    private func presentWebCanvas(
        key: String, plugin: PluginDescriptor, spec: PluginCustomWindowSpec,
        source: HTMLContentSource, viewModel: AppViewModel
    ) {
        let win = buildNativeWindow(for: spec, title: spec.title ?? plugin.displayName)
        win.delegate = self
        positionWindow(win, spec: spec)

        let config = WKWebViewConfiguration()
        let coordinator = PluginWebBridgeCoordinator(pluginID: plugin.id, windowKey: key, viewModel: viewModel, window: win)
        let uc = WKUserContentController()
        uc.addUserScript(WKUserScript(
            source: PluginWebSDKBootstrap.buildScript(plugin: plugin, spec: spec),
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        uc.addScriptMessageHandler(coordinator, contentWorld: .page, name: PluginWebSDKBootstrap.handlerName)
        config.userContentController = uc

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: spec.width, height: spec.height), configuration: config)
        webView.navigationDelegate = coordinator
        webView.autoresizingMask = [.width, .height]
        if spec.transparent || spec.chrome != .standard {
            webView.setValue(false, forKey: "drawsBackground")
        }

        win.contentView = webView
        WindowLevelStore.shared.attach(window: win, key: key, initialPinned: spec.pinOnTop)
        win.alphaValue = spec.opacity
        win.ignoresMouseEvents = spec.clickThrough

        activeCanvases[key] = ManagedCanvas(
            pluginID: plugin.id, windowID: spec.windowID, spec: spec, window: win, webView: webView, coordinator: coordinator
        )
        onWindowVisibilityChanged?()

        switch source {
        case .localFile(let fileURL, let root): webView.loadFileURL(fileURL, allowingReadAccessTo: root)
        case .inlineHTML(let html, let baseURL): webView.loadHTMLString(html, baseURL: baseURL)
        }

        if spec.chrome == .hud {
            win.orderFrontRegardless()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }

    private func buildNativeWindow(for spec: PluginCustomWindowSpec, title: String) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: spec.width, height: spec.height)
        let win: NSWindow
        switch spec.chrome {
        case .standard:
            var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if spec.resizable { mask.insert(.resizable) }
            win = NSWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
            win.title = title; win.titlebarAppearsTransparent = spec.transparent
        case .frameless:
            var mask: NSWindow.StyleMask = [.borderless]
            if spec.resizable { mask.insert(.resizable) }
            win = PluginFramelessCanvasWindow(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
            win.title = title
        case .hud:
            var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
            if spec.resizable { mask.insert(.resizable) }
            let panel = PluginHUDCanvasPanel(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win = panel; win.title = title
        }
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: spec.minWidth, height: spec.minHeight)
        if spec.transparent || spec.chrome != .standard {
            win.isOpaque = false; win.backgroundColor = .clear
        }
        win.hasShadow = !spec.transparent || spec.chrome == .standard
        return win
    }

    private func positionWindow(_ window: NSWindow, spec: PluginCustomWindowSpec) {
        let vis = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let x = spec.x, let y = spec.y {
            let safeX = max(vis.minX + 8, min(CGFloat(x), vis.maxX - CGFloat(spec.width) - 8))
            let safeY = max(vis.minY + 8, min(CGFloat(y), vis.maxY - CGFloat(spec.height) - 8))
            window.setFrameOrigin(NSPoint(x: safeX, y: safeY))
        } else if spec.chrome != .standard || spec.pinOnTop {
            window.setFrameOrigin(NSPoint(x: vis.maxX - CGFloat(spec.width) - 24, y: vis.maxY - CGFloat(spec.height) - 36))
        } else {
            window.setFrameOrigin(NSPoint(x: vis.midX - CGFloat(spec.width) / 2, y: vis.midY - CGFloat(spec.height) / 2))
        }
    }

    private func canvasKey(pluginID: String, windowID: String) -> String {
        "customWin:\(pluginID):\(windowID)"
    }
}
