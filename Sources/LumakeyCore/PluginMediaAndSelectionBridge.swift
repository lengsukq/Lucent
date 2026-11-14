import AppKit
import ApplicationServices
import AVFoundation
import Foundation

public struct PluginSelectionSnapshot: Sendable, Hashable {
    public let text: String
    public let sourceApp: String
    public let bundleIdentifier: String

    public init(text: String = "", sourceApp: String = "", bundleIdentifier: String = "") {
        self.text = text
        self.sourceApp = sourceApp
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum PluginSelectionReader {
    public static func captureFrontmostSelection(
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> PluginSelectionSnapshot {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { readFrontmostSelectionOnMain(excludingPID: excludingPID) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { readFrontmostSelectionOnMain(excludingPID: excludingPID) }
        }
    }

    @MainActor
    private static func readFrontmostSelectionOnMain(excludingPID: pid_t) -> PluginSelectionSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return PluginSelectionSnapshot()
        }
        let appName = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        guard app.processIdentifier != excludingPID, AXIsProcessTrusted() else {
            return PluginSelectionSnapshot(text: "", sourceApp: appName, bundleIdentifier: bundleID)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusStatus == .success, let focusedObj = focusedRef,
              CFGetTypeID(focusedObj) == AXUIElementGetTypeID() else {
            return PluginSelectionSnapshot(text: "", sourceApp: appName, bundleIdentifier: bundleID)
        }
        let focusedElement = unsafeDowncast(focusedObj, to: AXUIElement.self)

        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let directText = selectedRef as? String, !directText.isEmpty {
            return PluginSelectionSnapshot(text: directText, sourceApp: appName, bundleIdentifier: bundleID)
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeObj = rangeRef {
            var rangedTextRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                focusedElement,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeObj,
                &rangedTextRef
            ) == .success, let rangedText = rangedTextRef as? String, !rangedText.isEmpty {
                return PluginSelectionSnapshot(text: rangedText, sourceApp: appName, bundleIdentifier: bundleID)
            }
        }

        return PluginSelectionSnapshot(text: "", sourceApp: appName, bundleIdentifier: bundleID)
    }
}

public final class PluginAudioBridgePlayer: @unchecked Sendable {
    public static let shared = PluginAudioBridgePlayer()

    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var synthesizer: AVSpeechSynthesizer?

    private init() {}

    public func play(path: String) throws -> [String: Any] {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LumakeyError.pluginExecutionFailed("音频文件不存在：\(url.path)")
        }
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.prepareToPlay()
        lock.withLock {
            synthesizer?.stopSpeaking(at: .immediate)
            player?.stop()
            player = audioPlayer
        }
        let started = audioPlayer.play()
        return ["playing": started, "mode": "file", "path": url.path, "duration": audioPlayer.duration]
    }

    public func speak(text: String, language: String? = nil) -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["playing": false, "mode": "tts", "reason": "empty_text"]
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        if let language, !language.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        lock.withLock {
            player?.stop()
            player = nil
            let synth = synthesizer ?? AVSpeechSynthesizer()
            synthesizer = synth
            synth.stopSpeaking(at: .immediate)
            synth.speak(utterance)
        }
        return ["playing": true, "mode": "tts", "length": trimmed.count, "language": language ?? "system"]
    }

    public func stop() -> [String: Any] {
        lock.withLock {
            player?.stop()
            player = nil
            synthesizer?.stopSpeaking(at: .immediate)
        }
        return ["stopped": true]
    }
}
