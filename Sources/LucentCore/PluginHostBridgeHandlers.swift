import LucentSearch
import LucentMedia
import AppKit
import Foundation

public enum PluginHostBridgeHandlers {
    public static func dispatch(
        capability: PluginCapability,
        action: String,
        params: [String: Any],
        hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        switch capability {
        case .clipboard:
            switch action {
            case "read":
                return okJSON(capability, action, ["text": hostContext.clipboardReader()])
            case "write":
                guard let text = params["text"] as? String else { return errorJSON("invalid_params", "缺少 text 参数", capability: capability) }
                return okJSON(capability, action, ["written": hostContext.clipboardWriter(text), "length": text.count])
            case "writeImage":
                guard let path = params["imagePath"] as? String, !path.isEmpty else {
                    return errorJSON("invalid_params", "缺少 imagePath 参数", capability: capability)
                }
                return PluginScreenAndWindowBridge.writeImageToPasteboard(imagePath: path)
            default:
                return errorJSON("invalid_action", "clipboard 支持 read / write / writeImage", capability: capability)
            }

        case .selection:
            switch action {
            case "read":
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
                    "bundleIdentifier": snapshot.bundleIdentifier,
                    "accessibilityGranted": PluginHostTCCBroker.status(for: .accessibility).isGranted
                ])
            case "pasteBack":
                return PluginScreenAndWindowBridge.handlePasteBack(params: params, hostContext: hostContext)
            default:
                return errorJSON("invalid_action", "selection 支持 read / pasteBack", capability: capability)
            }

        case .window, .floatingWindow:
            return PluginScreenAndWindowBridge.handleCustomWindow(
                capability: capability, action: action, params: params, hostContext: hostContext
            )

        case .screenCapture:
            return PluginScreenAndWindowBridge.handleScreenCapture(
                action: action, params: params, hostContext: hostContext
            )

        case .notifications:
            return PluginScreenAndWindowBridge.handleNotifications(
                action: action, params: params, hostContext: hostContext
            )

        case .audio:
            return handleAudio(action: action, params: params)

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

        case .fileShelf:
            guard action == "open" || action == "addContextItems", params.isEmpty else {
                return errorJSON("invalid_action", "Expected open or addContextItems without parameters", capability: capability)
            }
            guard let id = hostContext.pluginID, let perform = hostContext.fileShelfAction,
                  perform(id, action == "addContextItems") else {
                return errorJSON("shelf_unavailable", "No authorized file shelf or selected files", capability: capability)
            }
            return okJSON(capability, action, ["opened": true])

        case .audioDevices:
            guard hostContext.allowsAudioDevices else {
                return errorJSON("unsupported_context", "Audio devices require the Lucent desktop host", capability: capability)
            }
            return PluginAudioDeviceRouter.shared.dispatch(action, params: params, feedback: hostContext.audioFeedback)

        case .lumaLinkStatus:
            return handleLumaLinkBridge(action: action, params: params)

