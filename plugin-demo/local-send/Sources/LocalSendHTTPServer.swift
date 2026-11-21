import Foundation
import Network

struct LocalSendServerStatus: Sendable {
    let listening: Bool
    let port: UInt16
    let protocolName: String
    let mode: LocalSendReceiveMode
    let warning: String?
}

final class LocalSendHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.lucent.localsend.server", qos: .userInitiated)
    private let identity: LocalSendTLSIdentity
    private let receiver: LocalSendReceiveManager
    private var config: LocalSendSessionConfig
    private var listener: NWListener?
    private var activeConnections: [UUID: LocalSendHTTPConnection] = [:]
    private var activeProtocol = "https"
    private var boundPort: UInt16 = 0
    private var failedPinAttempts = 0
    private var pinLockoutUntil: CFAbsoluteTime = 0

    var onPeerRegistered: (@Sendable (LocalSendDeviceInfo, String) -> Void)?
    var onStatusChanged: (@Sendable (LocalSendServerStatus) -> Void)?
    var onIncomingPrompt: (@Sendable ([String: Any]) -> Void)? {
        get { receiver.onIncomingPrompt }
        set { receiver.onIncomingPrompt = newValue }
    }
    var onTransferProgress: (@Sendable ([String: Any]) -> Void)? {
        get { receiver.onTransferProgress }
        set { receiver.onTransferProgress = newValue }
    }
    var onTransferCompleted: (@Sendable ([String: Any]) -> Void)? {
        get { receiver.onTransferCompleted }
        set { receiver.onTransferCompleted = newValue }
    }

    init(config: LocalSendSessionConfig, identity: LocalSendTLSIdentity) {
        self.config = config
        self.identity = identity
        self.receiver = LocalSendReceiveManager(saveDirectory: config.saveDirectory, queue: queue)
    }

    deinit { stop() }

    func currentDeviceInfo() -> LocalSendDeviceInfo {
        let (cfg, proto, portVal) = lock.withLock { (config, activeProtocol, boundPort > 0 ? boundPort : config.port) }
        return LocalSendDeviceInfo(
            alias: cfg.alias,
            version: LocalSendConstants.protocolVersion,
            deviceModel: "macOS",
            deviceType: "desktop",
            fingerprint: identity.fingerprint,
            port: Int(portVal),
            protocolName: proto,
            download: false,
            announce: nil
        )
    }

    func updateReceiveMode(_ mode: LocalSendReceiveMode) {
        let changed = lock.withLock { () -> Bool in
            guard config.receiveMode != mode else { return false }
            config.receiveMode = mode
            return true
        }
        guard changed else { return }
        if mode == .sendOnly {
            stop()
            onStatusChanged?(LocalSendServerStatus(
                listening: false, port: config.port,
                protocolName: config.useHttps ? "https" : "http", mode: .sendOnly, warning: nil
            ))
        } else if listener == nil {
            start()
        } else {
            let snap = lock.withLock { (boundPort, activeProtocol, config.receiveMode) }
            onStatusChanged?(LocalSendServerStatus(
                listening: snap.0 > 0, port: snap.0 > 0 ? snap.0 : config.port,
                protocolName: snap.1, mode: snap.2, warning: nil
            ))
        }
    }

    func start(preferredPort: UInt16? = nil) {
        let cfg = lock.withLock { config }
        let targetPort = preferredPort ?? cfg.port
        if cfg.receiveMode == .sendOnly {
            onStatusChanged?(LocalSendServerStatus(
                listening: false, port: targetPort,
                protocolName: cfg.useHttps ? "https" : "http", mode: .sendOnly, warning: nil
            ))
            return
        }
        var warning: String?
        let params: NWParameters
        let proto: String
        if cfg.useHttps, let tlsParams = identity.makeTLSParameters() {
            params = tlsParams
            proto = "https"
        } else {
            params = .tcp
            proto = "http"
            if cfg.useHttps { warning = identity.tlsInitError ?? "HTTPS 初始化失败，已自动降级为 HTTP 模式" }
        }
        params.allowLocalEndpointReuse = true

        do {
            let nwPort: NWEndpoint.Port = targetPort == 0 ? .any : (NWEndpoint.Port(rawValue: targetPort) ?? .any)
            let nwListener = try NWListener(using: params, on: nwPort)
            lock.withLock {
                self.listener = nwListener
                self.activeProtocol = proto
            }
            nwListener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state, targetPort: targetPort, proto: proto, initialWarning: warning)
            }
            nwListener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            nwListener.start(queue: queue)
        } catch {
            onStatusChanged?(LocalSendServerStatus(
                listening: false, port: targetPort, protocolName: proto, mode: .sendOnly,
                warning: "无法启动监听（\(error.localizedDescription)），已切为仅发送模式"
            ))
        }
    }

    func stop() {
        let (activeListener, conns) = lock.withLock { () -> (NWListener?, [LocalSendHTTPConnection]) in
            let l = listener; listener = nil; boundPort = 0
            let c = Array(activeConnections.values); activeConnections.removeAll()
            return (l, c)
        }
        activeListener?.cancel()
        for c in conns { c.forceClose() }
        receiver.stopAll()
    }

    func respondToIncoming(sessionId: String, accepted: Bool) {
        receiver.respondToIncoming(sessionId: sessionId, accepted: accepted)
    }

    func cancelReceiveSession(sessionId: String) {
        receiver.cancelSession(sessionId: sessionId)
    }

    func verifyPin(_ supplied: String?) -> Int {
        lock.withLock {
            let expected = config.receivePin
            guard !expected.isEmpty else { return 200 }
            let now = CFAbsoluteTimeGetCurrent()
            if now < pinLockoutUntil { return 429 }
            if supplied == expected {
                failedPinAttempts = 0
                return 200
            }
            failedPinAttempts += 1
            if failedPinAttempts >= LocalSendConstants.pinMaxFailures {
                pinLockoutUntil = now + LocalSendConstants.pinLockoutSeconds
                failedPinAttempts = 0
                return 429
            }
            return 401
        }
    }

    private func handleListenerState(_ state: NWListener.State, targetPort: UInt16, proto: String, initialWarning: String?) {
        switch state {
        case .ready:
            let realPort = listener?.port?.rawValue ?? targetPort
            lock.withLock { boundPort = realPort }
            onStatusChanged?(LocalSendServerStatus(
                listening: true, port: realPort, protocolName: proto,
                mode: lock.withLock { config.receiveMode }, warning: initialWarning
            ))
        case .failed(let err):
            let msg: String
            if case .posix(let code) = err, code == .EADDRINUSE {
                msg = "端口 \(targetPort) 已被其他 LocalSend 实例占用，当前以仅发送模式运行（可在插件设置改端口或关闭原版 LocalSend）"
            } else {
                msg = "接收服务启动失败：\(err.localizedDescription)，已切为仅发送模式"
            }
            lock.withLock { listener?.cancel(); listener = nil; boundPort = 0 }
            onStatusChanged?(LocalSendServerStatus(
                listening: false, port: targetPort, protocolName: proto, mode: .sendOnly, warning: msg
            ))
        default: break
        }
    }

    private func accept(_ conn: NWConnection) {
        let remoteIP = Self.extractRemoteIP(from: conn.endpoint)
        let connID = UUID()
        let handler = LocalSendHTTPConnection(
            connection: conn, queue: queue, remoteIP: remoteIP,
            onControlRequest: { [weak self] head, body, reply in
                self?.handleControl(head: head, body: body, reply: reply)
            },
            onUploadStart: { [weak self] head in
                self?.receiver.beginUpload(head: head) ?? .reject(status: 500, message: "Server stopped")
            },
            onClosed: { [weak self] in
                self?.lock.withLock { _ = self?.activeConnections.removeValue(forKey: connID) }
            }
        )
        lock.withLock { activeConnections[connID] = handler }
        handler.start()
    }

    private func handleControl(head: HTTPRequestHead, body: Data, reply: @escaping (Int, Data?) -> Void) {
        switch (head.method, head.path) {
        case ("GET", "/api/localsend/v2/info"):
            reply(200, try? JSONEncoder().encode(currentDeviceInfo()))
        case ("POST", "/api/localsend/v2/register"):
            if let peerInfo = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: body) {
                onPeerRegistered?(peerInfo, head.remoteIP)
            }
            reply(200, try? JSONEncoder().encode(currentDeviceInfo()))
        case ("POST", "/api/localsend/v2/prepare-upload"):
            guard let req = try? JSONDecoder().decode(LocalSendPrepareUploadRequest.self, from: body),
                  !req.files.isEmpty else {
                reply(400, Data("{\"message\":\"Invalid prepare-upload payload\"}".utf8))
                return
            }
            onPeerRegistered?(req.info, head.remoteIP)
            let pinCode = verifyPin(head.queryItems["pin"])
            guard pinCode == 200 else {
                reply(pinCode, Data("{\"message\":\"Invalid or locked PIN\"}".utf8))
                return
            }
            receiver.handlePrepareUpload(
                request: req, remoteIP: head.remoteIP,
                receiveMode: lock.withLock { config.receiveMode }, reply: reply
            )
        case ("POST", "/api/localsend/v2/cancel"):
            if let sid = head.queryItems["sessionId"] { cancelReceiveSession(sessionId: sid) }
            reply(200, nil)
        default:
            reply(404, Data("{\"message\":\"Not found\"}".utf8))
        }
    }

    private static func extractRemoteIP(from endpoint: NWEndpoint) -> String {
        if case .hostPort(let host, _) = endpoint {
            let raw = "\(host)"
            if raw.hasPrefix("::ffff:") { return String(raw.dropFirst(7)) }
            return raw.split(separator: "%").first.map(String.init) ?? raw
        }
        return ""
    }
}
