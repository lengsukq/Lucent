import AppKit
import Darwin
import Foundation
import Network

public struct LumaLinkRuntimeSnapshot: Sendable {
    public var isListening: Bool
    public var port: UInt16
    public var pairingPin: String
    public var connectedDeviceCount: Int
    public var lastError: String?

    public init(isListening: Bool = false, port: UInt16 = 0, pairingPin: String = "", connectedDeviceCount: Int = 0, lastError: String? = nil) {
        self.isListening = isListening
        self.port = port
        self.pairingPin = pairingPin
        self.connectedDeviceCount = connectedDeviceCount
        self.lastError = lastError
    }
}

final class LumaLinkClientSession: @unchecked Sendable {
    let id = UUID().uuidString
    let connection: NWConnection
    var accumulator = LumaLinkFrameAccumulator()
    var authenticatedDeviceName: String?

    init(connection: NWConnection) {
        self.connection = connection
    }
}

public final class LumaLinkServer: @unchecked Sendable {
    public static let shared = LumaLinkServer()
    public static let bonjourServiceType = "_lumakey-remote._tcp"

    let lock = NSLock()
    let queue = DispatchQueue(label: "app.lumakey.lumalink.server", qos: .userInitiated)
    let sampler = SystemMonitorSampler()
    var _config = LumaLinkConfig.load()
    var _pin: String = LumaLinkServer.generatePin()
    private var _isListening = false
    private var _listeningPort: UInt16 = 0
    private var _lastError: String?
    private var listener: NWListener?
    var sessions: [String: LumaLinkClientSession] = [:]
    private var clipboardTimer: DispatchSourceTimer?
    private var lastObservedChangeCount: Int = -1
    var suppressClipboardPushUntil: CFAbsoluteTime = 0

    public var onStatusChanged: (@MainActor @Sendable () -> Void)?

    private init() {}

    public func currentSnapshot() -> LumaLinkRuntimeSnapshot {
        lock.withLock {
            let connected = sessions.values.filter { $0.authenticatedDeviceName != nil }.count
            return LumaLinkRuntimeSnapshot(
                isListening: _isListening,
                port: _listeningPort,
                pairingPin: _pin,
                connectedDeviceCount: connected,
                lastError: _lastError
            )
        }
    }

    public func currentConfig() -> LumaLinkConfig {
        lock.withLock { _config }
    }

    public func regeneratePin() -> String {
        let next = Self.generatePin()
        lock.withLock { _pin = next }
        notifyStatusChanged()
        return next
    }

    public func apply(config next: LumaLinkConfig, persist: Bool = true) {
        if persist { next.save() }
        lock.withLock { _config = next }
        if next.enabled {
            startIfNeeded(preferredPort: next.preferredPort)
            LumaLinkRdpSidecarService.shared.sync(
                enabled: next.rdpEnabled,
                port: next.rdpPort,
                localAudioEnabled: next.rdpLocalAudioEnabled
            )
        } else {
            stopAll()
        }
    }

    public func revokePairedDevice(id: String) {
        var next = currentConfig()
        next.pairedDevices.removeAll { $0.id == id }
        apply(config: next, persist: true)
    }

    public func stopAll() {
        LumaLinkRdpSidecarService.shared.stop()
        LumaLinkAudioBridgeService.shared.stopVirtualMic()
        LumaLinkSpeakerTapService.shared.stopAll()
        queue.async {
            self.stopClipboardWatcherOnQueue()
            self.listener?.cancel()
            self.listener = nil
            let active = self.lock.withLock { () -> [LumaLinkClientSession] in
                let list = Array(self.sessions.values)
                self.sessions.removeAll()
                self._isListening = false
                self._listeningPort = 0
                return list
            }
            for s in active { s.connection.cancel() }
            if self.currentConfig().autoRestoreDisplayOnDisconnect {
                _ = LumaLinkDisplayService.shared.restoreAll()
            }
            LumaLinkSystemControlService.shared.releaseAllGuards()
            self.notifyStatusChanged()
        }
    }

    private func startIfNeeded(preferredPort: UInt16) {
        queue.async {
            if self.listener != nil { return }
            self.startListener(port: preferredPort, allowPortFallback: true)
        }
    }

