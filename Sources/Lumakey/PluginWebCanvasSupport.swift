import AppKit
import Foundation
import LumakeyCore
import SwiftUI
import WebKit

final class PluginFramelessCanvasWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PluginHUDCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
enum PluginWebWindowBuilder {
    static func buildNativeWindow(for spec: PluginCustomWindowSpec, title: String) -> NSWindow {
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
        if spec.transparent || spec.chrome != .standard { win.isOpaque = false; win.backgroundColor = .clear }
        win.hasShadow = !spec.transparent || spec.chrome == .standard
        return win
    }

    static func positionWindow(_ window: NSWindow, spec: PluginCustomWindowSpec) {
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

    static func makePermissionGateWindow(
        plugin: PluginDescriptor,
        capability: PluginCapability,
        delegate: NSWindowDelegate,
        onAllow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> NSWindow {
        let gateWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 250),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        gateWindow.title = "\(plugin.displayName) · \(L10n.pick("窗口权限确认", "Window Permission"))"
        gateWindow.titlebarAppearsTransparent = true
        gateWindow.isReleasedWhenClosed = false
        gateWindow.delegate = delegate
        gateWindow.center()
        let gateView = PluginWindowPermissionGateView(
            plugin: plugin, capability: capability,
            onAllow: onAllow, onOpenSettings: onOpenSettings, onCancel: onCancel
        )
        gateWindow.contentView = NSHostingView(rootView: LocalizedRootContainer { gateView })
        return gateWindow
    }
}

@MainActor
enum PluginWebNetworkSandbox {
    private static let ruleIdentifier = "lumakey-plugin-deny-network-v1"
    private static var cachedRuleList: WKContentRuleList?
    private static var compileTask: Task<WKContentRuleList?, Never>?

    private static let blockRemoteRulesJSON = """
    [
      {
        "trigger": { "url-filter": "^https?://.*" },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": "^wss?://.*" },
        "action": { "type": "block" }
      }
    ]
    """

    static func ruleListForOfflineCanvas() async -> WKContentRuleList? {
        if let cachedRuleList { return cachedRuleList }
        if let compileTask { return await compileTask.value }
        let task = Task<WKContentRuleList?, Never> { @MainActor in
            guard let store = WKContentRuleListStore.default() else { return nil }
            if let existing = try? await store.contentRuleList(forIdentifier: ruleIdentifier) {
                cachedRuleList = existing
                return existing
            }
            let compiled = try? await store.compileContentRuleList(
                forIdentifier: ruleIdentifier,
                encodedContentRuleList: blockRemoteRulesJSON
            )
            cachedRuleList = compiled
            return compiled
        }
        compileTask = task
        let result = await task.value
        compileTask = nil
        return result
    }

    static func prewarm() {
        Task { @MainActor in _ = await ruleListForOfflineCanvas() }
    }
}

@MainActor
enum PluginWebEnvBroadcaster {
    static func pushEnvUpdate(
        to webView: WKWebView?,
        plugin: PluginDescriptor,
        pinOnTop: Bool,
        opacity: Double
    ) {
        guard let webView else { return }
        let patch: [String: Any] = [
            "pluginName": plugin.displayName,
            "version": plugin.manifest.version,
            "locale": L10n.current.rawValue,
            "theme": AppThemeConfig.load().selectedTheme.rawValue,
            "pinOnTop": pinOnTop,
            "opacity": opacity,
            "declaredCapabilities": plugin.declaredCapabilities.map(\.rawValue),
            "grantedCapabilities": plugin.grantedCapabilities.map(\.rawValue).sorted(),
            "networkAllowed": plugin.isResourceScopeGranted(.network)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: patch),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__lumakeyApplyEnvUpdate && window.__lumakeyApplyEnvUpdate(\(json));")
    }
}
