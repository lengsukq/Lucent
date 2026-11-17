import AppKit
import Foundation
import Testing
@testable import LumakeyCore

@MainActor
private final class MockTrackableWindow: NSWindow {
    var mockVisible = true
    var mockMiniaturized = false
    var orderOutCalls = 0
    var orderBackCalls = 0

    override var isVisible: Bool { mockVisible }
    override var isMiniaturized: Bool { mockMiniaturized }

    override func orderOut(_ sender: Any?) {
        orderOutCalls += 1
        mockVisible = false
    }

    override func orderBack(_ sender: Any?) {
        orderBackCalls += 1
        mockVisible = true
    }
}

@Suite("Capture Focus Guard & Background Window Preservation Tests")
struct LumakeyCaptureFocusGuardTests {
    @Test("resolveTargetApp ignores self PID and prefers explicit non-self target app")
    @MainActor
    func resolveTargetAppRespectsSelfAndPreferred() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfApp = NSRunningApplication(processIdentifier: selfPID)
        let externalApp = NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != selfPID && !$0.isTerminated && $0.activationPolicy == .regular
        }

        #expect(CaptureFocusGuard.resolveTargetApp(preferred: selfApp, frontmost: selfApp, selfPID: selfPID) == nil)
        if let externalApp {
            #expect(CaptureFocusGuard.resolveTargetApp(preferred: selfApp, frontmost: externalApp, selfPID: selfPID)?.processIdentifier == externalApp.processIdentifier)
            #expect(CaptureFocusGuard.resolveTargetApp(preferred: externalApp, frontmost: selfApp, selfPID: selfPID)?.processIdentifier == externalApp.processIdentifier)
        }
    }

    @Test("shouldSuppressBackgroundWindow filters only visible non-miniaturized normal key/main windows")
    @MainActor
    func backgroundWindowSuppressionFilter() {
        let normalWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        normalWin.level = .normal
        normalWin.mockVisible = true

        let floatingWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        floatingWin.level = .floating
        floatingWin.mockVisible = true

        let hiddenWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        hiddenWin.level = .normal
        hiddenWin.mockVisible = false

        let minimizedWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        minimizedWin.level = .normal
        minimizedWin.mockVisible = true
        minimizedWin.mockMiniaturized = true

        let overlayWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWin.level = .normal
        overlayWin.mockVisible = true

        let excluded: Set<ObjectIdentifier> = [ObjectIdentifier(overlayWin)]
        #expect(CaptureFocusGuard.shouldSuppressBackgroundWindow(normalWin, excluding: excluded))
        #expect(!CaptureFocusGuard.shouldSuppressBackgroundWindow(floatingWin, excluding: excluded))
        #expect(!CaptureFocusGuard.shouldSuppressBackgroundWindow(hiddenWin, excluding: excluded))
        #expect(!CaptureFocusGuard.shouldSuppressBackgroundWindow(minimizedWin, excluding: excluded))
        #expect(!CaptureFocusGuard.shouldSuppressBackgroundWindow(overlayWin, excluding: excluded))
    }

    @Test("CaptureFocusGuard suppresses background standard windows during external capture and orders them back on finish")
    @MainActor
    func suppressAndRestoreLifecycle() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        guard let externalApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != selfPID && !$0.isTerminated && $0.activationPolicy == .regular
        }) else {
            return
        }

        let settingsWin = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWin.level = .normal
        settingsWin.mockVisible = true

        let pinPanel = MockTrackableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pinPanel.level = .floating
        pinPanel.mockVisible = true

        let guardObj = CaptureFocusGuard()
        guardObj.prepareForNewCapture(preferredApp: externalApp)
        #expect(guardObj.hasPreviousTargetApp)

        guardObj.suppressBackgroundWindowsIfNeeded(excluding: [], candidateWindows: [settingsWin, pinPanel])
        #expect(guardObj.suppressedWindowCount == 1)
        #expect(settingsWin.orderOutCalls == 1)
        #expect(!settingsWin.isVisible)
        #expect(pinPanel.orderOutCalls == 0)
        #expect(pinPanel.isVisible)

        // Do not call activate() on externalApp in tests to avoid shifting the developer's active window.
        guardObj.finishRestore(restorePreviousApp: false)
        #expect(!guardObj.hasPreviousTargetApp)
        #expect(guardObj.suppressedWindowCount == 0)
        #expect(settingsWin.orderBackCalls == 1)
        #expect(settingsWin.isVisible)
    }
}
