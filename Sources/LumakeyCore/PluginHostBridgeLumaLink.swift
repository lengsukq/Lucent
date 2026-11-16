import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import ApplicationServices
import CoreGraphics
import Foundation

extension PluginHostBridgeHandlers {
    static func handleLumaLinkBridge(action: String, params: [String: Any]) -> [String: Any] {
        var cfg = LumaLinkServer.shared.currentConfig()
        let sys = LumaLinkSystemControlService.shared
        let dispSvc = LumaLinkDisplayService.shared

        switch action {
        case "status":
            break
        case "toggle":
            cfg.enabled.toggle()
            LumaLinkServer.shared.apply(config: cfg, persist: true)
        case "setEnabled":
            guard let enabled = params["enabled"] as? Bool else {
                return errorJSON("invalid_params", "缺少布尔参数 enabled", capability: .lumaLinkStatus)
            }
            cfg.enabled = enabled
            LumaLinkServer.shared.apply(config: cfg, persist: true)
        case "toggleRdp":
            cfg.rdpEnabled.toggle()
            LumaLinkServer.shared.apply(config: cfg, persist: true)
        case "regeneratePin":
            _ = LumaLinkServer.shared.regeneratePin()
        case "toggleCurtain":
            let next = (params["active"] as? Bool) ?? !sys.isCurtainActive
            sys.setCurtain(next, mute: cfg.muteMacWhenCurtainEnabled)
        case "toggleCaffeine":
            let next = (params["active"] as? Bool) ?? !sys.isCaffeineActive
            sys.setCaffeine(next)
        case "setDisplayMode":
            guard let modeKey = params["modeKey"] as? String, !modeKey.isEmpty else {
                return errorJSON("invalid_params", "缺少分辨率参数 modeKey", capability: .lumaLinkStatus)
            }
            let rawID = (params["displayID"] as? NSNumber)?.uint32Value
            do {
                _ = try dispSvc.setDisplayMode(displayID: rawID, modeKey: modeKey)
            } catch {
                return errorJSON("execution_failed", error.localizedDescription, capability: .lumaLinkStatus)
            }
        case "restoreDisplays":
            _ = dispSvc.restoreAll()
        case "revokeDevice":
            guard let devID = params["deviceId"] as? String, !devID.isEmpty else {
                return errorJSON("invalid_params", "缺少设备标识 deviceId", capability: .lumaLinkStatus)
            }
            LumaLinkServer.shared.revokePairedDevice(id: devID)
        default:
            return errorJSON(
                "invalid_action",
                "lumaLinkStatus 不支持动作 '\(action)'",
                capability: .lumaLinkStatus
            )
        }

        let latestCfg = LumaLinkServer.shared.currentConfig()
        let snap = LumaLinkServer.shared.currentSnapshot()
        let rdp = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: false)
        let ip = LumaLinkServer.localIPv4Address() ?? "127.0.0.1"
        let port = Int(snap.port > 0 ? snap.port : latestCfg.preferredPort)
        let pin = latestCfg.enabled ? snap.pairingPin : ""
        let pairURI = latestCfg.enabled && !pin.isEmpty ? "lumalink://pair?host=\(ip)&port=\(port)&pin=\(pin)" : ""

        var qrImagePath = ""
        if !pairURI.isEmpty, (params["renderQR"] as? Bool ?? true) {
            let qrDir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-lumalink-qr", isDirectory: true)
            if let qrURL = DevToolkitHelpers.renderQRCodePNG(text: pairURI, pixelSize: 380, directory: qrDir) {
                qrImagePath = qrURL.path
            }
        }

        let includeDisplays = params["includeDisplays"] as? Bool ?? false
        let displaysJSON: [[String: Any]] = includeDisplays ? dispSvc.listDisplays().map { d in
            [
                "displayID": d.displayID,
                "name": d.name,
                "isMain": d.isMain,
                "currentModeKey": d.currentModeKey,
                "modes": d.modes.map { m in
                    [
                        "modeKey": m.modeKey, "label": m.label,
                        "pointWidth": m.pointWidth, "pointHeight": m.pointHeight,
                        "refreshHz": m.refreshHz, "isHiDPI": m.isHiDPI, "isCurrent": m.isCurrent
                    ]
                }
            ]
        } : []

        let pairedDevicesJSON: [[String: Any]] = latestCfg.pairedDevices.map { dev in
            [
                "id": dev.id,
                "name": dev.name,
                "pairedAt": dev.pairedAt
            ]
        }

        return okJSON(.lumaLinkStatus, action, [
            "enabled": latestCfg.enabled,
            "isListening": snap.isListening,
            "port": port,
            "preferredPort": Int(latestCfg.preferredPort),
            "localIPv4": ip,
            "pairingPin": pin,
            "pairURI": pairURI,
            "qrImagePath": qrImagePath,
            "connectedDeviceCount": snap.connectedDeviceCount,
            "pairedDeviceCount": latestCfg.pairedDevices.count,
            "pairedDevices": pairedDevicesJSON,
            "rdpEnabled": latestCfg.rdpEnabled,
            "rdpRunning": rdp.running,
            "rdpPort": Int(latestCfg.rdpPort),
            "curtainActive": sys.isCurtainActive,
            "caffeineActive": sys.isCaffeineActive,
            "hasModifiedDisplays": dispSvc.hasSnapshottedChanges,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "screenRecordingTrusted": CGPreflightScreenCaptureAccess(),
            "displays": displaysJSON
        ])
    }
}
