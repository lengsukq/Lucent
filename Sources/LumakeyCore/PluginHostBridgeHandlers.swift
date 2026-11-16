import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import AppKit
import Foundation

public struct PluginBridgeHostContext: Sendable {
    public let everythingIndex: EverythingIndex?
    public let clipboardReader: @Sendable () -> String
    public let clipboardWriter: @Sendable (String) -> Bool
    public let selectionReader: @Sendable () -> PluginSelectionSnapshot
    public let preCapturedSelection: PluginSelectionSnapshot?

    public init(
        everythingIndex: EverythingIndex? = nil,
        clipboardReader: (@Sendable () -> String)? = nil,
        clipboardWriter: (@Sendable (String) -> Bool)? = nil,
        selectionReader: (@Sendable () -> PluginSelectionSnapshot)? = nil,
        preCapturedSelection: PluginSelectionSnapshot? = nil
    ) {
        self.everythingIndex = everythingIndex
        self.clipboardReader = clipboardReader ?? {
            Self.runOnMainSync { NSPasteboard.general.string(forType: .string) ?? "" }
        }
        self.clipboardWriter = clipboardWriter ?? { text in
            Self.runOnMainSync {
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            }
        }
        self.selectionReader = selectionReader ?? {
            PluginSelectionReader.captureFrontmostSelection()
        }
        self.preCapturedSelection = preCapturedSelection
    }

    public static let `default` = PluginBridgeHostContext()

    private static func runOnMainSync<T: Sendable>(_ work: @MainActor @Sendable () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }
}

