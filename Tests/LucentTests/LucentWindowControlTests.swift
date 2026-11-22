import CoreGraphics
import Foundation
import LucentCore
import LucentFoundation
import LucentSystem
import Testing

private final class MockWindowHardware: SystemWindowHardware, @unchecked Sendable {
    private let lock = NSLock()
    var trusted: Bool
    var mockDisplays: [SystemDisplayRect]
    var mockWindows: [ManagedWindowInfo]
    var launchedBundleIDs: [String] = []
    var moveHistory: [(pid: Int32, windowIndex: Int, frame: CGRect, activate: Bool)] = []
    var launchFactory: ((String) -> ManagedWindowInfo?)?

    init(trusted: Bool = true, displays: [SystemDisplayRect], windows: [ManagedWindowInfo]) {
        self.trusted = trusted
        self.mockDisplays = displays
        self.mockWindows = windows
    }

    func isAccessibilityTrusted() -> Bool { lock.withLock { trusted } }
    func displays() -> [SystemDisplayRect] { lock.withLock { mockDisplays } }
    func listWindows(excludingPID: Int32) -> [ManagedWindowInfo] {
        lock.withLock { mockWindows.filter { $0.pid != excludingPID } }
    }

    func frontmostWindow(preferredPID: Int32?, excludingPID: Int32) -> ManagedWindowInfo? {
        lock.withLock {
            let valid = mockWindows.filter { $0.pid != excludingPID && !$0.isMinimized }
            if let pref = preferredPID, let match = valid.first(where: { $0.pid == pref }) { return match }
            return valid.first(where: \.isFocused) ?? valid.first
        }
    }

    func setWindowFrame(
        pid: Int32, windowIndex: Int, titleHint: String?, frame: CGRect, activate: Bool
    ) -> CGRect? {
        lock.withLock {
            guard let idx = mockWindows.firstIndex(where: { $0.pid == pid && $0.windowIndex == windowIndex }) else {
                return nil
            }
            let old = mockWindows[idx]
            let dispIdx = WindowLayoutGeometry.bestDisplayIndex(for: frame, in: mockDisplays)
            let dispID = mockDisplays.indices.contains(dispIdx) ? mockDisplays[dispIdx].displayID : old.displayID
            mockWindows[idx] = ManagedWindowInfo(
                pid: old.pid, bundleID: old.bundleID, appName: old.appName, title: old.title,
                windowIndex: old.windowIndex, frame: frame, displayID: dispID, displayIndex: dispIdx,
                isFocused: old.isFocused, isMinimized: false, isResizable: old.isResizable
            )
            moveHistory.append((pid, windowIndex, frame, activate))
            return frame
        }
    }

    func launchApplication(bundleID: String) -> Int32? {
        lock.withLock {
            launchedBundleIDs.append(bundleID)
            guard let created = launchFactory?(bundleID) else { return nil }
            mockWindows.append(created)
            return created.pid
        }
    }
}

private func dualDisplayFixture() -> [SystemDisplayRect] {
    [
        SystemDisplayRect(
            displayID: 101, name: "Built-in Retina", isMain: true, index: 0,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 815)
        ),
        SystemDisplayRect(
            displayID: 202, name: "Studio 4K", isMain: false, index: 1,
            frame: CGRect(x: 1440, y: -540, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 1440, y: -515, width: 2560, height: 1415)
        )
    ]
}

@Test func quartzRectConversionHandlesMultiDisplayTopologies() {
    let primaryVis = WindowLayoutGeometry.quartzRect(
        fromCocoa: CGRect(x: 0, y: 60, width: 1440, height: 815),
        primaryScreenHeight: 900
    )
    #expect(primaryVis == CGRect(x: 0, y: 25, width: 1440, height: 815))

    let upperDisplayVis = WindowLayoutGeometry.quartzRect(
        fromCocoa: CGRect(x: -560, y: 900, width: 2560, height: 1415),
        primaryScreenHeight: 900
    )
    #expect(upperDisplayVis == CGRect(x: -560, y: -1415, width: 2560, height: 1415))

    let rightTallVis = WindowLayoutGeometry.quartzRect(
        fromCocoa: CGRect(x: 1440, y: 0, width: 2560, height: 1415),
        primaryScreenHeight: 900
    )
    #expect(rightTallVis == CGRect(x: 1440, y: -515, width: 2560, height: 1415))
}

