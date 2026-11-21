import AppKit
import CoreGraphics
import LucentCore
import LucentFoundation
import LucentMedia
import SwiftUI

/// Non-activating clickable bottom-right toast after quick-saving a capture so the user can reveal the saved file in Finder in one click.
@MainActor
enum QuickSaveRevealToast {
    private static var activePanel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func present(savedURL: URL) {
        dismiss()
        let screen = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 316, height: 46)
        let origin = NSPoint(x: screen.maxX - size.width - 18, y: screen.minY + 22)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LocalizedRootContainer {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.pick("已保存：\(savedURL.lastPathComponent)", "Saved: \(savedURL.lastPathComponent)"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(L10n.pick("点击在访达中定位文件", "Click to reveal in Finder"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(width: size.width, height: size.height)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LiquidColors.pillBorder, lineWidth: 0.9))
            }
            .buttonStyle(.plain)
        })
        panel.orderFrontRegardless()
        activePanel = panel
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.6))
            if !Task.isCancelled { dismiss() }
        }
    }

    static func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if let p = activePanel {
            p.contentView = nil
            p.close()
            activePanel = nil
        }
    }
}

@MainActor
extension ScreenCaptureCoordinator {
    func saveExportImage(_ image: CGImage, scale: CGFloat, session: ScreenshotSessionState) throws {
        var prefs = GeneralPreferences.load()
        let fmt = prefs.captureExportFormat
        let saveDir = prefs.resolvedCaptureSaveDirectory()
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let baseName = CaptureFileNameFormatter.formatBaseName(
            template: prefs.captureFileNameTemplate,
            appName: session.selectedWindow?.ownerName
        )
        if prefs.quickSaveCaptureWithoutDialog {
            let dst = CaptureFileNameFormatter.uniqueFileURL(in: saveDir, baseName: baseName, format: fmt)
            try ScreenshotCompositor.writeEncodedImage(image, scale: scale, format: fmt, to: dst)
            ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
            didModifyPasteboard = true
            QuickSaveRevealToast.present(savedURL: dst)
            finish(with: .saved(dst), animated: true)
            return
        }
        for p in overlayPanels { p.orderOut(nil) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fmt.utType]
        let panelDir = !prefs.lastCaptureSavePanelDirectoryPath.isEmpty
            ? URL(fileURLWithPath: prefs.lastCaptureSavePanelDirectoryPath, isDirectory: true)
            : saveDir
        panel.directoryURL = panelDir
        panel.nameFieldStringValue = "\(baseName).\(fmt.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.lastCaptureSavePanelDirectoryPath = url.deletingLastPathComponent().standardizedFileURL.path
            prefs.save()
            try ScreenshotCompositor.writeEncodedImage(image, scale: scale, format: fmt, to: url)
            ScreenshotCompositor.copyImageToPasteboard(image, scale: scale, lazy: false)
            didModifyPasteboard = true
            finish(with: .saved(url), animated: false)
        } else {
            for p in overlayPanels { p.orderFrontRegardless() }
            panelByDisplayID[session.activeDisplayID]?.makeKeyAndOrderFront(nil)
        }
    }
}
