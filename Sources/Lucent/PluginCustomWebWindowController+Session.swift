import AppKit
import Foundation
import LucentCore

@MainActor
extension PluginCustomWebWindowController {
    func syncPluginState(for pluginID: String, plugins: [PluginDescriptor]) {
        guard let plug = plugins.first(where: { $0.id == pluginID }) else { return }
        for (key, managed) in activeCanvases where managed.pluginID == pluginID {
            let pinned = WindowLevelStore.shared.isPinned(key)
            PluginWebEnvBroadcaster.pushEnvUpdate(
                to: managed.webView, plugin: plug, pinOnTop: pinned, showInDock: managed.spec.showInDock, opacity: Double(managed.window.alphaValue)
            )
        }
    }

    func reuseExistingCanvas(key: String, spec: PluginCustomWindowSpec, activateApp: Bool) -> Bool {
        guard var managed = activeCanvases[key], let webView = managed.webView else { return false }
        if let plug = boundViewModel?.plugins.first(where: { $0.id == managed.pluginID }),
           Self.bundleAssetStamp(for: plug, spec: managed.spec) != managed.contentStamp {
            return false
        }
        let sameSource = managed.spec.htmlPath == spec.htmlPath && managed.spec.html == spec.html
        guard sameSource else { return false }
        managed.spec = PluginCustomWindowSpec(
            pluginID: managed.spec.pluginID, windowID: managed.spec.windowID,
            title: spec.title ?? managed.spec.title, htmlPath: managed.spec.htmlPath, html: managed.spec.html,
            width: managed.spec.width, height: managed.spec.height,
            minWidth: managed.spec.minWidth, minHeight: managed.spec.minHeight,
            resizable: managed.spec.resizable, chrome: managed.spec.chrome,
            transparent: managed.spec.transparent, pinOnTop: managed.spec.pinOnTop,
            clickThrough: managed.spec.clickThrough, showInDock: managed.spec.showInDock,
            opacity: managed.spec.opacity, x: managed.spec.x, y: managed.spec.y,
            initialStateJSON: spec.initialStateJSON ?? managed.spec.initialStateJSON,
            reuseIfOpen: true
        )
        activeCanvases[key] = managed
        if managed.window.isMiniaturized { managed.window.deminiaturize(nil) }
        if activateApp && managed.spec.showInDock {
            NSApp.activate(ignoringOtherApps: true)
            managed.window.makeKeyAndOrderFront(nil)
        } else {
            managed.window.orderFrontRegardless()
            managed.window.makeKey()
        }
        if let rawPayload = spec.initialStateJSON,
           let encoded = try? JSONEncoder().encode(rawPayload),
           let jsLit = String(data: encoded, encoding: .utf8) {
            webView.evaluateJavaScript("window.__lucentApplyPayload && window.__lucentApplyPayload(\(jsLit));")
        }
        return true
    }