enum PluginHostBridgeHandlers {
    static func dispatch(
        capability: PluginCapability,
        action: String,
        params: [String: Any],
        hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        switch capability {
        case .clipboard:
            if action == "read" {
                return okJSON(capability, action, ["text": hostContext.clipboardReader()])
            } else if action == "write" {
                guard let text = params["text"] as? String else { return errorJSON("invalid_params", "缺少 text 参数", capability: capability) }
                return okJSON(capability, action, ["written": hostContext.clipboardWriter(text), "length": text.count])
            }
            return errorJSON("invalid_action", "clipboard 仅支持 read / write", capability: capability)

        case .selection:
            guard action == "read" else { return errorJSON("invalid_action", "selection 仅支持 read", capability: capability) }
            let snapshot: PluginSelectionSnapshot
            if let pre = hostContext.preCapturedSelection, !pre.text.isEmpty {
                snapshot = pre
            } else {
                let live = hostContext.selectionReader()
                snapshot = live.text.isEmpty ? (hostContext.preCapturedSelection ?? live) : live
            }
            return okJSON(capability, action, [
                "text": snapshot.text,
                "sourceApp": snapshot.sourceApp,
                "bundleIdentifier": snapshot.bundleIdentifier
            ])

        case .audio:
            switch action {
            case "play":
                guard let path = params["path"] as? String, !path.isEmpty else {
                    return errorJSON("invalid_params", "缺少 path 参数", capability: capability)
                }
                do {
                    return okJSON(capability, action, try PluginAudioBridgePlayer.shared.play(path: path))
                } catch {
                    return errorJSON("execution_failed", error.localizedDescription, capability: capability)
                }
            case "speak":
                guard let text = params["text"] as? String, !text.isEmpty else {
                    return errorJSON("invalid_params", "缺少 text 参数", capability: capability)
                }
                let language = params["language"] as? String
                return okJSON(capability, action, PluginAudioBridgePlayer.shared.speak(text: text, language: language))
            case "stop":
                return okJSON(capability, action, PluginAudioBridgePlayer.shared.stop())
            default:
                return errorJSON("invalid_action", "audio 仅支持 play / speak / stop", capability: capability)
            }

        case .ocr:
            guard action == "recognize" else { return errorJSON("invalid_action", "ocr 仅支持 recognize", capability: capability) }
            guard let path = params["imagePath"] as? String, !path.isEmpty else {
                return errorJSON("invalid_params", "缺少 imagePath 参数", capability: capability)
            }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return errorJSON("invalid_params", "图片文件不存在：\(path)", capability: capability)
            }
            do {
                let analysis = try VisionService.analyzeTextAndBarcodes(at: url)
                return okJSON(capability, action, ["text": analysis.recognizedText, "barcodes": analysis.barcodes])
            } catch {
                return errorJSON("execution_failed", error.localizedDescription, capability: capability)
            }

        case .everythingSearch:
            guard action == "search" else { return errorJSON("invalid_action", "everythingSearch 仅支持 search", capability: capability) }
            let query = params["query"] as? String ?? ""
            let limit = min(max(params["limit"] as? Int ?? 20, 1), 100)
            guard let index = hostContext.everythingIndex else {
                return okJSON(capability, action, ["indexLoaded": false, "count": 0, "hits": []])
            }
            let hits = index.search(queryText: query, limit: limit).map { hit -> [String: Any] in
                ["name": hit.name, "path": hit.url.path, "relativeParent": hit.relativeParentPath, "isDirectory": hit.isDirectory, "sizeBytes": hit.sizeBytes]
            }
            return okJSON(capability, action, ["indexLoaded": true, "count": hits.count, "hits": hits])

        case .displayInfo:
            guard action == "list" else { return errorJSON("invalid_action", "displayInfo 仅支持 list", capability: capability) }
            let displays = LumaLinkDisplayService.shared.listDisplays().map { d -> [String: Any] in
                [
                    "displayID": d.displayID, "name": d.name, "isMain": d.isMain, "currentModeKey": d.currentModeKey,
                    "modes": d.modes.map { ["modeKey": $0.modeKey, "label": $0.label, "pointWidth": $0.pointWidth, "pointHeight": $0.pointHeight, "refreshHz": $0.refreshHz, "isHiDPI": $0.isHiDPI, "isCurrent": $0.isCurrent] }
                ]
            }
            return okJSON(capability, action, ["displays": displays])

        case .systemControl:
            return handleSystemControl(action: action, params: params)

        case .lumaLinkStatus:
            return handleLumaLinkBridge(action: action, params: params)
        }
    }

    private static func handleSystemControl(action: String, params: [String: Any]) -> [String: Any] {
        let sys = LumaLinkSystemControlService.shared
        switch action {
        case "status":
            let audio = sys.readAudioState()
            return okJSON(.systemControl, action, [
                "volumePercent": audio.volumePercent, "isMuted": audio.isMuted,
                "caffeineActive": sys.isCaffeineActive, "curtainActive": sys.isCurtainActive
            ])
        case "setVolume":
            guard let pct = params["percent"] as? Int else { return errorJSON("invalid_params", "缺少 percent 参数", capability: .systemControl) }
            sys.setVolume(percent: pct)
            let audio = sys.readAudioState()
            return okJSON(.systemControl, action, ["volumePercent": audio.volumePercent, "isMuted": audio.isMuted])
        case "setMute":
            let cmd = (params["muted"] as? Bool).map { $0 ? "true" : "false" } ?? (params["muted"] as? String ?? "toggle")
            sys.setMute(command: cmd)
            let audio = sys.readAudioState()
            return okJSON(.systemControl, action, ["volumePercent": audio.volumePercent, "isMuted": audio.isMuted])
        case "setCaffeine":
            let active = params["active"] as? Bool ?? !sys.isCaffeineActive
            sys.setCaffeine(active)
            return okJSON(.systemControl, action, ["caffeineActive": sys.isCaffeineActive])
        default:
            return errorJSON("invalid_action", "systemControl 支持 status / setVolume / setMute / setCaffeine", capability: .systemControl)
        }
    }

    static func okJSON(_ cap: PluginCapability, _ action: String, _ data: [String: Any]) -> [String: Any] {
        ["ok": true, "capability": cap.rawValue, "action": action, "data": data]
    }

    static func errorJSON(_ code: String, _ message: String, capability: PluginCapability? = nil) -> [String: Any] {
        var out: [String: Any] = ["ok": false, "error": code, "message": message]
        if let capability { out["capability"] = capability.rawValue }
        return out
    }
}
