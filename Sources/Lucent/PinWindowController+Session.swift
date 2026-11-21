import AppKit
import Foundation
import LucentCore
import LucentMedia

@MainActor
extension PinWindowController {
    func resolveInitialPinFrame(screenRect: NSRect?, imageSize: NSSize, ratio: CGFloat) -> NSRect {
        if let screenRect, screenRect.width >= 40, screenRect.height >= 40 {
            return screenRect
        }
        let visible = ScreenTopologyAndWindowMatcher.activeCursorScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(imageSize.width, 260), min(580, visible.width * 0.7))
        let height = min(max(width / max(ratio, 0.25), 180), min(500, visible.height * 0.7))
        let offset = CGFloat((managedPins.count % 6) * 26)
        let x = min(max(visible.minX + 24, visible.midX - width / 2 + offset), visible.maxX - width - 24)
        let y = min(max(visible.minY + 24, visible.midY - height / 2 - offset), visible.maxY - height - 24)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func closeManagedPin(panel: NSPanel, originalTempURL: URL, originalCleanTempURL: URL?) {
        dismissUnlockBadge(for: panel)
        let removed = managedPins.first { $0.panel === panel }
        managedPins.removeAll { $0.panel === panel }
        persistActivePins()
        WindowMotionAnimator.dismiss(panel, style: .floatingPin) { [weak panel] in
            panel?.delegate = nil
            panel?.contentView = nil
            panel?.close()
            if let removed {
                if removed.isManagedSessionCopy { try? FileManager.default.removeItem(at: removed.imageURL) }
                if let base = removed.cleanBaseURL, base != removed.imageURL {
                    try? FileManager.default.removeItem(at: base)
                }
            }
            for tmp in [originalTempURL, originalCleanTempURL].compactMap({ $0 }) {
                let name = tmp.lastPathComponent
                if name.hasPrefix("lucent-pin-") || name.hasPrefix("cutout-") {
                    try? FileManager.default.removeItem(at: tmp)
                }
            }
            MemoryStats.reclaimFreeHeapPages()
        }
    }

    func beginInPlaceAnnotationEdit(for managed: ManagedPin) {
        let baseURL = managed.cleanBaseURL ?? managed.imageURL
        let frame = managed.panel.frame
        let existing = managed.annotations
        managed.panel.orderOut(nil)
        Task { @MainActor [weak self, weak managed] in
            guard let self, let managed else { return }
            do {
                let result = try await ScreenCaptureCoordinator.shared.editPinnedImage(
                    cleanBaseURL: baseURL,
                    pinAppKitFrame: frame,
                    existingAnnotations: existing
                )
                if case .pinEdited(let updatedTempURL, let updatedAnnotations) = result {
                    self.applyEditedPinResult(managed: managed, updatedTempURL: updatedTempURL, annotations: updatedAnnotations)
                }
            } catch {
                managed.state.flashBadge(L10n.pick("编辑启动失败", "Edit failed"))
            }
            managed.panel.makeKeyAndOrderFront(nil)
            managed.panel.invalidateShadow()
        }
    }

    private func applyEditedPinResult(
        managed: ManagedPin,
        updatedTempURL: URL,
        annotations: [ScreenshotAnnotation]
    ) {
        defer { try? FileManager.default.removeItem(at: updatedTempURL) }
        let destURL: URL
        if managed.isManagedSessionCopy {
            destURL = managed.imageURL
        } else {
            let dir = FloatingWindowSessionStore.pinnedSessionDirectory()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            destURL = dir.appendingPathComponent("pin-\(managed.id).png", isDirectory: false)
        }
        do {
            let tmpSwap = destURL.appendingPathExtension("tmp")
            try? FileManager.default.removeItem(at: tmpSwap)
            try FileManager.default.copyItem(at: updatedTempURL, to: tmpSwap)
            if FileManager.default.fileExists(atPath: destURL.path) {
                _ = try FileManager.default.replaceItemAt(destURL, withItemAt: tmpSwap)
            } else {
                try FileManager.default.moveItem(at: tmpSwap, to: destURL)
            }
            if let refreshed = NSImage(contentsOf: destURL) {
                managed.imageURL = destURL
                managed.annotations = annotations
                managed.state.displayImage = refreshed
                managed.state.imageURL = destURL
                managed.state.flashBadge(L10n.pick("已更新标注", "Annotations updated"))
                persistActivePins()
            }
        } catch {
            managed.state.flashBadge(L10n.pick("保存标注失败", "Update failed"))
        }
    }

