import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

@MainActor
private final class LumaLinkCurtainOverlay {
    static let shared = LumaLinkCurtainOverlay()
    private var windows: [NSWindow] = []
    private(set) var isActive = false

    func setActive(_ active: Bool) {
        if active == isActive { return }
        if active {
            dismissAll()
            for screen in NSScreen.screens {
                let win = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                win.level = .screenSaver
                win.isOpaque = true
                win.backgroundColor = .black
                win.ignoresMouseEvents = true
                win.sharingType = .none
                win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

                let label = NSTextField(labelWithString: "流光随行 LumaLink · 隐私幕布保护中（仅物理屏防窥）")
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.textColor = NSColor.white.withAlphaComponent(0.16)
                label.alignment = .center
                let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
                root.wantsLayer = true
                root.layer?.backgroundColor = NSColor.black.cgColor
                label.translatesAutoresizingMaskIntoConstraints = false
                root.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: root.centerYAnchor)
                ])
                win.contentView = root
                win.orderFrontRegardless()
                windows.append(win)
            }
            isActive = !windows.isEmpty
        } else {
            dismissAll()
            isActive = false
        }
    }

    private func dismissAll() {
        for win in windows { win.orderOut(nil) }
        windows.removeAll()
    }
}

public final class LumaLinkSystemControlService: @unchecked Sendable {
    public static let shared = LumaLinkSystemControlService()

    private let lock = NSLock()
    private var caffeineAssertionID: IOPMAssertionID = 0
    private var _caffeineActive = false
    private var _curtainActive = false

    private init() {}

    public var isCaffeineActive: Bool { lock.withLock { _caffeineActive } }
    public var isCurtainActive: Bool { lock.withLock { _curtainActive } }

    public func readAudioState() -> (volumePercent: Int, isMuted: Bool) {
        guard let dev = defaultOutputDeviceID() else { return (50, false) }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(dev, &addr) {
            _ = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol)
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var mSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(dev, &muteAddr) {
            _ = AudioObjectGetPropertyData(dev, &muteAddr, 0, nil, &mSize, &muted)
        }
        return (Int((vol * 100).rounded()).clamped(to: 0...100), muted != 0)
    }

    public func setVolume(percent: Int) {
        guard let dev = defaultOutputDeviceID() else { return }
        var vol = Float32(percent.clamped(to: 0...100)) / 100.0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(dev, &addr) {
            _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        }
    }

    public func setMute(command: String) {
        guard let dev = defaultOutputDeviceID() else { return }
        let current = readAudioState().isMuted
        let nextMuted: Bool = switch command.lowercased() {
        case "true", "on", "1": true
        case "false", "off", "0": false
        default: !current
        }
        var val: UInt32 = nextMuted ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(dev, &addr) {
            _ = AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
        }
    }

    public func triggerMedia(command: String) {
        let key: Int32? = switch command {
        case "playPause": 16
        case "next": 17
        case "prev": 18
        case "brightnessUp": 2
        case "brightnessDown": 3
        default: nil
        }
        guard let key else { return }
        DispatchQueue.main.async {
            Self.postSystemDefinedKey(key)
        }
    }

    public func triggerShortcut(command: String) {
        DispatchQueue.main.async {
            switch command {
            case "missionControl": Self.postKeyCombo(keyCode: 126, flags: .maskControl)
            case "spaceLeft": Self.postKeyCombo(keyCode: 123, flags: .maskControl)
            case "spaceRight": Self.postKeyCombo(keyCode: 124, flags: .maskControl)
            case "spotlight": Self.postKeyCombo(keyCode: 49, flags: .maskCommand)
            case "forceQuit": Self.postKeyCombo(keyCode: 53, flags: [.maskCommand, .maskAlternate])
            case "lockScreen": Self.postKeyCombo(keyCode: 12, flags: [.maskControl, .maskCommand])
            default: break
            }
        }
    }

    public func pasteTextToFocusedApp(_ text: String) {
        DispatchQueue.main.async {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(35)) {
                Self.postKeyCombo(keyCode: 9, flags: .maskCommand)
            }
        }
    }

    public func triggerPower(command: String, muteOnCurtain: Bool) {
        switch command {
        case "caffeineOn": setCaffeine(true)
        case "caffeineOff": setCaffeine(false)
        case "caffeineToggle": setCaffeine(!isCaffeineActive)
        case "curtainOn": setCurtain(true, mute: muteOnCurtain)
        case "curtainOff": setCurtain(false, mute: false)
        case "curtainToggle": setCurtain(!isCurtainActive, mute: muteOnCurtain)
        case "lockScreen": triggerShortcut(command: "lockScreen")
        case "sleep":
            Task.detached(priority: .utility) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                proc.arguments = ["sleepnow"]
                try? proc.run()
            }
        default: break
        }
    }

    public func setCaffeine(_ active: Bool) {
        lock.withLock {
            guard active != _caffeineActive else { return }
            if active {
                var id: IOPMAssertionID = 0
                let res = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Lumakey LumaLink 防休眠保护" as CFString,
                    &id
                )
                if res == kIOReturnSuccess {
                    caffeineAssertionID = id
                    _caffeineActive = true
                }
            } else {
                if caffeineAssertionID != 0 {
                    IOPMAssertionRelease(caffeineAssertionID)
                    caffeineAssertionID = 0
                }
                _caffeineActive = false
            }
        }
    }

    public func setCurtain(_ active: Bool, mute: Bool) {
        lock.withLock { _curtainActive = active }
        if active && mute {
            setMute(command: "true")
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LumaLinkCurtainOverlay.shared.setActive(active)
            }
        } else {
            DispatchQueue.main.async {
                LumaLinkCurtainOverlay.shared.setActive(active)
            }
        }
    }

    public func releaseAllGuards() {
        setCaffeine(false)
        setCurtain(false, mute: false)
        StatusScreenOverlayService.shared.dismiss()
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var dev = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return status == noErr && dev != AudioDeviceID(kAudioObjectUnknown) ? dev : nil
    }

    @MainActor
    private static func postSystemDefinedKey(_ key: Int32) {
        for flagBits in [0x0A00, 0x0B00] {
            let data1 = Int((key << 16) | Int32(flagBits))
            if let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flagBits)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )?.cgEvent {
                ev.post(tap: .cghidEventTap)
            }
        }
    }

    @MainActor
    private static func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
