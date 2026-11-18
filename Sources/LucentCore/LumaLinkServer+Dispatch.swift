import AppKit
import Foundation
import Network
import Security

extension LumaLinkServer {
    func handleFrame(_ data: Data, from session: LumaLinkClientSession) {
        if data.first != 0x7B { // Binary audio frame (non-JSON '{')
            guard session.authenticatedDeviceName != nil else { return }
            let pref = currentConfig().preferredVirtualMicName
            _ = LumaLinkAudioBridgeService.shared.handleIncomingPacket(data, preferredName: pref)
            return
        }
        guard let req = try? JSONDecoder().decode(LumaLinkRequest.self, from: data) else {
            send(LumaLinkResponse(id: "", ok: false, error: "请求格式错误"), to: session)
            return
        }
        if req.action == "auth.hello" {
            let hostName = Host.current().localizedName ?? "Mac"
            let rdp = LumaLinkRdpSidecarService.shared.currentStatus()
            send(LumaLinkResponse(
                id: req.id,
                ok: true,
                hostName: hostName,
                protocolVersion: 2,
                requiresPairing: true,
                rdpEnabled: rdp.enabled && rdp.running,
                rdpPort: Int(rdp.port)
            ), to: session)
            return
        }
        if req.action == "auth.pair" {
            handlePair(req, session: session)
            return
        }
        guard authenticate(req, session: session) else {
            send(LumaLinkResponse(id: req.id, ok: false, error: "未授权或 Token 已失效，请重新输入配对码"), to: session)
            return
        }
        dispatchAction(req, session: session)
    }

    public static let maxFailedPairAttempts = 5
    public static let pairLockoutDurationSeconds: CFAbsoluteTime = 60.0

