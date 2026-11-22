import CoreGraphics
import Foundation
import LucentFoundation
import LucentSystem

public struct WindowSnapOutcome: Equatable, Sendable {
    public let status: String
    public let preset: WindowSnapPreset
    public let window: ManagedWindowInfo?
    public let appliedFrame: CGRect?
    public let display: SystemDisplayRect?
    public let message: String

    public init(
        status: String,
        preset: WindowSnapPreset,
        window: ManagedWindowInfo? = nil,
        appliedFrame: CGRect? = nil,
        display: SystemDisplayRect? = nil,
        message: String
    ) {
        self.status = status
        self.preset = preset
        self.window = window
        self.appliedFrame = appliedFrame
        self.display = display
        self.message = message
    }
}

public struct WorkspaceApplyOutcome: Equatable, Sendable {
    public let status: String
    public let movedCount: Int
    public let skippedCount: Int
    public let missingApps: [String]
    public let launchedApps: [String]
    public let usedFallbackDisplay: Bool

    public init(
        status: String,
        movedCount: Int,
        skippedCount: Int,
        missingApps: [String],
        launchedApps: [String],
        usedFallbackDisplay: Bool
    ) {
        self.status = status
        self.movedCount = movedCount
        self.skippedCount = skippedCount
        self.missingApps = missingApps
        self.launchedApps = launchedApps
        self.usedFallbackDisplay = usedFallbackDisplay
    }
}

public final class PluginWindowControlRouter: @unchecked Sendable {
    public static let shared = PluginWindowControlRouter(hardware: SystemWindowControlAdapter())
    public static let maxWorkspaceSlots = 24
    private static let maxUndoEntries = 32

    private let hardware: any SystemWindowHardware
    private let ownPID: Int32
    private let lock = NSLock()
    private var undoFrames: [String: CGRect] = [:]
    private var undoOrder: [String] = []

    public init(hardware: any SystemWindowHardware, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.hardware = hardware
        self.ownPID = ownPID
    }

    public func status(preferredPID: Int32? = nil) -> (
        trusted: Bool,
        displays: [SystemDisplayRect],
        activeWindow: ManagedWindowInfo?,
        windows: [ManagedWindowInfo],
        canUndo: Bool
    ) {
        let displays = hardware.displays()
        let trusted = hardware.isAccessibilityTrusted()
        guard trusted else {
            return (false, displays, nil, [], false)
        }
        let active = hardware.frontmostWindow(preferredPID: preferredPID, excludingPID: ownPID)
        let windows = hardware.listWindows(excludingPID: ownPID)
        let canUndo = lock.withLock {
            if let key = active?.stableUndoKey, undoFrames[key] != nil { return true }
            return !undoFrames.isEmpty
        }
        return (true, displays, active, windows, canUndo)
    }

    public func snap(
        preset: WindowSnapPreset,
        gap: CGFloat = 0,
        explicitPID: Int32? = nil,
        windowIndex: Int? = nil,
        preferredPID: Int32? = nil
    ) -> WindowSnapOutcome {
        guard hardware.isAccessibilityTrusted() else {
            return WindowSnapOutcome(
                status: "permission_denied", preset: preset,
                message: L10n.pick("宿主尚未获得「辅助功能」权限", "Accessibility permission is not granted to Lucent")
            )
        }
        let displays = hardware.displays()
        guard !displays.isEmpty else {
            return WindowSnapOutcome(
                status: "no_display", preset: preset,
                message: L10n.pick("未检测到可用显示器", "No active displays detected")
            )
        }
        guard let target = resolveTargetWindow(explicitPID: explicitPID, windowIndex: windowIndex, preferredPID: preferredPID) else {
            return WindowSnapOutcome(
                status: "no_target_window", preset: preset,
                message: L10n.pick("未找到可调整的前台应用窗口", "No resizable foreground application window found")
            )
        }

        let destination: CGRect
        let targetDisplayIndex: Int
        if preset == .restore {
            guard let saved = popUndoFrame(for: target.stableUndoKey) else {
                return WindowSnapOutcome(
                    status: "nothing_to_restore", preset: preset, window: target,
                    message: L10n.pick("当前窗口暂无可撤销的分屏记录", "No previous position saved for this window")
                )
            }
            destination = saved
            targetDisplayIndex = WindowLayoutGeometry.bestDisplayIndex(for: saved, in: displays)
        } else {
            let currentIdx = WindowLayoutGeometry.bestDisplayIndex(for: target.frame, in: displays)
            let computed = WindowLayoutGeometry.targetFrame(
                for: preset, currentFrame: target.frame, displays: displays,
                currentDisplayIndex: currentIdx, gap: gap
            )
            recordUndoFrame(target.frame, for: target.stableUndoKey)
            destination = computed.frame
            targetDisplayIndex = computed.displayIndex
        }

        guard let applied = hardware.setWindowFrame(
            pid: target.pid, windowIndex: target.windowIndex, titleHint: target.title,
            frame: destination, activate: false
        ) else {
            return WindowSnapOutcome(
                status: "failed", preset: preset, window: target,
                message: L10n.pick("应用窗口拒绝调整尺寸或已关闭", "The target window could not be moved or resized")
            )
        }
        let targetDisplay = displays.indices.contains(targetDisplayIndex) ? displays[targetDisplayIndex] : displays.first
        return WindowSnapOutcome(
            status: "applied", preset: preset, window: target,
            appliedFrame: applied, display: targetDisplay,
            message: "\(preset.localizedTitle) · \(target.appName)"
        )
    }