    private func startListener(port: UInt16, allowPortFallback: Bool) {
        do {
            let nwPort: NWEndpoint.Port = (port > 0 && allowPortFallback)
                ? (NWEndpoint.Port(rawValue: port) ?? .any)
                : .any
            let nwListener = try NWListener(using: .tcp, on: nwPort)
            let hostName = Host.current().localizedName ?? "Mac"
            nwListener.service = NWListener.Service(
                name: hostName,
                type: Self.bonjourServiceType,
                txtRecord: NWTXTRecord(["proto": "1", "host": hostName])
            )
            nwListener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state, triedFixedPort: port > 0 && allowPortFallback)
            }
            nwListener.newConnectionHandler = { [weak self] conn in
                self?.acceptConnection(conn)
            }
            listener = nwListener
            nwListener.start(queue: queue)
        } catch {
            lock.withLock { _lastError = error.localizedDescription; _isListening = false }
            notifyStatusChanged()
        }
    }

    private func handleListenerState(_ state: NWListener.State, triedFixedPort: Bool) {
        switch state {
        case .ready:
            let portVal = listener?.port?.rawValue ?? 0
            lock.withLock { _isListening = true; _listeningPort = portVal; _lastError = nil }
            notifyStatusChanged()
        case .failed(let err):
            listener?.cancel()
            listener = nil
            if triedFixedPort {
                startListener(port: 0, allowPortFallback: false)
                return
            }
            lock.withLock { _isListening = false; _listeningPort = 0; _lastError = err.localizedDescription }
            notifyStatusChanged()
        case .cancelled:
            lock.withLock { _isListening = false; _listeningPort = 0 }
            notifyStatusChanged()
        default: break
        }
    }

    private func acceptConnection(_ conn: NWConnection) {
        let session = LumaLinkClientSession(connection: conn)
        lock.withLock { sessions[session.id] = session }
        conn.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.dropSession(session.id) }
            else if case .cancelled = st { self?.dropSession(session.id) }
        }
        conn.start(queue: queue)
        receiveLoop(session)
    }

    private func dropSession(_ id: String) {
        LumaLinkSpeakerTapService.shared.unsubscribe(sessionID: id)
        let remainingAuth = lock.withLock { () -> Int in
            sessions.removeValue(forKey: id)?.connection.cancel()
            return sessions.values.filter { $0.authenticatedDeviceName != nil }.count
        }
        if remainingAuth == 0 {
            stopClipboardWatcherOnQueue()
            LumaLinkAudioBridgeService.shared.stopVirtualMic()
            LumaLinkSpeakerTapService.shared.stopAll()
            if currentConfig().autoRestoreDisplayOnDisconnect {
                _ = LumaLinkDisplayService.shared.restoreAll()
            }
            LumaLinkSystemControlService.shared.setCurtain(false, mute: false)
        }
        notifyStatusChanged()
    }

    private func receiveLoop(_ session: LumaLinkClientSession) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try session.accumulator.append(data) {
                        self.handleFrame(frame, from: session)
                    }
                } catch {
                    self.dropSession(session.id)
                    return
                }
            }
            if isComplete || err != nil {
                self.dropSession(session.id)
            } else {
                self.receiveLoop(session)
            }
        }
    }

    func startClipboardWatcherIfNeededOnQueue() {
        guard clipboardTimer == nil else { return }
        DispatchQueue.main.async { self.lastObservedChangeCount = NSPasteboard.general.changeCount }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .milliseconds(900), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.pollClipboardOnMain() }
        }
        timer.resume()
        clipboardTimer = timer
    }

    private func stopClipboardWatcherOnQueue() {
        clipboardTimer?.cancel()
        clipboardTimer = nil
    }

    @MainActor
    private func pollClipboardOnMain() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = pb.changeCount
        let suppressed = lock.withLock { CFAbsoluteTimeGetCurrent() < suppressClipboardPushUntil }
        guard !suppressed, let text = pb.string(forType: .string), !text.isEmpty, text.count <= 32_768 else { return }
        let clients = lock.withLock { Array(sessions.values.filter { $0.authenticatedDeviceName != nil }) }
        guard !clients.isEmpty else { return }
        let push = LumaLinkResponse(id: "", type: "event", ok: true, clipboardText: text)
        for s in clients { send(push, to: s) }
    }

    func notifyStatusChanged() {
        let cb = onStatusChanged
        Task { @MainActor in cb?() }
    }

    static func generatePin() -> String {
        String(format: "%06d", Int.random(in: 100_000...999_999))
    }

    public static func localIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = buf.withUnsafeBufferPointer { String(decoding: $0.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self) }
                if !ip.hasPrefix("169.254.") { return ip }
            }
        }
        return nil
    }
}
