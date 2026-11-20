import AppKit
import Foundation
import LucentCore

@MainActor
extension PluginCustomWebWindowController {
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
        let snapshots: [PersistedPluginCustomWindow] = activeCanvases
            .sorted { $0.key < $1.key }
            .compactMap { (key, managed) -> PersistedPluginCustomWindow? in
                guard managed.webView != nil else { return nil }
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
