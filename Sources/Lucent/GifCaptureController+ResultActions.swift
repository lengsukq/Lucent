import AppKit
import Foundation
import LucentCore
import UniformTypeIdentifiers

extension GifCaptureController {
    func recordAgain() {
        let cb = consumePendingCompletionHandler()
        let vcb = pendingVideoCompletionHandler
        pendingVideoCompletionHandler = nil
        let currentMode = recordingMode
        dismissCompletedHUD(immediately: true)
        startInteractiveCapture(mode: currentMode, onComplete: cb, onVideoComplete: vcb)
    }

    func copyResultAgain(_ result: GifFinalizeResult) {
        if GifStreamEncoder.copyGifToPasteboard(at: result.fileURL) {
            onStatusMessage?("已重新复制 GIF 动图到剪贴板")
        }
    }

    func copyVideoResultAgain(_ result: VideoFinalizeResult) {
        if VideoStreamEncoder.copyVideoToPasteboard(at: result.fileURL) {
            onStatusMessage?(L10n.pick("已重新复制 MP4 录像到剪贴板", "MP4 recording copied to clipboard"))
        }
    }

    func saveVideoResultAs(_ result: VideoFinalizeResult) {
        let prefs = GeneralPreferences.load()
        let saveDir = prefs.resolvedCaptureSaveDirectory()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let fileName = "Lucent-Video-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).mp4"
        if prefs.quickSaveCaptureWithoutDialog {
            let dst = saveDir.appendingPathComponent(fileName, isDirectory: false)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = VideoStreamEncoder.copyVideoToPasteboard(at: dst)
            onStatusMessage?(L10n.pick("录像已保存至默认目录：\(dst.lastPathComponent)", "Video saved to default folder: \(dst.lastPathComponent)"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.directoryURL = saveDir
        panel.nameFieldStringValue = fileName
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dst = panel.url {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = VideoStreamEncoder.copyVideoToPasteboard(at: dst)
            onStatusMessage?(L10n.pick("录像已另存为：\(dst.lastPathComponent)", "Video saved as: \(dst.lastPathComponent)"))
        }
    }

    func saveResultAs(_ result: GifFinalizeResult) {
        let prefs = GeneralPreferences.load()
        let saveDir = prefs.resolvedCaptureSaveDirectory()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let fileName = "Lucent-GIF-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).gif"
        if prefs.quickSaveCaptureWithoutDialog {
            let dst = saveDir.appendingPathComponent(fileName, isDirectory: false)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = GifStreamEncoder.copyGifToPasteboard(at: dst)
            onStatusMessage?(L10n.pick("GIF 已保存至默认目录：\(dst.lastPathComponent)", "GIF saved to default folder: \(dst.lastPathComponent)"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.directoryURL = saveDir
        panel.nameFieldStringValue = fileName
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dst = panel.url {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: result.fileURL, to: dst)
            _ = GifStreamEncoder.copyGifToPasteboard(at: dst)
            onStatusMessage?("GIF 已另存为：\(dst.lastPathComponent)")
        }
    }

    func revealResultInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func previewResult(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
