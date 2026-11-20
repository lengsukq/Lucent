import AppKit
import Foundation
import LucentCore
import SwiftUI
import WebKit

@MainActor
final class PluginCustomWebWindowController: NSObject, NSWindowDelegate {
    static let shared = PluginCustomWebWindowController()

    struct ManagedCanvas {
        let pluginID: String
        let windowID: String
        var spec: PluginCustomWindowSpec
        let window: NSWindow
        let webView: WKWebView?
        let coordinator: PluginWebBridgeCoordinator?
    }

    var activeCanvases: [String: ManagedCanvas] = [:]
    private weak var boundViewModel: AppViewModel?
    var onWindowVisibilityChanged: (() -> Void)?

    private override init() {
        super.init()
        PluginWebNetworkSandbox.prewarm()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostEnvChanged), name: .lucentLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHostEnvChanged), name: .lucentThemeDidChange, object: nil
        )
    }

    @objc private func handleHostEnvChanged() {
        guard let vm = boundViewModel else { return }
        for (key, managed) in activeCanvases {
            guard let plug = vm.plugins.first(where: { $0.id == managed.pluginID }) else { continue }
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, showInDock: managed.spec.showInDock, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    var hasDockVisibleWindows: Bool {
        activeCanvases.values.contains { $0.webView == nil || $0.spec.showInDock }
    }

    var activeWindowCount: Int { activeCanvases.count }

    func setShowInDock(_ enabled: Bool, forKey key: String) {
        guard var managed = activeCanvases[key], managed.spec.showInDock != enabled else { return }
        managed.spec = managed.spec.withShowInDock(enabled)
        activeCanvases[key] = managed
        persistActiveSession()
        onWindowVisibilityChanged?()
        if let plug = boundViewModel?.plugins.first(where: { $0.id == managed.pluginID }) {
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, showInDock: enabled, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    func syncPluginState(for pluginID: String, plugins: [PluginDescriptor]) {
        guard let plug = plugins.first(where: { $0.id == pluginID }) else { return }
        for (key, managed) in activeCanvases where managed.pluginID == pluginID {
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, showInDock: managed.spec.showInDock, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    @discardableResult
    func open(
        spec rawSpec: PluginCustomWindowSpec,
        viewModel: AppViewModel,
        activateApp: Bool = true,
        allowPermissionPrompt: Bool = true
    ) -> Bool {
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
                _ = closeByKey(oldestKey)
            }
        } else {
            _ = closeByKey(key)
        }

        if !spec.isSatisfied(by: plugin.grantedCapabilities) {
            guard allowPermissionPrompt else { return false }
            let gateWindow = PluginWebWindowBuilder.makePermissionGateWindow(
                plugin: plugin, capability: reqCap, delegate: self,
                onAllow: { [weak self] in
                    try? viewModel.setPluginCapabilityGranted(plugin, capability: reqCap, granted: true)
                    _ = self?.closeByKey(key)
                    _ = self?.open(spec: spec, viewModel: viewModel)
                },
                onOpenSettings: { [weak self] in
                    _ = self?.closeByKey(key)
                    viewModel.openPluginSettings(id: plugin.id)
                },
                onCancel: { [weak self] in _ = self?.closeByKey(key) }
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
            if allowPermissionPrompt {
                viewModel.serviceMessage = L10n.pick("插件自由窗口缺少有效 HTML 入口文件", "Plugin custom window is missing a valid HTML entry")
            }
            return false
        }
        presentWebCanvas(
            key: key, plugin: plugin, spec: spec, source: contentSource,
            viewModel: viewModel, activateApp: activateApp
        )
        return true
    }

    @discardableResult
    func close(pluginID: String, windowID: String) -> Bool {
        closeByKey(canvasKey(pluginID: pluginID, windowID: windowID))
    }

    @discardableResult
    func closeByKey(_ key: String, updateSession: Bool = true) -> Bool {
        persistCanvasFrame(forKey: key)
        guard let managed = activeCanvases.removeValue(forKey: key) else { return false }
        WindowLevelStore.shared.detach(key: key)
        managed.coordinator?.tearDown(webView: managed.webView)
        managed.window.delegate = nil
        managed.window.contentView = nil
        managed.window.close()
        if updateSession { persistActiveSession() }
        onWindowVisibilityChanged?()
        MemoryStats.reclaimFreeHeapPages()
        return true
    }

    func closeAll(clearPersistedSession: Bool = true) {
        if !clearPersistedSession { persistActiveSession() }
        for key in Array(activeCanvases.keys) { _ = closeByKey(key, updateSession: false) }
        if clearPersistedSession { persistActiveSession() }
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              let pair = activeCanvases.first(where: { $0.value.window === win }) else { return }
        persistCanvasFrame(forKey: pair.key)
        pair.value.coordinator?.motionSession.notifyNativeFrameChanged(settled: false)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              let pair = activeCanvases.first(where: { $0.value.window === win }) else { return }
        persistCanvasFrame(forKey: pair.key)
        pair.value.coordinator?.motionSession.notifyNativeFrameChanged(settled: true)
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
        persistActiveSession()
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
            return .localFile(fileURL: fileURL, readAccessRoot: plugin.directoryURL.resolvingSymlinksInPath().standardizedFileURL)
        }
        if let rawHTML = spec.html, !rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .inlineHTML(rawHTML, baseURL: plugin.directoryURL)
        }
        return nil
    }

    private func presentWebCanvas(
        key: String, plugin: PluginDescriptor, spec: PluginCustomWindowSpec,
        source: HTMLContentSource, viewModel: AppViewModel, activateApp: Bool
    ) {
        let win = PluginWebWindowBuilder.buildNativeWindow(for: spec, title: spec.title ?? plugin.displayName)
        win.delegate = self
        PluginWebWindowBuilder.positionWindow(win, spec: spec)

        let config = WKWebViewConfiguration()
        let coordinator = PluginWebBridgeCoordinator(
            pluginID: plugin.id,
            windowKey: key,
            allowCompactFloating: spec.chrome != .standard,
            viewModel: viewModel,
            window: win
        )
        let uc = WKUserContentController()
        uc.addUserScript(WKUserScript(
            source: PluginWebSDKBootstrap.buildScript(plugin: plugin, spec: spec),
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        uc.addScriptMessageHandler(coordinator, contentWorld: .page, name: PluginWebSDKBootstrap.handlerName)
        config.userContentController = uc

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: spec.width, height: spec.height), configuration: config)
        coordinator.bind(webView: webView)
        webView.navigationDelegate = coordinator
        webView.autoresizingMask = [.width, .height]
        if spec.transparent || spec.chrome != .standard {
            webView.setValue(false, forKey: "drawsBackground")
            webView.wantsLayer = true
            webView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if spec.chrome == .standard && spec.transparent {
            let material = NSVisualEffectView(frame: webView.frame)
            material.material = .windowBackground
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.addSubview(webView)
            win.contentView = material
        } else {
            win.contentView = webView
        }
        WindowLevelStore.shared.attach(window: win, key: key, initialPinned: spec.pinOnTop)
        win.alphaValue = spec.opacity
        win.ignoresMouseEvents = spec.clickThrough

        activeCanvases[key] = ManagedCanvas(
            pluginID: plugin.id, windowID: spec.windowID, spec: spec, window: win, webView: webView, coordinator: coordinator
        )
        persistActiveSession()
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

        if activateApp && spec.showInDock { NSApp.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil) }
        else { win.orderFrontRegardless() }
    }

    private func canvasKey(pluginID: String, windowID: String) -> String {
        "customWin:\(pluginID):\(windowID)"
    }
}
