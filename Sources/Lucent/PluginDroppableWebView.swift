import AppKit
import Foundation
import WebKit

/// 拦截 macOS 原生文件/文件夹拖拽并向 `window.lucent` 透传真实 POSIX 路径的自由窗口 WebView。
@MainActor
final class PluginDroppableWebView: WKWebView {
    private var isFileDragActive = false

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let paths = Self.extractFilePaths(from: sender.draggingPasteboard)
        if !paths.isEmpty {
            isFileDragActive = true
            dispatchEvent("lucent:fileDragState", detail: ["active": true, "count": paths.count])
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if isFileDragActive {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        if isFileDragActive {
            isFileDragActive = false
            dispatchEvent("lucent:fileDragState", detail: ["active": false, "count": 0])
            return
        }
        super.draggingExited(sender)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        if isFileDragActive {
            isFileDragActive = false
            dispatchEvent("lucent:fileDragState", detail: ["active": false, "count": 0])
        }
        super.concludeDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let paths = Self.extractFilePaths(from: sender.draggingPasteboard)
        if !paths.isEmpty {
            isFileDragActive = false
            dispatchEvent("lucent:fileDragState", detail: ["active": false, "count": 0])
            dispatchEvent("lucent:filesDropped", detail: ["filePaths": paths])
            return true
        }
        return super.performDragOperation(sender)
    }

    private func dispatchEvent(_ eventName: String, detail: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluateJavaScript("window.__lucentDispatchWindowEvent && window.__lucentDispatchWindowEvent(\"\(eventName)\", \(json));")
    }

    private static func extractFilePaths(from pasteboard: NSPasteboard) -> [String] {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return []
        }
        var seen = Set<String>()
        var paths: [String] = []
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            if FileManager.default.fileExists(atPath: path), seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }
}
