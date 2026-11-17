import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func openFloatingPluginPanel(
        for plugin: PluginDescriptor,
        pinOnTop: Bool = true,
        intervalSeconds: Int? = nil,
        arguments: [String] = [],
        query: String = "",
        seedPayload: PluginViewPayload? = nil
    ) {
        let defaultInterval = intervalSeconds ?? plugin.manifest.refreshIntervalSeconds ?? 30
        let req = PluginFloatingPanelRequest(
            pluginID: plugin.id,
            pinOnTop: pinOnTop,
            refreshIntervalSeconds: defaultInterval,
            arguments: arguments,
            query: query
        )
        openRoute(.pluginPanel(req, seedPayload))
    }

    func handlePluginOpenURL(_ url: URL) {
        if let parsed = PluginDeepLinkParser.parse(url) {
            switch parsed {
            case .pluginSettings(let id):
                openPluginSettings(id: id)
            case .pluginPanel(let req):
                let seed = (activeInlinePlugin?.id == req.pluginID && req.arguments.isEmpty && req.query.isEmpty)
                    ? inlinePluginViewPayload
                    : nil
                openRoute(.pluginPanel(req, seed))
            case .pluginCustomWindow(let spec):
                _ = PluginCustomWebWindowController.shared.open(spec: spec, viewModel: self)
            case .settingsSection(let target):
                switch target {
                case "mos": openRoute(.settings(.mos))
                case "lumaLink": openRoute(.settings(.lumaLink))
                case "monitor": openRoute(.settings(.monitor))
                case "network": openRoute(.networkMonitor)
                case "cache": openRoute(.settings(.cache))
                case "plugins": openRoute(.settings(.plugins))
                case "home", "homeLayout": openRoute(.settings(.homeLayout))
                case "capture": openRoute(.settings(.capture))
                default:
                    if plugins.contains(where: { $0.id == target }) { openPluginSettings(id: target) }
                    else { openRoute(.settings(.general)) }
                }
            case .documentReader(let docURL):
                openMediaWindow(for: docURL, kind: .markdown)
            case .imageViewer(let imgURL, let pinOnTop):
                openMediaWindow(for: imgURL, kind: .image, pinOnTop: pinOnTop)
            case .pinImage(let pinURL):
                PinWindowController.shared.pinImage(at: pinURL)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    func applyPluginPostActionEffect(
        _ effect: PluginPostActionEffect,
        sourcePlugin: PluginDescriptor,
        seedPayload: PluginViewPayload? = nil,
        fromFloatingPanel: Bool = false
    ) {
        if effect.reloadSearchIndex == true {
            reloadPluginSearchIndex()
        }
        if let note = effect.notification {
            _ = PluginNotificationService.shared.post(
                note,
                pluginID: sourcePlugin.id,
                pluginName: sourcePlugin.displayName
            )
        }
        if let rawReader = effect.openReaderPath {
            let docURL = URL(fileURLWithPath: rawReader).standardizedFileURL
            if FileManager.default.fileExists(atPath: docURL.path) {
                openMediaWindow(for: docURL, kind: .markdown)
            }
        }
        if let rawImg = effect.openImagePath {
            let imgURL = URL(fileURLWithPath: rawImg).standardizedFileURL
            if FileManager.default.fileExists(atPath: imgURL.path) {
                openMediaWindow(for: imgURL, kind: .image)
            }
        }
        if let rawPin = effect.pinImagePath {
            let pinURL = URL(fileURLWithPath: rawPin).standardizedFileURL
            if FileManager.default.fileExists(atPath: pinURL.path) {
                PinWindowController.shared.pinImage(at: pinURL)
            }
        }
        if let launchWin = effect.openWindow {
            let spec = PluginCustomWindowSpec.resolve(plugin: sourcePlugin, launch: launchWin)
            _ = PluginCustomWebWindowController.shared.open(spec: spec, viewModel: self)
        }
        if !fromFloatingPanel, effect.openFloatingPanel == true {
            let hasVisibleCardItems = !(seedPayload?.items ?? []).isEmpty || !(seedPayload?.metrics ?? []).isEmpty
            openFloatingPluginPanel(
                for: sourcePlugin,
                pinOnTop: effect.floatingPanelPinOnTop ?? true,
                intervalSeconds: effect.floatingPanelIntervalSeconds,
                arguments: effect.floatingPanelArgs ?? [],
                seedPayload: hasVisibleCardItems ? seedPayload : nil
            )
        }
        if let pasteText = effect.pasteText, !pasteText.isEmpty {
            _ = performPluginPasteBack(pasteText)
        } else if !fromFloatingPanel, effect.closeOverlay == true {
            onHideOverlayRequest?()
        }
        if let toast = effect.toast, !toast.isEmpty {
            serviceMessage = toast
        }
    }
}
