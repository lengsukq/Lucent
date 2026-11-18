import AppKit
import AVKit
import CoreMedia
import Foundation
import LucentCore
import SwiftUI

enum PlayerKeyboardCommand: Equatable {
    case togglePlayPause
    case seekRelative(Double)
    case adjustVolume(Float)
    case toggleMute
    case stepSpeed(Int)
    case resetSpeed
    case frameStep(Int)
    case toggleFullScreen
    case stepEpisode(Int)
    case togglePlaylist
    case escape

    static func parse(event: NSEvent, allowWindowCommands: Bool) -> PlayerKeyboardCommand? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = event.keyCode
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if code == 49 && flags.isEmpty { return .togglePlayPause }
        if code == 123 {
            if flags.isEmpty { return .seekRelative(-5) }
            if flags == [.option] || flags == [.command] { return .seekRelative(-15) }
            if flags == [.shift] { return allowWindowCommands ? .stepEpisode(-1) : .seekRelative(-15) }
            return nil
        }
        if code == 124 {
            if flags.isEmpty { return .seekRelative(5) }
            if flags == [.option] || flags == [.command] { return .seekRelative(15) }
            if flags == [.shift] { return allowWindowCommands ? .stepEpisode(1) : .seekRelative(15) }
            return nil
        }
        if code == 126 && flags.isEmpty { return .adjustVolume(0.10) }
        if code == 125 && flags.isEmpty { return .adjustVolume(-0.10) }

        if flags == [.command, .control] && chars == "f" {
            return allowWindowCommands ? .toggleFullScreen : nil
        }
        guard flags.isEmpty else { return nil }

        switch chars {
        case "m": return .toggleMute
        case "[", "-", "c": return .stepSpeed(-1)
        case "]", "=", "+", "x": return .stepSpeed(1)
        case "r", "z", "1", "0", "\\": return .resetSpeed
        case ",": return .frameStep(-1)
        case ".": return .frameStep(1)
        case "f": return allowWindowCommands ? .toggleFullScreen : nil
        case "p": return allowWindowCommands ? .stepEpisode(-1) : nil
        case "n": return allowWindowCommands ? .stepEpisode(1) : nil
        case "l": return allowWindowCommands ? .togglePlaylist : nil
        default: break
        }
        if code == 53 && allowWindowCommands { return .escape }
        return nil
    }
}

enum PlayerRateHelper {
    static let presets: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    static func isNonUnit(_ rate: Float) -> Bool {
        abs(rate - 1.0) > 0.01
    }

    static func format(_ rate: Float) -> String {
        let rounded = (rate * 100).rounded() / 100
        return "\(String(format: "%g", rounded))×"
    }

    static func steppedRate(from current: Float, delta: Int) -> Float {
        let base = current > 0 ? current : 1.0
        if delta > 0 {
            return presets.first(where: { $0 > base + 0.02 }) ?? presets.last ?? 2.0
        } else {
            return presets.last(where: { $0 < base - 0.02 }) ?? presets.first ?? 0.5
        }
    }

    @MainActor
    static func seekPreservingState(
        player: AVPlayer,
        targetSeconds: Double,
        preferredRate: Float
    ) {
        let wasActive = player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            || player.rate != 0
        let resumeRate: Float = {
            if preferredRate > 0 { return preferredRate }
            if player.rate > 0 { return player.rate }
            return 1.0
        }()

        var clampedSeconds = max(0, targetSeconds)
        if let duration = player.currentItem?.duration, duration.isNumeric && duration.seconds > 0.2 {
            clampedSeconds = min(clampedSeconds, max(0, duration.seconds - 0.05))
        }
        let targetTime = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished, wasActive else { return }
            Task { @MainActor in
                player.defaultRate = resumeRate
                if player.rate != resumeRate {
                    player.playImmediately(atRate: resumeRate)
                }
            }
        }
    }
}

@MainActor
final class InteractiveAVPlayerView: AVPlayerView {
    var capturesAllWindowKeys: Bool = false
    var onMouseActivity: (() -> Void)?
    var onCommand: ((PlayerKeyboardCommand) -> Bool)?

    private var tracker: NSTrackingArea?
    nonisolated(unsafe) private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? cleanupKeyMonitor() : installKeyMonitorIfNeeded()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracker { removeTrackingArea(tracker) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracker = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseActivity?()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseActivity?()
        super.mouseEntered(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseActivity?()
        if capturesAllWindowKeys, event.clickCount == 2 {
            let local = convert(event.locationInWindow, from: nil)
            if local.y > 72 && local.y < bounds.height - 56 {
                window?.toggleFullScreen(nil)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if dispatchPlayerKey(event) { return }
        super.keyDown(with: event)
    }

    func cleanupKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.interceptWindowKeyDown(event) ? nil : event
        }
    }

    private func interceptWindowKeyDown(_ event: NSEvent) -> Bool {
        guard let targetWindow = window,
              event.window === targetWindow,
              targetWindow.isKeyWindow,
              targetWindow.attachedSheet == nil else { return false }

        if let responder = targetWindow.firstResponder {
            if responder is NSText || responder is NSTextField { return false }
            if !capturesAllWindowKeys {
                guard let respView = responder as? NSView,
                      respView === self || respView.isDescendant(of: self) else { return false }
            }
        } else if !capturesAllWindowKeys {
            return false
        }
        return dispatchPlayerKey(event)
    }

    private func dispatchPlayerKey(_ event: NSEvent) -> Bool {
        guard let cmd = PlayerKeyboardCommand.parse(event: event, allowWindowCommands: capturesAllWindowKeys),
              let onCommand else { return false }
        onMouseActivity?()
        return onCommand(cmd)
    }
}

struct PlayerResetSpeedPill: View {
    let rateText: String
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 4 : 5) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(compact
                     ? L10n.pick("\(rateText) · 还原 1×", "\(rateText) · Reset 1×")
                     : L10n.pick("当前 \(rateText) · 还原 1.0× (R)", "Speed \(rateText) · Reset 1.0× (R)"))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 4.5 : 6)
            .background(Color.black.opacity(0.76), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.cyan.opacity(0.68), lineWidth: 1.0) }
            .shadow(color: .black.opacity(0.32), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help(L10n.pick("点击一键恢复 1.0× 正常倍速（快捷键 R / Z / 1）", "Click to restore 1.0× normal playback speed (R / Z / 1)"))
    }
}

struct PlayerOSDToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8) }
            .allowsHitTesting(false)
    }
}
