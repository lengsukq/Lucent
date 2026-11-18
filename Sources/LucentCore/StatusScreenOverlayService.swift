import LucentFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public final class StatusScreenOverlayService: @unchecked Sendable {
    public static let shared = StatusScreenOverlayService()

    private let lock = NSLock()
    private var _isActive = false
    private var _currentConfig: StatusScreenConfiguration?
    private var savedCaffeine = false
    private var savedMuted = false
    private var didOverrideCaffeine = false
    private var didOverrideMute = false

    @MainActor private var windows: [NSWindow] = []
    @MainActor private var hintLabels: [NSTextField] = []
    @MainActor private var localKeyMonitor: Any?
    @MainActor private var screenObserver: NSObjectProtocol?
    @MainActor private var holdTimer: Timer?
    @MainActor private var holdStartDate: Date?
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var eventTapSource: CFRunLoopSource?

    public var suppressWindowPresentationForTesting = false

    private init() {}

    public var isActive: Bool { lock.withLock { _isActive } }
    public var currentConfiguration: StatusScreenConfiguration? { lock.withLock { _currentConfig } }

    public func statusSnapshot() -> [String: Any] {
        let (active, cfg) = lock.withLock { (_isActive, _currentConfig) }
        return [
            "statusScreenActive": active,
            "statusScreenPreset": cfg?.preset ?? "",
            "statusScreenIcon": cfg?.icon ?? "",
            "statusScreenTitle": cfg?.title ?? "",
            "statusScreenBlockInput": cfg?.blockInput ?? false,
            "accessibilityTrusted": AXIsProcessTrusted()
        ]
    }

    public func activate(_ config: StatusScreenConfiguration, delaySeconds: Double = 0.0) {
        let sys = LumaLinkSystemControlService.shared
        lock.withLock {
            if !_isActive {
                savedCaffeine = sys.isCaffeineActive
                savedMuted = sys.readAudioState().isMuted
                didOverrideCaffeine = false
                didOverrideMute = false
            }
            _isActive = true
            _currentConfig = config
            if config.keepAwake && !savedCaffeine {
                didOverrideCaffeine = true
                sys.setCaffeine(true)
            }
            if config.muteAudio && !savedMuted {
                didOverrideMute = true
                sys.setMute(command: "true")
            }
        }
        guard !suppressWindowPresentationForTesting else { return }
        let presentBlock: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.presentOnMain(config) }
        }
        if delaySeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: presentBlock)
        } else if Thread.isMainThread {
            MainActor.assumeIsolated { presentOnMain(config) }
        } else {
            DispatchQueue.main.async(execute: presentBlock)
        }
    }

    public func dismiss() {
        let (wasActive, restoreCaf, prevCaf, restoreMute, prevMute) = lock.withLock {
            let active = _isActive
            _isActive = false
            _currentConfig = nil
            let rc = didOverrideCaffeine; let pc = savedCaffeine
            let rm = didOverrideMute; let pm = savedMuted
            didOverrideCaffeine = false; didOverrideMute = false
            return (active, rc, pc, rm, pm)
        }
        if wasActive {
            let sys = LumaLinkSystemControlService.shared
            if restoreCaf { sys.setCaffeine(prevCaf) }
            if restoreMute { sys.setMute(command: prevMute ? "true" : "false") }
        }
        guard !suppressWindowPresentationForTesting else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { tearDownOnMain(animated: true) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.tearDownOnMain(animated: true) } }
        }
    }

    @MainActor
    private func presentOnMain(_ config: StatusScreenConfiguration) {
        guard isActive else { return }
        tearDownOnMain(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        let animateFade = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for screen in NSScreen.screens {
            let win = StatusScreenShieldWindow(
                contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen
            )
            win.level = .screenSaver
            win.isOpaque = true
            win.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)
            win.ignoresMouseEvents = false
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

            let (root, hintLabel) = StatusScreenShieldViewBuilder.build(
                size: screen.frame.size, config: config, target: self, emergencyAction: #selector(handleEmergencyButton(_:))
            )
            win.contentView = root
            if animateFade {
                win.alphaValue = 0.0
                win.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    win.animator().alphaValue = 1.0
                }
            } else {
                win.makeKeyAndOrderFront(nil)
            }
            windows.append(win)
            hintLabels.append(hintLabel)
        }
        installInputMonitors(config: config)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive, let cfg = self.currentConfiguration else { return }
                self.presentOnMain(cfg)
            }
        }
    }

    @objc @MainActor
    private func handleEmergencyButton(_ sender: NSButton) {
        if NSApp.currentEvent?.clickCount ?? 1 >= 2 || !(currentConfiguration?.blockInput ?? true) {
            dismiss()
        }
    }

    @MainActor
    private func installInputMonitors(config: StatusScreenConfiguration) {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                if event.type == .keyDown && !event.isARepeat { self.beginEscHold(holdSeconds: config.holdSeconds) }
                else if event.type == .keyUp { self.cancelEscHold(holdSeconds: config.holdSeconds) }
                return nil
            }
            return config.blockInput ? nil : event
        }
        guard config.blockInput, AXIsProcessTrusted() else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let svc = Unmanaged<StatusScreenOverlayService>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let t = svc.eventTap { CGEvent.tapEnable(tap: t, enable: true) }
                    return nil
                }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if (type == .keyDown || type == .keyUp) && keyCode == 53 {
                    let isDown = (type == .keyDown)
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    let secs = svc.currentConfiguration?.holdSeconds ?? 2.0
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            if isDown && !isRepeat { svc.beginEscHold(holdSeconds: secs) }
                            else if !isDown { svc.cancelEscHold(holdSeconds: secs) }
                        }
                    }
                }
                return nil
            },
            userInfo: refcon
        ) {
            eventTap = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventTapSource = src
            if let src { CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes) }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    @MainActor
    private func beginEscHold(holdSeconds: Double) {
        guard holdTimer == nil else { return }
        holdStartDate = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickEscHold(holdSeconds: holdSeconds) }
        }
    }

    @MainActor
    private func tickEscHold(holdSeconds: Double) {
        guard let start = holdStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= holdSeconds { dismiss(); return }
        let remain = max(0.1, holdSeconds - elapsed)
        let msg = L10n.pick(String(format: "继续按住 Esc %.1f 秒退出…", remain), String(format: "Keep holding Esc %.1fs to exit…", remain))
        for lbl in hintLabels { lbl.stringValue = msg }
    }

    @MainActor
    private func cancelEscHold(holdSeconds: Double) {
        holdTimer?.invalidate(); holdTimer = nil; holdStartDate = nil
        let text = StatusScreenConfiguration.defaultHintText(holdSeconds: holdSeconds)
        for lbl in hintLabels { lbl.stringValue = text }
    }

    @MainActor
    private func tearDownOnMain(animated: Bool) {
        holdTimer?.invalidate(); holdTimer = nil; holdStartDate = nil
        if let obs = screenObserver { NotificationCenter.default.removeObserver(obs); screenObserver = nil }
        if let mon = localKeyMonitor { NSEvent.removeMonitor(mon); localKeyMonitor = nil }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTapSource = nil; eventTap = nil
        let closing = windows
        windows.removeAll(); hintLabels.removeAll()
        if animated && !closing.isEmpty && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                for win in closing { win.animator().alphaValue = 0.0 }
            } completionHandler: {
                MainActor.assumeIsolated {
                    for win in closing { win.orderOut(nil); win.contentView = nil }
                }
            }
        } else {
            for win in closing { win.orderOut(nil); win.contentView = nil }
        }
    }
}