    public func verifyAndConsumePairPin(_ candidatePin: String, now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> String? {
        let trimmed = candidatePin.trimmingCharacters(in: .whitespacesAndNewlines)
        return lock.withLock {
            if now < pairLockoutUntil {
                let remain = max(1, Int(ceil(pairLockoutUntil - now)))
                return "配对尝试过于频繁，已临时锁定（请 \(remain) 秒后使用新配对码重试）"
            }
            guard !trimmed.isEmpty, trimmed == _pin else {
                failedPairAttempts += 1
                if failedPairAttempts >= Self.maxFailedPairAttempts {
                    failedPairAttempts = 0
                    pairLockoutUntil = now + Self.pairLockoutDurationSeconds
                    _pin = Self.generatePin()
                    notifyStatusChanged()
                    return "连续配对失败已达 \(Self.maxFailedPairAttempts) 次，配对码已自动轮换并锁定 60 秒"
                }
                return "配对码错误（剩余 \(Self.maxFailedPairAttempts - failedPairAttempts) 次尝试机会）"
            }
            failedPairAttempts = 0
            pairLockoutUntil = 0
            _pin = Self.generatePin()
            return nil
        }
    }

    private static func generateSecureDeviceToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func handlePair(_ req: LumaLinkRequest, session: LumaLinkClientSession) {
        if let reason = verifyAndConsumePairPin(req.pin ?? "") {
            send(LumaLinkResponse(id: req.id, ok: false, error: reason), to: session)
            return
        }
        let devName = (req.deviceName ?? "").isEmpty ? "Android 手机" : req.deviceName!
        let newDevice = LumaLinkPairedDevice(name: devName, token: Self.generateSecureDeviceToken())
        var cfg = currentConfig()
        cfg.pairedDevices.append(newDevice)
        cfg.save()
        lock.withLock {
            _config = cfg
            session.authenticatedDeviceName = devName
        }
        startClipboardWatcherIfNeededOnQueue()
        notifyStatusChanged()
        send(LumaLinkResponse(
            id: req.id,
            ok: true,
            hostName: Host.current().localizedName ?? "Mac",
            protocolVersion: 1,
            token: newDevice.token,
            deviceId: newDevice.id
        ), to: session)
    }

    private func authenticate(_ req: LumaLinkRequest, session: LumaLinkClientSession) -> Bool {
        if session.authenticatedDeviceName != nil { return true }
        guard let token = req.token, !token.isEmpty else { return false }
        let matched = currentConfig().pairedDevices.first { $0.token == token }
        guard let matched else { return false }
        session.authenticatedDeviceName = matched.name
        startClipboardWatcherIfNeededOnQueue()
        notifyStatusChanged()
        return true
    }

    private func dispatchAction(_ req: LumaLinkRequest, session: LumaLinkClientSession) {
        let ctrl = LumaLinkSystemControlService.shared
        switch req.action {
        case "display.list":
            send(LumaLinkResponse(id: req.id, ok: true, displays: LumaLinkDisplayService.shared.listDisplays()), to: session)
        case "display.set":
            do {
                let updated = try LumaLinkDisplayService.shared.setDisplayMode(displayID: req.displayID, modeKey: req.modeKey ?? "")
                send(LumaLinkResponse(id: req.id, ok: true, displays: updated), to: session)
            } catch {
                send(LumaLinkResponse(id: req.id, ok: false, error: error.localizedDescription), to: session)
            }
        case "display.restore":
            _ = LumaLinkDisplayService.shared.restoreAll()
            send(LumaLinkResponse(id: req.id, ok: true, displays: LumaLinkDisplayService.shared.listDisplays()), to: session)
        case "telemetry.get":
            let snap = sampler.sample()
            let audio = ctrl.readAudioState()
            let tel = LumaLinkTelemetry(
                cpuPercent: snap.cpuTotalPercent,
                memoryUsedGB: Double(snap.memoryUsedBytes) / 1_073_741_824.0,
                memoryTotalGB: Double(snap.memoryTotalBytes) / 1_073_741_824.0,
                memoryPercent: snap.memoryPercent,
                systemWatts: snap.systemWatts,
                batteryPercent: snap.batteryPercent ?? -1,
                isCharging: snap.isCharging,
                netDownBytesPerSec: snap.netDownBytesPerSec,
                netUpBytesPerSec: snap.netUpBytesPerSec,
                thermalState: snap.thermalStateLabel,
                volumePercent: audio.volumePercent,
                isMuted: audio.isMuted,
                privacyCurtainActive: ctrl.isCurtainActive,
                caffeineActive: ctrl.isCaffeineActive
            )
            send(LumaLinkResponse(id: req.id, ok: true, telemetry: tel), to: session)
        case "control.volume":
            if let pct = req.percent { ctrl.setVolume(percent: pct) }
            if let cmd = req.command { ctrl.setMute(command: cmd) }
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "control.media":
            ctrl.triggerMedia(command: req.command ?? "")
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "control.power":
            ctrl.triggerPower(command: req.command ?? "", muteOnCurtain: currentConfig().muteMacWhenCurtainEnabled)
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "control.shortcut":
            ctrl.triggerShortcut(command: req.command ?? "")
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "clipboard.get":
            DispatchQueue.main.async {
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                self.send(LumaLinkResponse(id: req.id, ok: true, clipboardText: text), to: session)
            }
        case "clipboard.set":
            let txt = req.text ?? ""
            lock.withLock { suppressClipboardPushUntil = CFAbsoluteTimeGetCurrent() + 1.5 }
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(txt, forType: .string)
            }
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "clipboard.pasteText":
            let txt = req.text ?? ""
            lock.withLock { suppressClipboardPushUntil = CFAbsoluteTimeGetCurrent() + 1.5 }
            ctrl.pasteTextToFocusedApp(txt)
            send(LumaLinkResponse(id: req.id, ok: true), to: session)
        case "rdp.status":
            let rdp = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: true)
            send(LumaLinkResponse(
                id: req.id,
                ok: true,
                hostName: Host.current().localizedName ?? "Mac",
                protocolVersion: 2,
                rdpEnabled: rdp.enabled && rdp.running,
                rdpPort: Int(rdp.port)
            ), to: session)
        case "rdp.enable", "rdp.start":
            var cfg = currentConfig()
            cfg.enabled = true
            cfg.rdpEnabled = true
            apply(config: cfg, persist: true)
            Thread.sleep(forTimeInterval: 0.15)
            let rdp = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: true)
            send(LumaLinkResponse(
                id: req.id,
                ok: rdp.running,
                error: rdp.running ? nil : (rdp.lastError ?? "极速 RDP 服务尚未就绪，请在 Mac 端检查权限或引擎组件"),
                hostName: Host.current().localizedName ?? "Mac",
                protocolVersion: 2,
                rdpEnabled: rdp.enabled && rdp.running,
                rdpPort: Int(rdp.port)
            ), to: session)
        case "rdp.disable", "rdp.stop":
            var cfg = currentConfig()
            cfg.rdpEnabled = false
            apply(config: cfg, persist: true)
            let rdp = LumaLinkRdpSidecarService.shared.currentStatus(refreshPermissions: false)
            send(LumaLinkResponse(
                id: req.id,
                ok: true,
                hostName: Host.current().localizedName ?? "Mac",
                protocolVersion: 2,
                rdpEnabled: false,
                rdpPort: Int(rdp.port)
            ), to: session)
        case "audio.status":
            let pref = currentConfig().preferredVirtualMicName
            send(LumaLinkResponse(id: req.id, ok: true, audio: LumaLinkAudioBridgeService.shared.status(preferredName: pref)), to: session)
        case "audio.mic.start":
            let pref = currentConfig().preferredVirtualMicName
            let st = LumaLinkAudioBridgeService.shared.startVirtualMic(preferredName: pref)
            let ok = st.virtualMicDeviceName != nil
            send(LumaLinkResponse(id: req.id, ok: ok, error: ok ? nil : st.note, audio: st), to: session)
        case "audio.mic.stop":
            LumaLinkAudioBridgeService.shared.stopVirtualMic()
            let pref = currentConfig().preferredVirtualMicName
            send(LumaLinkResponse(id: req.id, ok: true, audio: LumaLinkAudioBridgeService.shared.status(preferredName: pref)), to: session)
        case "audio.speaker.start":
            let sid = session.id
            let err = LumaLinkSpeakerTapService.shared.subscribe(sessionID: sid) { [weak self, weak session] packet in
                guard let self, let session else { return }
                self.sendBinary(packet, to: session)
            }
            let pref = currentConfig().preferredVirtualMicName
            send(LumaLinkResponse(id: req.id, ok: err == nil, error: err, audio: LumaLinkAudioBridgeService.shared.status(preferredName: pref)), to: session)
        case "audio.speaker.stop":
            LumaLinkSpeakerTapService.shared.unsubscribe(sessionID: session.id)
            let pref = currentConfig().preferredVirtualMicName
            send(LumaLinkResponse(id: req.id, ok: true, audio: LumaLinkAudioBridgeService.shared.status(preferredName: pref)), to: session)
        default:
            send(LumaLinkResponse(id: req.id, ok: false, error: "不支持的操作: \(req.action)"), to: session)
        }
    }

    func send(_ response: LumaLinkResponse, to session: LumaLinkClientSession) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        session.connection.send(content: LumaLinkFraming.encodeFrame(data), completion: .contentProcessed { _ in })
    }

    func sendBinary(_ payload: Data, to session: LumaLinkClientSession) {
        session.connection.send(content: LumaLinkFraming.encodeFrame(payload), completion: .contentProcessed { _ in })
    }
}
