import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public protocol SystemWindowHardware: Sendable {
    func isAccessibilityTrusted() -> Bool
    func displays() -> [SystemDisplayRect]
    func listWindows(excludingPID: Int32) -> [ManagedWindowInfo]
    func frontmostWindow(preferredPID: Int32?, excludingPID: Int32) -> ManagedWindowInfo?
    func setWindowFrame(
        pid: Int32,
        windowIndex: Int,
        titleHint: String?,
        frame: CGRect,
        activate: Bool
    ) -> CGRect?
    func launchApplication(bundleID: String) -> Int32?
}

public struct SystemWindowControlAdapter: SystemWindowHardware {
    public init() {}

    public func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func displays() -> [SystemDisplayRect] {
        Self.runOnMainSync {
            let screens = NSScreen.screens
            guard let primary = screens.first else { return [] }
            let primaryH = primary.frame.height
            let raw: [(UInt32, String, Bool, CGRect, CGRect)] = screens.enumerated().map { idx, screen in
                let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    ?? CGMainDisplayID()
                let isMain = (idx == 0) || (num == CGMainDisplayID())
                let name = screen.localizedName.isEmpty ? "Display \(idx + 1)" : screen.localizedName
                let qFrame = WindowLayoutGeometry.quartzRect(fromCocoa: screen.frame, primaryScreenHeight: primaryH)
                let qVis = WindowLayoutGeometry.quartzRect(fromCocoa: screen.visibleFrame, primaryScreenHeight: primaryH)
                return (num, name, isMain, qFrame, qVis)
            }
            // Sort spatially left-to-right, then top-to-bottom so next/prev display follows physical layout.
            let sorted = raw.sorted { a, b in
                if abs(a.3.minX - b.3.minX) > 20 { return a.3.minX < b.3.minX }
                if abs(a.3.minY - b.3.minY) > 20 { return a.3.minY < b.3.minY }
                return a.0 < b.0
            }
            return sorted.enumerated().map { idx, item in
                SystemDisplayRect(
                    displayID: item.0, name: item.1, isMain: item.2,
                    index: idx, frame: item.3, visibleFrame: item.4
                )
            }
        }
    }

    public func listWindows(excludingPID: Int32) -> [ManagedWindowInfo] {
        guard isAccessibilityTrusted() else { return [] }
        let screens = displays()
        guard !screens.isEmpty else { return [] }
        let orderedPIDs = visibleRegularAppPIDsInZOrder(excludingPID: excludingPID)
        let frontPID = Self.runOnMainSync { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }

        var results: [ManagedWindowInfo] = []
        for pid in orderedPIDs {
            guard let app = runningAppMeta(pid: pid) else { continue }
            let appWindows = collectStandardWindows(
                pid: pid, bundleID: app.bundleID, appName: app.name,
                displays: screens, isAppFrontmost: pid == frontPID
            )
            results.append(contentsOf: appWindows)
            if results.count >= 48 { break }
        }
        return results
    }

    public func frontmostWindow(preferredPID: Int32?, excludingPID: Int32) -> ManagedWindowInfo? {
        guard isAccessibilityTrusted() else { return nil }
        let screens = displays()
        guard !screens.isEmpty else { return nil }

        let liveFrontPID = Self.runOnMainSync { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }
        var candidatePIDs: [Int32] = []
        if liveFrontPID > 0, liveFrontPID != excludingPID { candidatePIDs.append(liveFrontPID) }
        if let pref = preferredPID, pref > 0, pref != excludingPID, !candidatePIDs.contains(pref) {
            candidatePIDs.append(pref)
        }
        for zPID in visibleRegularAppPIDsInZOrder(excludingPID: excludingPID) where !candidatePIDs.contains(zPID) {
            candidatePIDs.append(zPID)
            if candidatePIDs.count >= 8 { break }
        }

        for pid in candidatePIDs {
            guard let app = runningAppMeta(pid: pid) else { continue }
            let windows = collectStandardWindows(
                pid: pid, bundleID: app.bundleID, appName: app.name,
                displays: screens, isAppFrontmost: true
            )
            if let focused = windows.first(where: { $0.isFocused && !$0.isMinimized }) { return focused }
            if let visible = windows.first(where: { !$0.isMinimized }) { return visible }
        }
        return nil
    }

    public func setWindowFrame(
        pid: Int32,
        windowIndex: Int,
        titleHint: String?,
        frame: CGRect,
        activate: Bool
    ) -> CGRect? {
        guard isAccessibilityTrusted(), pid > 0 else { return nil }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, SystemWindowAXHelpers.axTimeoutSeconds)
        let windows = SystemWindowAXHelpers.standardAXWindows(of: appEl)
        guard !windows.isEmpty else { return nil }

        let target = SystemWindowAXHelpers.pickWindow(in: windows, windowIndex: windowIndex, titleHint: titleHint)
        AXUIElementSetMessagingTimeout(target, SystemWindowAXHelpers.axTimeoutSeconds)

