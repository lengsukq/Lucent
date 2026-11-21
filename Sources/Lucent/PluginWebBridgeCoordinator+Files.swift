import AppKit
import Foundation
import LucentCore
import Quartz

/// 面向自定义 Web 窗口插件的轻量原生 Quick Look 预览控制器（与窗口生命周期解耦并在关窗时自动回收）。
@MainActor
final class PluginQuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = PluginQuickLookController()

    private var previewURLs: [URL] = []
    private var ownerKey: String?

    private override init() {
        super.init()
    }

    func present(urls: [URL], ownerKey: String) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.previewURLs = urls
        self.ownerKey = ownerKey
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func closeIfOwned(by key: String) {
        guard ownerKey == key else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.dataSource === self {
            panel.orderOut(nil)
            panel.dataSource = nil
        }
        previewURLs = []
        ownerKey = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}

@MainActor
extension PluginWebBridgeCoordinator {
    private static let maxDirectOpenFiles = 5

    func handleFileAction(body: [String: Any], plugin: PluginDescriptor) -> [String: Any] {
        guard plugin.isResourceScopeGranted(.filesystem) else {
            return [
                "ok": false,
                "error": "scope_not_granted",
                "message": L10n.pick("插件未开启「文件系统」作用域，无法打开或定位本地文件", "Filesystem scope is not enabled for this plugin")
            ]
        }
        let action = (body["action"] as? String) ?? ""
        var rawPaths = (body["paths"] as? [String]) ?? []
        if rawPaths.isEmpty, let single = body["path"] as? String {
            rawPaths = [single]
        }
        let urls = PluginWindowFileActionPolicy.resolveExistingURLs(from: rawPaths)
        guard !urls.isEmpty else {
            return [
                "ok": false,
                "error": "file_not_found",
                "message": L10n.pick("目标文件不存在或已被移动", "File does not exist or has been moved")
            ]
        }

        switch action {
        case "open":
            return handleDirectOpen(urls: urls)
        case "quickLook":
            PluginQuickLookController.shared.present(urls: urls, ownerKey: windowKey)
            return ["ok": true, "count": urls.count]
        case "reveal":
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return ["ok": true, "count": urls.count]
        default:
            return ["ok": false, "error": "unknown_file_action"]
        }
    }

    private func handleDirectOpen(urls: [URL]) -> [String: Any] {
        let safeURLs = urls.filter { PluginWindowFileActionPolicy.isSafeForDirectOpen($0) }
        if safeURLs.isEmpty || safeURLs.count < urls.count || safeURLs.count > Self.maxDirectOpenFiles {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return ["ok": true, "count": urls.count, "revealedInstead": true]
        }
        var opened = 0
        for url in safeURLs {
            if NSWorkspace.shared.open(url) {
                opened += 1
            }
        }
        return ["ok": opened > 0, "count": opened, "revealedInstead": false]
    }
}
