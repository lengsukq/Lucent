import LucentFoundation
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
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        allowCopyFallback: Bool = false
    ) -> PluginSelectionSnapshot {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                readFrontmostSelectionOnMain(excludingPID: excludingPID, allowCopyFallback: allowCopyFallback)
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                readFrontmostSelectionOnMain(excludingPID: excludingPID, allowCopyFallback: allowCopyFallback)
            }
        }
    }

    @MainActor
    private static func readFrontmostSelectionOnMain(
        excludingPID: pid_t,
        allowCopyFallback: Bool
    ) -> PluginSelectionSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return PluginSelectionSnapshot()
        }
        let appName = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        guard app.processIdentifier != excludingPID, AXIsProcessTrusted() else {
            return PluginSelectionSnapshot(text: "", sourceApp: appName, bundleIdentifier: bundleID)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let direct = readSelectionFromAX(appElement: appElement), !direct.isEmpty {
            return PluginSelectionSnapshot(text: direct, sourceApp: appName, bundleIdentifier: bundleID)
        }

        // Chromium / Electron apps lazily expose AX nodes only after AXManualAccessibility is enabled.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let manualText = readSelectionFromAX(appElement: appElement), !manualText.isEmpty {
            return PluginSelectionSnapshot(text: manualText, sourceApp: appName, bundleIdentifier: bundleID)
        }

        if allowCopyFallback {
            let copied = PluginSelectionFallback.copySelectionWithPasteboardRestore(
                appElement: appElement,
                bundleIdentifier: bundleID
            )
            if !copied.isEmpty {
                return PluginSelectionSnapshot(text: copied, sourceApp: appName, bundleIdentifier: bundleID)
            }
        }

        return PluginSelectionSnapshot(text: "", sourceApp: appName, bundleIdentifier: bundleID)
    }

    private static func readSelectionFromAX(appElement: AXUIElement) -> String? {
        for element in candidateAXElements(from: appElement) {
            if isSecureInputElement(element) { return nil }
            if let text = extractSelectedText(from: element), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func isSecureInputElement(_ element: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        return false
    }

    private static func candidateAXElements(from appElement: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = []
        if let focused = copyAXElement(appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
            candidates.append(focused)
        }
        if let window = copyAXElement(appElement, attribute: kAXFocusedWindowAttribute as CFString) {
            if let winFocused = copyAXElement(window, attribute: kAXFocusedUIElementAttribute as CFString) {
                candidates.append(winFocused)
            }
            candidates.append(window)
        }
        return candidates
    }

    private static func copyAXElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let obj = ref,
              CFGetTypeID(obj) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(obj, to: AXUIElement.self)
    }

    private static func extractSelectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let directText = selectedRef as? String, !directText.isEmpty {
            return directText
        }

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeObj = rangeRef {
            var rangedTextRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                rangeObj,
                &rangedTextRef
            ) == .success, let rangedText = rangedTextRef as? String, !rangedText.isEmpty {
                return rangedText
            }
        }

        var markerRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success,
           let markerRange = markerRangeRef {
            var markerTextRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXStringForTextMarkerRange" as CFString,
                markerRange,
                &markerTextRef
            ) == .success, let markerText = markerTextRef as? String, !markerText.isEmpty {
                return markerText
            }
        }

        return nil
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
            throw LucentError.pluginExecutionFailed("音频文件不存在：\(url.path)")
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