        if SystemWindowAXHelpers.boolAttr(target, kAXMinimizedAttribute as CFString) == true {
            _ = AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        let enhancedKey = SystemWindowAXHelpers.enhancedUIName as CFString
        let hadEnhancedUI = SystemWindowAXHelpers.boolAttr(appEl, enhancedKey) == true
        if hadEnhancedUI {
            _ = AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanFalse)
        }
        defer {
            if hadEnhancedUI {
                _ = AXUIElementSetAttributeValue(appEl, enhancedKey, kCFBooleanTrue)
            }
        }

        // Set size -> position -> size so cross-monitor resizes are not clamped by the source display bounds.
        SystemWindowAXHelpers.setSize(frame.size, on: target)
        SystemWindowAXHelpers.setPosition(frame.origin, on: target)
        if let afterMove = SystemWindowAXHelpers.readFrame(of: target),
           abs(afterMove.width - frame.width) > 2 || abs(afterMove.height - frame.height) > 2 {
            SystemWindowAXHelpers.setSize(frame.size, on: target)
        }

        if activate {
            _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
            Self.runOnMainSync {
                _ = NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
        return SystemWindowAXHelpers.readFrame(of: target) ?? frame
    }

    public func launchApplication(bundleID: String) -> Int32? {
        guard !bundleID.isEmpty else { return nil }
        if let existing = Self.runOnMainSync({
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated })?.processIdentifier
        }) {
            return existing
        }
        guard let appURL = Self.runOnMainSync({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }) else {
            return nil
        }
        let sem = DispatchSemaphore(value: 0)
        let pidBox = LockedPIDBox()
        DispatchQueue.main.async {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { app, _ in
                pidBox.set(app?.processIdentifier)
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + .milliseconds(1400))
        guard let launchedPID = pidBox.get(), launchedPID > 0 else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.2
        let appEl = AXUIElementCreateApplication(launchedPID)
        AXUIElementSetMessagingTimeout(appEl, SystemWindowAXHelpers.axTimeoutSeconds)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !SystemWindowAXHelpers.standardAXWindows(of: appEl).isEmpty { break }
            Thread.sleep(forTimeInterval: 0.08)
        }
        return launchedPID
    }

    private func collectStandardWindows(
        pid: Int32,
        bundleID: String,
        appName: String,
        displays: [SystemDisplayRect],
        isAppFrontmost: Bool
    ) -> [ManagedWindowInfo] {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, SystemWindowAXHelpers.axTimeoutSeconds)
        let focusedWin = SystemWindowAXHelpers.elementAttr(appEl, kAXFocusedWindowAttribute as CFString)
            ?? SystemWindowAXHelpers.elementAttr(appEl, kAXMainWindowAttribute as CFString)
        let rawWindows = SystemWindowAXHelpers.standardAXWindows(of: appEl)
        return rawWindows.enumerated().compactMap { idx, win in
            guard let rect = SystemWindowAXHelpers.readFrame(of: win),
                  rect.width >= 80, rect.height >= 60 else { return nil }
            let dispIdx = WindowLayoutGeometry.bestDisplayIndex(for: rect, in: displays)
            let displayID = displays[dispIdx].displayID
            let title = (SystemWindowAXHelpers.stringAttr(win, kAXTitleAttribute as CFString) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let minimized = SystemWindowAXHelpers.boolAttr(win, kAXMinimizedAttribute as CFString) == true
            var sizeSettable = DarwinBoolean(false)
            _ = AXUIElementIsAttributeSettable(win, kAXSizeAttribute as CFString, &sizeSettable)
            let isFocused = isAppFrontmost && (focusedWin.map { CFEqual($0, win) } ?? (idx == 0))
            return ManagedWindowInfo(
                pid: pid, bundleID: bundleID, appName: appName,
                title: title.isEmpty ? appName : title,
                windowIndex: idx, frame: rect, displayID: displayID, displayIndex: dispIdx,
                isFocused: isFocused, isMinimized: minimized, isResizable: sizeSettable.boolValue
            )
        }
    }

    private func visibleRegularAppPIDsInZOrder(excludingPID: Int32) -> [Int32] {
        let regularPIDs: Set<Int32> = Self.runOnMainSync {
            Set(NSWorkspace.shared.runningApplications.compactMap { app -> Int32? in
                guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != excludingPID else {
                    return nil
                }
                return app.processIdentifier
            })
        }
        var seen = Set<Int32>()
        var ordered: [Int32] = []
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                let layer = (info[kCGWindowLayer as String] as? Int) ?? 1
                guard layer == 0, let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                      regularPIDs.contains(pid), seen.insert(pid).inserted else { continue }
                ordered.append(pid)
            }
        }
        for pid in regularPIDs where seen.insert(pid).inserted { ordered.append(pid) }
        return ordered
    }

    private func runningAppMeta(pid: Int32) -> (bundleID: String, name: String)? {
        Self.runOnMainSync {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, !app.isTerminated else { return nil }
            let bundle = app.bundleIdentifier ?? "pid.\(pid)"
            let name = app.localizedName ?? bundle
            return (bundle, name)
        }
    }

    private static func runOnMainSync<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }
}

private final class LockedPIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: Int32?
    func set(_ value: Int32?) { lock.withLock { pid = value } }
    func get() -> Int32? { lock.withLock { pid } }
}