    func prepareDurablePinURL(sourceURL: URL, pinID: String) -> (url: URL, isManagedCopy: Bool) {
        let name = sourceURL.lastPathComponent
        let stdPath = sourceURL.standardizedFileURL.path
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let isEphemeral = name.hasPrefix("lucent-pin-")
            || name.hasPrefix("cutout-")
            || stdPath.hasPrefix(tempRoot)
        guard isEphemeral else { return (sourceURL, false) }
        let dir = FloatingWindowSessionStore.pinnedSessionDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let dest = dir.appendingPathComponent("pin-\(pinID).\(ext)", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return (dest, true)
        } catch {
            return (sourceURL, false)
        }
    }

    func prepareDurableCleanBaseURL(sourceURL: URL, pinID: String) -> URL? {
        let dir = FloatingWindowSessionStore.pinnedSessionDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let dest = dir.appendingPathComponent("pin-base-\(pinID).\(ext)", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    func persistActivePins() {
        let encoder = JSONEncoder()
        let records = managedPins.map { item in
            let f = item.panel.frame
            let json = !item.annotations.isEmpty
                ? (try? encoder.encode(item.annotations)).flatMap { String(data: $0, encoding: .utf8) }
                : nil
            return PersistedPinnedImageWindow(
                id: item.id,
                imagePath: item.imageURL.standardizedFileURL.path,
                cleanBaseImagePath: item.cleanBaseURL?.standardizedFileURL.path,
                annotationsJSON: json,
                isManagedSessionCopy: item.isManagedSessionCopy,
                isCutout: item.isCutout,
                x: Double(f.origin.x),
                y: Double(f.origin.y),
                width: Double(f.size.width),
                height: Double(f.size.height),
                opacity: item.state.opacity,
                isClickThrough: item.state.isClickThrough
            )
        }
        FloatingWindowSessionStore.replacePinnedImages(records)
    }

    func restorePersistedPins() {
        let saved = FloatingWindowSessionStore.load().pinnedImages
        guard !saved.isEmpty else {
            FloatingWindowSessionStore.pruneOrphanPinnedFiles(keeping: [])
            return
        }
        let screens = PluginWindowMotionSession.currentScreens()
        var hadInvalid = false
        for item in saved {
            guard FileManager.default.fileExists(atPath: item.imagePath) else {
                hadInvalid = true
                continue
            }
            let rawRect = CGRect(x: item.x, y: item.y, width: item.width, height: item.height)
            let screen = PluginWindowGeometry.bestScreen(for: rawRect, screens: screens)
            let clamped = PluginWindowGeometry.clampFrameToVisible(rawRect, visibleFrame: screen.visibleFrame, margin: 8)
            pinImage(
                at: URL(fileURLWithPath: item.imagePath),
                screenRect: clamped,
                makeKey: false,
                restoredRecord: item
            )
        }
        if hadInvalid { persistActivePins() }
        var keepPaths = Set(managedPins.filter(\.isManagedSessionCopy).map { $0.imageURL.standardizedFileURL.path })
        for base in managedPins.compactMap(\.cleanBaseURL) { keepPaths.insert(base.standardizedFileURL.path) }
        FloatingWindowSessionStore.pruneOrphanPinnedFiles(keeping: keepPaths)
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSPanel,
              managedPins.contains(where: { $0.panel === win }) else { return }
        persistActivePins()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let win = notification.object as? NSPanel,
              managedPins.contains(where: { $0.panel === win }) else { return }
        persistActivePins()
    }
}