        case .contextRouter:
            return handleContextRouter(action: action, params: params, hostContext: hostContext)
        }
    }

    private static func handleContextRouter(
        action: String,
        params: [String: Any],
        hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        guard let payload = parseContextPayload(params: params, sourcePluginID: hostContext.pluginID) else {
            return errorJSON("invalid_params", "需要有效的 kind 与对应 text / url / filePaths 参数", capability: .contextRouter)
        }
        switch action {
        case "match":
            let candidates = hostContext.contextMatcher?(hostContext.pluginID, payload) ?? []
            return okJSON(.contextRouter, action, ["plugins": candidates.map { $0.toJSONObject() }])
        case "route":
            guard let rawTarget = params["targetPluginId"] as? String ?? params["pluginId"] as? String,
                  PluginSystem.isSafePluginID(rawTarget),
                  rawTarget != hostContext.pluginID else {
                return errorJSON("invalid_params", "缺少合法的目标插件 targetPluginId", capability: .contextRouter)
            }
            guard let router = hostContext.contextRouter else {
                return errorJSON("unsupported_context", "当前上下文不支持跨插件路由", capability: .contextRouter)
            }
            let routed = router(rawTarget, payload)
            guard routed else {
                return errorJSON("route_failed", "目标插件不可用或拒绝接收该上下文：\(rawTarget)", capability: .contextRouter)
            }
            return okJSON(.contextRouter, action, ["routed": true, "targetPluginId": rawTarget])
        default:
            return errorJSON("invalid_action", "contextRouter 支持 match / route", capability: .contextRouter)
        }
    }

    private static func parseContextPayload(params: [String: Any], sourcePluginID: String?) -> PluginContextPayload? {
        let source = (params["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSource = (source?.isEmpty == false ? source! : nil) ?? sourcePluginID ?? "plugin"
        if let rawPaths = params["filePaths"] as? [String], !rawPaths.isEmpty {
            let validURLs = rawPaths
                .map { URL(fileURLWithPath: $0).standardizedFileURL }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !validURLs.isEmpty else { return nil }
            if let rawKind = params["kind"] as? String, let explicitKind = PluginContextKind(rawValue: rawKind),
               [.file, .image, .directory].contains(explicitKind) {
                return PluginContextPayload(kind: explicitKind, filePaths: validURLs.map(\.path), source: resolvedSource)
            }
            return PluginContextMatcher.payloadFromFiles(validURLs, source: resolvedSource)
        }
        if let rawURL = (params["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty {
            return PluginContextPayload(kind: .url, text: rawURL, url: rawURL, source: resolvedSource)
        }
        if let rawText = (params["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty {
            if let rawKind = params["kind"] as? String, rawKind == PluginContextKind.text.rawValue {
                return PluginContextPayload(kind: .text, text: rawText, source: resolvedSource)
            }
            return PluginContextMatcher.payloadFromText(rawText, source: resolvedSource)
        }
        return nil
    }

    private static func handleAudio(action: String, params: [String: Any]) -> [String: Any] {
        switch action {
        case "play":
            guard let path = params["path"] as? String, !path.isEmpty else {
                return errorJSON("invalid_params", "缺少 path 参数", capability: .audio)
            }
            do { return okJSON(.audio, action, try PluginAudioBridgePlayer.shared.play(path: path)) }
            catch { return errorJSON("execution_failed", error.localizedDescription, capability: .audio) }
        case "speak":
            guard let text = params["text"] as? String, !text.isEmpty else {
                return errorJSON("invalid_params", "缺少 text 参数", capability: .audio)
            }
            return okJSON(.audio, action, PluginAudioBridgePlayer.shared.speak(text: text, language: params["language"] as? String))
        case "stop":
            return okJSON(.audio, action, PluginAudioBridgePlayer.shared.stop())
        default:
            return errorJSON("invalid_action", "audio 仅支持 play / speak / stop", capability: .audio)
        }
    }

    private static func handleSystemControl(action: String, params: [String: Any]) -> [String: Any] {
        let sys = LumaLinkSystemControlService.shared
        let shield = StatusScreenOverlayService.shared
        func mergedStatus() -> [String: Any] {
            let audio = sys.readAudioState()
            var base: [String: Any] = [
                "volumePercent": audio.volumePercent, "isMuted": audio.isMuted,
                "caffeineActive": sys.isCaffeineActive, "curtainActive": sys.isCurtainActive
            ]
            for (k, v) in shield.statusSnapshot() { base[k] = v }
            return base
        }
        switch action {
        case "status":
            return okJSON(.systemControl, action, mergedStatus())
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
            sys.setCaffeine(params["active"] as? Bool ?? !sys.isCaffeineActive)
            return okJSON(.systemControl, action, ["caffeineActive": sys.isCaffeineActive])
        case "setStatusScreen":
            if (params["active"] as? Bool ?? true) == false {
                shield.dismiss(); return okJSON(.systemControl, action, mergedStatus())
            }
            let cfg = StatusScreenConfiguration(
                preset: params["preset"] as? String ?? "clean", icon: params["icon"] as? String ?? "",
                title: params["title"] as? String ?? "", subtitle: params["subtitle"] as? String ?? "",
                blockInput: params["blockInput"] as? Bool ?? true, keepAwake: params["keepAwake"] as? Bool ?? true,
                muteAudio: params["muteAudio"] as? Bool ?? false,
                holdSeconds: (params["holdSeconds"] as? NSNumber)?.doubleValue ?? 2.0
            )
            shield.activate(cfg, delaySeconds: (params["delaySeconds"] as? NSNumber)?.doubleValue ?? 0.12)
            return okJSON(.systemControl, action, mergedStatus())
        case "clearStatusScreen":
            shield.dismiss()
            return okJSON(.systemControl, action, mergedStatus())
        default:
            return errorJSON("invalid_action", "systemControl 支持 status / setVolume / setMute / setCaffeine / setStatusScreen / clearStatusScreen", capability: .systemControl)
        }
    }

    public static func okJSON(_ cap: PluginCapability, _ action: String, _ data: [String: Any]) -> [String: Any] {
        ["ok": true, "capability": cap.rawValue, "action": action, "data": data]
    }

    public static func errorJSON(_ code: String, _ message: String, capability: PluginCapability? = nil) -> [String: Any] {
        var out: [String: Any] = ["ok": false, "error": code, "message": message]
        if let capability { out["capability"] = capability.rawValue }
        return out
    }
}