    func synchronize(plugins: [PluginDescriptor]) {
        let activeByID = Dictionary(
            plugins.filter { $0.isValid && ($0.isBuiltin || $0.isEnabled) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (key, managed) in Array(activeCanvases) {
            guard let plugin = activeByID[managed.pluginID] else {
                _ = closeByKey(key)
                continue
            }
            guard managed.webView != nil, let vm = boundViewModel else { continue }
            let latestStamp = Self.bundleAssetStamp(for: plugin, spec: managed.spec)
            if latestStamp != managed.contentStamp {
                let s = managed.spec
                let reloadSpec = PluginCustomWindowSpec(
                    pluginID: s.pluginID, windowID: s.windowID, title: s.title, htmlPath: s.htmlPath, html: s.html,
                    width: s.width, height: s.height, minWidth: s.minWidth, minHeight: s.minHeight,
                    resizable: s.resizable, chrome: s.chrome, transparent: s.transparent, pinOnTop: s.pinOnTop,
                    clickThrough: s.clickThrough, showInDock: s.showInDock, opacity: s.opacity,
                    x: nil, y: nil, initialStateJSON: s.initialStateJSON, reuseIfOpen: false
                )
                _ = open(spec: reloadSpec, viewModel: vm, activateApp: false, allowPermissionPrompt: false)
            }
        }
    }

    static func bundleAssetStamp(for plugin: PluginDescriptor, spec: PluginCustomWindowSpec) -> TimeInterval {
        guard !plugin.isBuiltin else { return 0 }
        let fm = FileManager.default
        var urls: [URL] = [
            plugin.directoryURL.appendingPathComponent("plugin.json"),
            plugin.directoryURL.appendingPathComponent(plugin.manifest.entry)
        ]
        if let rel = spec.htmlPath, !rel.isEmpty,
           let htmlURL = PluginCustomWindowSpec.resolveSafeHTMLFileURL(relativePath: rel, bundleDirectory: plugin.directoryURL) {
            urls.append(htmlURL)
            let assetDir = htmlURL.deletingLastPathComponent()
            if let children = try? fm.contentsOfDirectory(
                at: assetDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            ) {
                urls.append(contentsOf: children)
            }
        }
        var maxStamp: TimeInterval = 0
        for url in urls {
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                maxStamp = max(maxStamp, date.timeIntervalSinceReferenceDate)
            }
        }
        return maxStamp
    }

    func closeAll(forPluginID pluginID: String) {
        for (key, managed) in Array(activeCanvases) where managed.pluginID == pluginID {
            _ = closeByKey(key)
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
        persistActiveSession()
    }

    func updateRuntimeAttributesAndPersist(
        forKey key: String,
        pinOnTop: Bool? = nil,
        clickThrough: Bool? = nil,
        opacity: Double? = nil
    ) {
        guard var managed = activeCanvases[key], managed.webView != nil else { return }
        let s = managed.spec
        managed.spec = PluginCustomWindowSpec(
            pluginID: s.pluginID,
            windowID: s.windowID,
            title: s.title,
            htmlPath: s.htmlPath,
            html: s.html,
            width: s.width,
            height: s.height,
            minWidth: s.minWidth,
            minHeight: s.minHeight,
            resizable: s.resizable,
            chrome: s.chrome,
            transparent: s.transparent,
            pinOnTop: pinOnTop ?? s.pinOnTop,
            clickThrough: clickThrough ?? s.clickThrough,
            showInDock: s.showInDock,
            opacity: opacity ?? s.opacity,
            x: s.x,
            y: s.y,
            initialStateJSON: s.initialStateJSON
        )
        activeCanvases[key] = managed
        persistCanvasFrame(forKey: key)
        persistActiveSession()
    }

    func persistActiveSession() {
        let pluginsByID = Dictionary((boundViewModel?.plugins ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshots: [PersistedPluginCustomWindow] = activeCanvases
            .sorted { $0.key < $1.key }
            .compactMap { (key, managed) -> PersistedPluginCustomWindow? in
                guard managed.webView != nil else { return nil }
                if pluginsByID[managed.pluginID]?.manifest.window?.persistSession == false {
                    return nil
                }
                let s = managed.spec
                let liveSpec = PluginCustomWindowSpec(
                    pluginID: s.pluginID,
                    windowID: s.windowID,
                    title: s.title,
                    htmlPath: s.htmlPath,
                    html: s.html,
                    width: s.width,
                    height: s.height,
                    minWidth: s.minWidth,
                    minHeight: s.minHeight,
                    resizable: s.resizable,
                    chrome: s.chrome,
                    transparent: s.transparent,
                    pinOnTop: WindowLevelStore.shared.isPinned(key),
                    clickThrough: managed.window.ignoresMouseEvents,
                    showInDock: s.showInDock,
                    opacity: Double(managed.window.alphaValue),
                    x: nil,
                    y: nil,
                    initialStateJSON: s.initialStateJSON
                )
                let entry = PersistedPluginCustomWindow(
                    pluginID: managed.pluginID,
                    windowID: managed.windowID,
                    spec: liveSpec
                )
                return entry.isPersistable ? entry : nil
            }
        FloatingWindowSessionStore.replacePluginCustomWindows(snapshots)
    }

    func restorePersistedWindows(viewModel: AppViewModel) {
        let saved = FloatingWindowSessionStore.load().pluginCustomWindows
        guard !saved.isEmpty else { return }
        var restoredAnyInvalid = false
        for item in saved {
            guard let plugin = viewModel.plugins.first(where: { $0.id == item.pluginID }),
                  plugin.isValid,
                  (plugin.isBuiltin || plugin.isEnabled) else {
                restoredAnyInvalid = true
                continue
            }
            let opened = open(
                spec: item.spec,
                viewModel: viewModel,
                activateApp: false,
                allowPermissionPrompt: false
            )
            if !opened {
                restoredAnyInvalid = true
            }
        }
        if restoredAnyInvalid {
            persistActiveSession()
        }
    }
}
