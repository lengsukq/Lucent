import AppKit
import Foundation
import LucentCore

@MainActor
extension PinWindowController {
    func prepareDurablePinURL(sourceURL: URL, pinID: String) -> (url: URL, isManagedCopy: Bool) {
        let name = sourceURL.lastPathComponent
        let stdPath = sourceURL.standardizedFileURL.path
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let isEphemeral = name.hasPrefix("lucent-pin-")
            || name.hasPrefix("cutout-")
            || stdPath.hasPrefix(tempRoot)
        guard isEphemeral else {
            return (sourceURL, false)
        }
        let dir = FloatingWindowSessionStore.pinnedSessionDirectory()
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let dest = dir.appendingPathComponent("pin-\(pinID).\(ext)", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return (dest, true)
        } catch {
            return (sourceURL, false)
        }
    }

    func persistActivePins() {
        let records = managedPins.map { item in
            let f = item.panel.frame
            return PersistedPinnedImageWindow(
                id: item.id,
                imagePath: item.imageURL.standardizedFileURL.path,
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
        if hadInvalid {
            persistActivePins()
        }
        let keepPaths = Set(managedPins.filter(\.isManagedSessionCopy).map { $0.imageURL.standardizedFileURL.path })
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
