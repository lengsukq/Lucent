import Darwin
import Foundation
import PluginKit

/// `--session` 窗口绑定会话运行时：通过标准输入/输出 NDJSON 与浮窗实时双向通信，收到 `SIGTERM` 或 `stdin` EOF 立即停服并退出。
final class LocalSendSessionRuntime: @unchecked Sendable {
    private final class SessionEmitter: @unchecked Sendable {
        private let lock = NSLock()
        func emit(_ object: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(object),
                  var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
            data.append(0x0A)
            lock.withLock { FileHandle.standardOutput.write(data) }
        }
    }

    private let emitter: SessionEmitter
    private let input: PluginInput
    private let config: LocalSendSessionConfig
    private let identity: LocalSendTLSIdentity
    private let server: LocalSendHTTPServer
    private let discovery: LocalSendDiscovery
    private let client: LocalSendClient
    private let history: LocalSendHistoryStore
    private var favorites: [LocalSendFavoritePeer]
    private var sigtermSource: DispatchSourceSignal?

    init(bootstrapInput: PluginInput) {
        self.input = bootstrapInput
        let cfg = LocalSendSessionConfig.from(
            config: bootstrapInput.config,
            dataDir: bootstrapInput.dataDir,
            isEnglish: bootstrapInput.isEnglish
        )
        self.config = cfg
        self.identity = LocalSendTLSIdentity(dataDirectory: cfg.dataDirectory)
        self.favorites = LocalSendFavoriteStore.load(in: cfg.dataDirectory)
        self.history = LocalSendHistoryStore(dataDirectory: cfg.dataDirectory)
        self.server = LocalSendHTTPServer(config: cfg, identity: identity)

        let lumaNames = Self.loadLumaLinkPairedDeviceNames(input: bootstrapInput)
        let srv = self.server
        let emitter = SessionEmitter()
        let historyStore = self.history
        self.emitter = emitter
        self.discovery = LocalSendDiscovery(
            port: cfg.port,
            favorites: self.favorites,
            lumaLinkPairedNames: lumaNames,
            selfDeviceInfoProvider: { srv.currentDeviceInfo() },
            onPeersChanged: { peers in
                emitter.emit(["type": "peers", "peers": peers.map { $0.toJSONObject() }])
            }
        )
        self.client = LocalSendClient(
            selfDeviceInfoProvider: { srv.currentDeviceInfo() },
            onEvent: { ev in
                var enriched = ev
                if (ev["type"] as? String) == "transferCompleted" {
                    let now = Date().timeIntervalSince1970
                    enriched["timestampEpoch"] = now
                    historyStore.record(completedEvent: enriched)
                }
                emitter.emit(enriched)
            }
        )

        wireServerCallbacks()
    }