    public func applyWorkspace(
        slots rawSlots: [WindowWorkspaceSlot],
        gap: CGFloat = 0,
        launchMissing: Bool = true
    ) -> WorkspaceApplyOutcome {
        let slots = Array(rawSlots.prefix(Self.maxWorkspaceSlots))
        guard !slots.isEmpty else {
            return WorkspaceApplyOutcome(status: "empty", movedCount: 0, skippedCount: 0, missingApps: [], launchedApps: [], usedFallbackDisplay: false)
        }
        guard hardware.isAccessibilityTrusted() else {
            return WorkspaceApplyOutcome(status: "permission_denied", movedCount: 0, skippedCount: slots.count, missingApps: [], launchedApps: [], usedFallbackDisplay: false)
        }
        let displays = hardware.displays()
        guard !displays.isEmpty else {
            return WorkspaceApplyOutcome(status: "no_display", movedCount: 0, skippedCount: slots.count, missingApps: [], launchedApps: [], usedFallbackDisplay: false)
        }

        var availableWindows = hardware.listWindows(excludingPID: ownPID)
        var usedKeys = Set<String>()
        var launchedBundleIDs = Set<String>()
        var movedCount = 0
        var skippedCount = 0
        var missingApps: [String] = []
        var launchedApps: [String] = []
        var usedFallbackDisplay = false

        for slot in slots {
            var matched = findUnusedWindow(for: slot, in: availableWindows, usedKeys: usedKeys)
            if matched == nil, launchMissing, !launchedBundleIDs.contains(slot.bundleID) {
                launchedBundleIDs.insert(slot.bundleID)
                if let newPID = hardware.launchApplication(bundleID: slot.bundleID) {
                    launchedApps.append(slot.appName)
                    availableWindows = hardware.listWindows(excludingPID: ownPID)
                    matched = findUnusedWindow(for: slot, in: availableWindows, usedKeys: usedKeys, preferPID: newPID)
                }
            }
            guard let window = matched else {
                skippedCount += 1
                if !missingApps.contains(slot.appName) { missingApps.append(slot.appName) }
                continue
            }
            guard let targetDisplay = WindowLayoutGeometry.resolveDisplay(
                preferredID: slot.displayID, preferredIndex: slot.displayIndex, in: displays
            ) else {
                skippedCount += 1
                continue
            }
            if let wantedID = slot.displayID, targetDisplay.displayID != wantedID,
               !displays.indices.contains(slot.displayIndex) {
                usedFallbackDisplay = true
            }
            let norm = NormalizedWindowRect(rx: slot.rx, ry: slot.ry, rw: slot.rw, rh: slot.rh)
            let rect = WindowLayoutGeometry.denormalizedFrame(norm, in: targetDisplay.visibleFrame, gap: gap)
            recordUndoFrame(window.frame, for: window.stableUndoKey)
            if hardware.setWindowFrame(
                pid: window.pid, windowIndex: window.windowIndex, titleHint: window.title,
                frame: rect, activate: true
            ) != nil {
                usedKeys.insert(window.stableUndoKey)
                movedCount += 1
            } else {
                skippedCount += 1
            }
        }

        let status: String
        if movedCount == slots.count { status = "applied" }
        else if movedCount > 0 { status = "partial" }
        else { status = "no_target_window" }
        return WorkspaceApplyOutcome(
            status: status, movedCount: movedCount, skippedCount: skippedCount,
            missingApps: missingApps, launchedApps: launchedApps, usedFallbackDisplay: usedFallbackDisplay
        )
    }

    private func resolveTargetWindow(explicitPID: Int32?, windowIndex: Int?, preferredPID: Int32?) -> ManagedWindowInfo? {
        if let pid = explicitPID, pid > 0, pid != ownPID {
            let windows = hardware.listWindows(excludingPID: ownPID).filter { $0.pid == pid }
            if let idx = windowIndex, let exact = windows.first(where: { $0.windowIndex == idx }) { return exact }
            if let visible = windows.first(where: { !$0.isMinimized }) { return visible }
            if let first = windows.first { return first }
        }
        return hardware.frontmostWindow(preferredPID: preferredPID, excludingPID: ownPID)
    }

    private func findUnusedWindow(
        for slot: WindowWorkspaceSlot,
        in windows: [ManagedWindowInfo],
        usedKeys: Set<String>,
        preferPID: Int32? = nil
    ) -> ManagedWindowInfo? {
        let candidates = windows.filter { win in
            !usedKeys.contains(win.stableUndoKey)
                && (win.bundleID == slot.bundleID || (preferPID != nil && win.pid == preferPID))
        }
        if let title = slot.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           let exactTitle = candidates.first(where: { $0.title == title }) {
            return exactTitle
        }
        if let exactIndex = candidates.first(where: { $0.windowIndex == slot.windowIndex }) {
            return exactIndex
        }
        return candidates.first(where: { !$0.isMinimized }) ?? candidates.first
    }

    private func recordUndoFrame(_ frame: CGRect, for key: String) {
        lock.withLock {
            undoFrames[key] = frame
            undoOrder.removeAll { $0 == key }
            undoOrder.append(key)
            while undoOrder.count > Self.maxUndoEntries {
                let oldest = undoOrder.removeFirst()
                undoFrames.removeValue(forKey: oldest)
            }
        }
    }

    private func popUndoFrame(for key: String) -> CGRect? {
        lock.withLock {
            undoOrder.removeAll { $0 == key }
            return undoFrames.removeValue(forKey: key)
        }
    }
}