@Test func snapPresetsComputeExactNonOverlappingGeometryWithGap() {
    let displays = dualDisplayFixture()
    let initial = CGRect(x: 100, y: 100, width: 800, height: 600)
    let gap: CGFloat = 10

    let left = WindowLayoutGeometry.targetFrame(for: .leftHalf, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    let right = WindowLayoutGeometry.targetFrame(for: .rightHalf, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    #expect(left.minX == 10)
    #expect(left.minY == 35)
    #expect(right.minX - left.maxX == gap)
    #expect(right.maxX == 1430)
    #expect(left.intersection(right).isNull)

    let l3 = WindowLayoutGeometry.targetFrame(for: .leftThird, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    let c3 = WindowLayoutGeometry.targetFrame(for: .centerThird, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    let r3 = WindowLayoutGeometry.targetFrame(for: .rightThird, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    #expect(c3.minX - l3.maxX == gap)
    #expect(r3.minX - c3.maxX == gap)
    #expect(r3.maxX == 1430)

    let tl = WindowLayoutGeometry.targetFrame(for: .topLeft, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    let br = WindowLayoutGeometry.targetFrame(for: .bottomRight, currentFrame: initial, displays: displays, currentDisplayIndex: 0, gap: gap).frame
    #expect(br.minX - tl.maxX == gap)
    #expect(br.minY - tl.maxY == gap)

    let movedNext = WindowLayoutGeometry.targetFrame(for: .nextDisplay, currentFrame: left, displays: displays, currentDisplayIndex: 0, gap: 0)
    #expect(movedNext.displayIndex == 1)
    #expect(displays[1].visibleFrame.contains(movedNext.frame))
    let wrappedBack = WindowLayoutGeometry.targetFrame(for: .nextDisplay, currentFrame: movedNext.frame, displays: displays, currentDisplayIndex: 1, gap: 0)
    #expect(wrappedBack.displayIndex == 0)
}

@Test func windowControlRouterSnapsRestoresAndEnforcesPermissions() {
    let displays = dualDisplayFixture()
    let startFrame = CGRect(x: 120, y: 120, width: 720, height: 520)
    let win = ManagedWindowInfo(
        pid: 4200, bundleID: "com.microsoft.VSCode", appName: "VS Code", title: "Lucent",
        windowIndex: 0, frame: startFrame, displayID: 101, displayIndex: 0,
        isFocused: true, isMinimized: false, isResizable: true
    )
    let hardware = MockWindowHardware(trusted: false, displays: displays, windows: [win])
    let router = PluginWindowControlRouter(hardware: hardware, ownPID: 9999)

    let denied = router.snap(preset: .leftHalf, gap: 8)
    #expect(denied.status == "permission_denied")

    hardware.trusted = true
    let snapped = router.snap(preset: .leftHalf, gap: 8)
    #expect(snapped.status == "applied")
    #expect(snapped.appliedFrame?.minX == 8)

    let restored = router.snap(preset: .restore)
    #expect(restored.status == "applied")
    #expect(restored.appliedFrame == startFrame)

    let secondRestore = router.snap(preset: .restore)
    #expect(secondRestore.status == "nothing_to_restore")
}

@Test func workspaceApplyHandlesMultiWindowSameAppFallbackDisplayAndAutoLaunch() {
    let singleDisplay = [dualDisplayFixture()[0]]
    let chromeA = ManagedWindowInfo(
        pid: 5100, bundleID: "com.google.Chrome", appName: "Chrome", title: "Docs",
        windowIndex: 0, frame: CGRect(x: 40, y: 40, width: 600, height: 500),
        displayID: 101, displayIndex: 0, isFocused: true, isMinimized: false, isResizable: true
    )
    let chromeB = ManagedWindowInfo(
        pid: 5100, bundleID: "com.google.Chrome", appName: "Chrome", title: "Console",
        windowIndex: 1, frame: CGRect(x: 100, y: 80, width: 600, height: 500),
        displayID: 101, displayIndex: 0, isFocused: false, isMinimized: false, isResizable: true
    )
    let hardware = MockWindowHardware(trusted: true, displays: singleDisplay, windows: [chromeA, chromeB])
    hardware.launchFactory = { bundleID in
        guard bundleID == "com.apple.Terminal" else { return nil }
        return ManagedWindowInfo(
            pid: 5200, bundleID: bundleID, appName: "Terminal", title: "zsh",
            windowIndex: 0, frame: CGRect(x: 80, y: 80, width: 500, height: 400),
            displayID: 101, displayIndex: 0, isFocused: false, isMinimized: false, isResizable: true
        )
    }

    let router = PluginWindowControlRouter(hardware: hardware, ownPID: 9999)
    let slots = [
        WindowWorkspaceSlot(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Docs", windowIndex: 0, displayIndex: 0, displayID: 101, rx: 0, ry: 0, rw: 0.5, rh: 1),
        WindowWorkspaceSlot(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Console", windowIndex: 1, displayIndex: 1, displayID: 202, rx: 0.5, ry: 0, rw: 0.5, rh: 1),
        WindowWorkspaceSlot(bundleID: "com.apple.Terminal", appName: "Terminal", windowIndex: 0, displayIndex: 0, displayID: 101, rx: 0, ry: 0.5, rw: 0.5, rh: 0.5)
    ]

    let result = router.applyWorkspace(slots: slots, gap: 0, launchMissing: true)
    #expect(result.status == "applied")
    #expect(result.movedCount == 3)
    #expect(result.launchedApps == ["Terminal"])
    #expect(result.usedFallbackDisplay == true)
    #expect(hardware.moveHistory.map(\.windowIndex) == [0, 1, 0])
}

@Test func windowControlBridgeGatingTCCAuditAndManifestValidation() {
    let blocked = PluginHostBridgeHandlers.dispatch(
        capability: .windowControl, action: "status", params: [:], hostContext: .default
    )
    #expect(blocked["ok"] as? Bool == false)
    #expect(blocked["error"] as? String == "unsupported_context")

    #expect(PluginHostTCCBroker.requiredTCC(for: .windowControl) == .accessibility)

    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let pluginDir = repoRoot.appendingPathComponent("plugin-demo/window-snap", isDirectory: true)
    let descriptor = PluginSystem.loadPlugin(at: pluginDir, in: pluginDir.deletingLastPathComponent())
    #expect(descriptor.isValid)
    #expect(descriptor.declaredCapabilities.contains(.floatingWindow))
    #expect(descriptor.declaredCapabilities.contains(.windowControl))
    #expect(descriptor.declaredResourceScopes.isEmpty)
    #expect(descriptor.declaredCommands.count >= 20)
    #expect(PluginPermissionAudit.declaredPermissions(for: descriptor).contains(.accessibility))
}
