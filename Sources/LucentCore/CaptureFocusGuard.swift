import AppKit
import Foundation

/// Preserves the active external application and keeps background Lucent windows
/// from jumping to the front when fullscreen capture overlays activate the app.
@MainActor
public final class CaptureFocusGuard {
    private struct WeakWindowBox {
        weak var window: NSWindow?
    }

    private var previousFrontmostApp: NSRunningApplication?
    private var suppressedWindows: [WeakWindowBox] = []
    private var hasCapturedBaseline = false

    public init() {}

    public var hasPreviousTargetApp: Bool { previousFrontmostApp != nil }
    public var suppressedWindowCount: Int { suppressedWindows.compactMap(\.window).count }

    public static func resolveTargetApp(
        preferred: NSRunningApplication? = nil,
        frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> NSRunningApplication? {
        if let preferred, !preferred.isTerminated, preferred.processIdentifier != selfPID {
            return preferred
        }
        if let frontmost, !frontmost.isTerminated, frontmost.processIdentifier != selfPID {
            return frontmost
        }
        return nil
    }

    public static func shouldSuppressBackgroundWindow(
        _ window: NSWindow,
        excluding: Set<ObjectIdentifier>
    ) -> Bool {
        guard !excluding.contains(ObjectIdentifier(window)) else { return false }
        guard window.isVisible, !window.isMiniaturized else { return false }
        guard window.level == .normal else { return false }
        return window.canBecomeMain || window.canBecomeKey
    }

    public func prepareForNewCapture(preferredApp: NSRunningApplication? = nil) {
        let carriedApp = previousFrontmostApp
        restoreSuppressedWindows()
        previousFrontmostApp = nil
        hasCapturedBaseline = false
        captureBaselineIfNeeded(preferredApp: preferredApp ?? carriedApp)
    }

    public func captureBaselineIfNeeded(preferredApp: NSRunningApplication? = nil) {
        if !hasCapturedBaseline {
            previousFrontmostApp = Self.resolveTargetApp(preferred: preferredApp)
            hasCapturedBaseline = true
        } else if previousFrontmostApp == nil,
                  let resolved = Self.resolveTargetApp(preferred: preferredApp, frontmost: nil) {
            previousFrontmostApp = resolved
        }
    }

    public func suppressBackgroundWindowsIfNeeded(
        excluding overlayPanels: [NSWindow],
        candidateWindows: [NSWindow]? = nil
    ) {
        captureBaselineIfNeeded()
        guard previousFrontmostApp != nil else { return }
        let excludedIDs = Set(overlayPanels.map { ObjectIdentifier($0) })
        var knownIDs = Set(suppressedWindows.compactMap { $0.window.map { ObjectIdentifier($0) } })
        for win in (candidateWindows ?? NSApp?.windows ?? []) {
            guard Self.shouldSuppressBackgroundWindow(win, excluding: excludedIDs) else { continue }
            let winID = ObjectIdentifier(win)
            guard knownIDs.insert(winID).inserted else { continue }
            suppressedWindows.append(WeakWindowBox(window: win))
            win.orderOut(nil)
        }
    }

    public func activateAppForCapture() {
        NSApp?.activate(ignoringOtherApps: true)
    }

    public func beginRestorePreviousAppIfNeeded() {
        guard let targetApp = previousFrontmostApp, !targetApp.isTerminated else { return }
        if !targetApp.isActive {
            NSApp?.yieldActivation(to: targetApp)
            targetApp.activate()
        }
    }

    public func restoreSuppressedWindows() {
        let boxes = suppressedWindows
        suppressedWindows.removeAll()
        for box in boxes {
            guard let win = box.window, !win.isVisible, !win.isMiniaturized else { continue }
            win.orderBack(nil)
        }
    }

    public func finishRestore(restorePreviousApp: Bool) {
        if restorePreviousApp {
            beginRestorePreviousAppIfNeeded()
        }
        previousFrontmostApp = nil
        hasCapturedBaseline = false
        restoreSuppressedWindows()
    }
}