    func runUntilExit() {
        installSignalTrap()
        server.start()
        discovery.start()
        emitReadySnapshot()

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let cmdObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cmd = cmdObj["cmd"] as? String else { continue }
            handleCommand(cmd, body: cmdObj)
        }
        shutdown()
    }

    func shutdown() {
        client.cancelAll()
        discovery.stop()
        server.stop()
        identity.cleanup()
    }

    private func wireServerCallbacks() {
        server.onPeerRegistered = { [weak self] info, ip in
            self?.discovery.upsertPeer(from: info, remoteIP: ip)
        }
        server.onStatusChanged = { [weak self] status in
            var obj: [String: Any] = [
                "type": "serverStatus",
                "listening": status.listening,
                "port": Int(status.port),
                "protocol": status.protocolName,
                "receiveMode": status.mode.rawValue
            ]
            if let warn = status.warning { obj["warning"] = warn }
            self?.emit(obj)
        }
        server.onIncomingPrompt = { [weak self] ev in self?.emit(ev) }
        server.onTransferProgress = { [weak self] ev in self?.emit(ev) }
        server.onTransferCompleted = { [weak self] ev in
            guard let self else { return }
            var enriched = ev
            enriched["timestampEpoch"] = Date().timeIntervalSince1970
            self.history.record(completedEvent: enriched)
            self.emit(enriched)
        }
    }

    private func emitReadySnapshot() {
        let info = server.currentDeviceInfo()
        let activeIP = LocalSendNetworkInterfaces.primaryIPv4()
        let ifaces = LocalSendNetworkInterfaces.listActive().map {
            ["name": $0.name, "ip": $0.ipv4, "isTunnel": $0.isTunnel]
        }
        emit([
            "type": "ready",
            "self": [
                "alias": info.alias,
                "ip": activeIP,
                "port": info.port,
                "protocol": info.protocolName,
                "fingerprint": info.fingerprint,
                "shortFingerprint": String(info.fingerprint.prefix(8)),
                "receiveMode": config.receiveMode.rawValue,
                "saveDirectory": config.saveDirectory.path,
                "hasPin": !config.receivePin.isEmpty,
                "autoRouteFilesToShelf": config.autoRouteFilesToShelf,
                "autoCopyReceivedText": config.autoCopyReceivedText,
                "interfaces": ifaces
            ],
            "favorites": favorites.map {
                ["id": $0.id, "alias": $0.alias, "ip": $0.ip, "port": $0.port, "protocol": $0.protocolName]
            },
            "peers": discovery.snapshotPeers().map { $0.toJSONObject() },
            "history": history.snapshot()
        ])
    }

    private func handleCommand(_ cmd: String, body: [String: Any]) {
        switch cmd {
        case "refresh":
            discovery.announceAndProbe()
        case "deepScan":
            emit(["type": "scanState", "scanning": true])
            discovery.deepScanActiveSubnet { [weak self] count in
                self?.emit(["type": "scanState", "scanning": false, "found": count])
            }
        case "probeIP":
            guard let ip = (body["ip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty else { return }
            let port = (body["port"] as? NSNumber)?.intValue ?? Int(LocalSendConstants.defaultPort)
            let proto = body["protocol"] as? String
            let saveFav = (body["saveFavorite"] as? Bool) ?? true
            discovery.probeManualHost(ip: ip, port: port, protocolName: proto) { [weak self] peer in
                guard let self else { return }
                if let peer {
                    if saveFav { self.addOrUpdateFavorite(peer: peer) }
                    self.emit(["type": "probeResult", "ok": true, "peer": peer.toJSONObject()])
                } else {
                    self.emit(["type": "probeResult", "ok": false, "ip": ip, "port": port])
                }
            }
        case "toggleFavorite":
            guard let fp = body["fingerprint"] as? String, let peer = discovery.peer(forFingerprint: fp) else { return }
            toggleFavorite(peer: peer)
        case "sendFiles":
            guard let fp = body["targetFingerprint"] as? String,
                  let peer = discovery.peer(forFingerprint: fp),
                  let paths = body["filePaths"] as? [String], !paths.isEmpty else {
                emit(["type": "transferFailed", "direction": "send", "transferId": (body["transferId"] as? String) ?? "", "error": "目标设备已离线或文件列表为空"])
                return
            }
            let tid = (body["transferId"] as? String) ?? UUID().uuidString
            client.sendFiles(transferId: tid, paths: paths, to: peer, pin: body["pin"] as? String)
        case "sendText":
            guard let fp = body["targetFingerprint"] as? String,
                  let peer = discovery.peer(forFingerprint: fp),
                  let text = body["text"] as? String else {
                emit(["type": "transferFailed", "direction": "send", "transferId": (body["transferId"] as? String) ?? "", "error": "目标设备已离线或文本为空"])
                return
            }
            let tid = (body["transferId"] as? String) ?? UUID().uuidString
            client.sendText(transferId: tid, text: text, to: peer, pin: body["pin"] as? String)
        case "respondIncoming":
            guard let sid = body["sessionId"] as? String else { return }
            let accepted = (body["accepted"] as? Bool) ?? false
            server.respondToIncoming(sessionId: sid, accepted: accepted)
        case "cancelTransfer":
            if let tid = body["transferId"] as? String, !tid.isEmpty { client.cancel(transferId: tid) }
            if let sid = body["sessionId"] as? String, !sid.isEmpty { server.cancelReceiveSession(sessionId: sid) }
        case "setReceiveMode":
            if let raw = body["mode"] as? String, let mode = LocalSendReceiveMode(rawValue: raw) {
                server.updateReceiveMode(mode)
            }
        case "deleteHistoryItem":
            if let id = body["id"] as? String, !id.isEmpty {
                history.remove(id: id)
                emit(["type": "history", "items": history.snapshot()])
            }
        case "clearHistory":
            history.clear()
            emit(["type": "history", "items": []])
        default: break
        }
    }

    private func addOrUpdateFavorite(peer: LocalSendPeer) {
        let fav = LocalSendFavoritePeer(id: "\(peer.ip):\(peer.port)", alias: peer.alias, ip: peer.ip, port: peer.port, protocolName: peer.protocolName, fingerprint: peer.fingerprint)
        favorites.removeAll { $0.id == fav.id }
        favorites.append(fav)
        LocalSendFavoriteStore.save(favorites, in: config.dataDirectory)
        discovery.updateFavorites(favorites)
    }

    private func toggleFavorite(peer: LocalSendPeer) {
        let id = "\(peer.ip):\(peer.port)"
        if favorites.contains(where: { $0.id == id }) {
            favorites.removeAll { $0.id == id }
        } else {
            favorites.append(LocalSendFavoritePeer(id: id, alias: peer.alias, ip: peer.ip, port: peer.port, protocolName: peer.protocolName, fingerprint: peer.fingerprint))
        }
        LocalSendFavoriteStore.save(favorites, in: config.dataDirectory)
        discovery.updateFavorites(favorites)
    }

    private func emit(_ object: [String: Any]) {
        emitter.emit(object)
    }

    private func installSignalTrap() {
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .userInitiated))
        src.setEventHandler { [weak self] in
            self?.shutdown()
            Darwin.exit(0)
        }
        src.resume()
        sigtermSource = src
    }

    private static func loadLumaLinkPairedDeviceNames(input: PluginInput) -> Set<String> {
        guard input.grantedCapabilities.contains("lumaLinkStatus") else { return [] }
        let resp = HostBridgeClient(input: input).call(capability: "lumaLinkStatus", action: "status", params: ["renderQR": false])
        guard resp.ok, let paired = resp.data["pairedDevices"] as? [[String: Any]] else { return [] }
        return Set(paired.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }
}
