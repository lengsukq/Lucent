import AppKit
import Foundation
import LumakeyCore
import SwiftUI
import WebKit

@MainActor
final class PluginCustomWebWindowController: NSObject, NSWindowDelegate {
    static let shared = PluginCustomWebWindowController()

    private struct ManagedCanvas {
        let pluginID: String
        let windowID: String
        var spec: PluginCustomWindowSpec
        let window: NSWindow
        let webView: WKWebView?
        let coordinator: PluginWebBridgeCoordinator?
    }

    private var activeCanvases: [String: ManagedCanvas] = [:]
    private weak var boundViewModel: AppViewModel?
    var onWindowVisibilityChanged: (() -> Void)?

    private override init() {
        super.init()
        PluginWebNetworkSandbox.prewarm()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostEnvChanged), name: .lumakeyLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostEnvChanged), name: .lumakeyThemeDidChange, object: nil
        )
    }

    @objc private func handleHostEnvChanged() {
        guard let vm = boundViewModel else { return }
        for (key, managed) in activeCanvases {
            guard let plug = vm.plugins.first(where: { $0.id == managed.pluginID }) else { continue }
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    var hasStandardWindows: Bool {
        activeCanvases.values.contains { $0.spec.chrome != .hud && $0.window.isVisible }
    }

    var activeWindowCount: Int { activeCanvases.count }

    func syncPluginState(for pluginID: String, plugins: [PluginDescriptor]) {
        guard let plug = plugins.first(where: { $0.id == pluginID }) else { return }
        for (key, managed) in activeCanvases where managed.pluginID == pluginID {
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    func persistCanvasFrame(forKey key: String) {
        guard let managed = activeCanvases[key], managed.webView != nil else { return }
        let frame = managed.window.frame
        let saved = PluginSavedWindowFrame(
            x: Int(frame.origin.x.rounded()),
            y: Int(frame.origin.y.rounded()),
            width: Int(frame.size.width.rounded()),
            height: Int(frame.size.height.rounded()),
            opacity: Double(managed.window.alphaValue),
            pinOnTop: WindowLevelStore.shared.isPinned(key)
        )
        PluginWindowFrameStore.saveFrame(saved, pluginID: managed.pluginID, windowID: managed.windowID)
    }

    func resetCanvasToDefaults(forKey key: String, plugin: PluginDescriptor) {
        guard let managed = activeCanvases[key] else { return }
        let defSpec = PluginCustomWindowSpec.resolve(plugin: plugin, launch: PluginWindowLaunchEffect(windowID: managed.windowID))
        managed.window.setContentSize(NSSize(width: CGFloat(defSpec.width), height: CGFloat(defSpec.height)))
        PluginWebWindowBuilder.positionWindow(managed.window, spec: defSpec)
        managed.window.alphaValue = defSpec.opacity
        if plugin.grantedCapabilities.contains(.floatingWindow) || !defSpec.pinOnTop {
            WindowLevelStore.shared.setPinned(defSpec.pinOnTop, forKey: key)
        }
        persistCanvasFrame(forKey: key)
    }

    @discardableResult
    func open(spec rawSpec: PluginCustomWindowSpec, viewModel: AppViewModel) -> Bool {
        boundViewModel = viewModel
        guard let plugin = viewModel.plugins.first(where: { $0.id == rawSpec.pluginID }),
              plugin.isBuiltin || plugin.isEnabled else {
            viewModel.serviceMessage = L10n.pick("未找到可用插件 '\(rawSpec.pluginID)'", "Plugin '\(rawSpec.pluginID)' not available")
            return false
        }
        let resolvedBase = PluginCustomWindowSpec.resolve(plugin: plugin, baseSpec: rawSpec)
        let savedFrame = PluginWindowFrameStore.loadFrame(pluginID: resolvedBase.pluginID, windowID: resolvedBase.windowID)
        let spec = resolvedBase.applyingSavedFrame(
            savedFrame,
            hasExplicitOrigin: rawSpec.x != nil && rawSpec.y != nil,
            canRestoreFloatingPin: plugin.grantedCapabilities.contains(.floatingWindow)
        )
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
            let gateWindow = PluginWebWindowBuilder.makePermissionGateWindow(
                plugin: plugin, capability: reqCap, delegate: self,
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
            activeCanvases[key] = ManagedCanvas(
                pluginID: plugin.id, windowID: spec.windowID, spec: spec, window: gateWindow, webView: nil, coordinator: nil
            )
            onWindowVisibilityChanged?()
            NSApp.activate(ignoringOtherApps: true)
            gateWindow.makeKeyAndOrderFront(nil)
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
        persistCanvasFrame(forKey: key)
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

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              let key = activeCanvases.first(where: { $0.value.window === win })?.key else { return }
        persistCanvasFrame(forKey: key)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              let key = activeCanvases.first(where: { $0.value.window === win })?.key else { return }
        persistCanvasFrame(forKey: key)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWin = notification.object as? NSWindow,
              let key = activeCanvases.first(where: { $0.value.window === closedWin })?.key else { return }
        persistCanvasFrame(forKey: key)
        guard let managed = activeCanvases.removeValue(forKey: key) else { return }
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

    private func presentWebCanvas(
        key: String, plugin: PluginDescriptor, spec: PluginCustomWindowSpec,
        source: HTMLContentSource, viewModel: AppViewModel
    ) {
        let win = PluginWebWindowBuilder.buildNativeWindow(for: spec, title: spec.title ?? plugin.displayName)
        win.delegate = self
        PluginWebWindowBuilder.positionWindow(win, spec: spec)

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
            webView.wantsLayer = true
            webView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        win.contentView = webView
        WindowLevelStore.shared.attach(window: win, key: key, initialPinned: spec.pinOnTop)
        win.alphaValue = spec.opacity
        win.ignoresMouseEvents = spec.clickThrough

        activeCanvases[key] = ManagedCanvas(
            pluginID: plugin.id, windowID: spec.windowID, spec: spec, window: win, webView: webView, coordinator: coordinator
        )
        onWindowVisibilityChanged?()

        let allowNet = plugin.isResourceScopeGranted(.network)
        Task { @MainActor [weak webView] in
            if !allowNet, let rules = await PluginWebNetworkSandbox.ruleListForOfflineCanvas() {
                webView?.configuration.userContentController.add(rules)
            }
            guard let webView else { return }
            switch source {
            case .localFile(let fileURL, let root): webView.loadFileURL(fileURL, allowingReadAccessTo: root)
            case .inlineHTML(let html, let baseURL): webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        if spec.chrome == .hud { win.orderFrontRegardless() }
        else { NSApp.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil) }
    }

    private func canvasKey(pluginID: String, windowID: String) -> String {
        "customWin:\(pluginID):\(windowID)"
    }
}
