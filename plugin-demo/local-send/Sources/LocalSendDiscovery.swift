import Darwin
import Foundation

final class LocalSendDiscovery: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.lucent.localsend.discovery", qos: .userInitiated)
    private let port: UInt16
    private let selfDeviceInfoProvider: @Sendable () -> LocalSendDeviceInfo
    private let onPeersChanged: @Sendable ([LocalSendPeer]) -> Void

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var peersByFingerprint: [String: LocalSendPeer] = [:]
    private var favorites: [LocalSendFavoritePeer] = []
    private var lumaLinkPairedNames: Set<String> = []
    private var stopped = false

    init(
        port: UInt16,
        favorites: [LocalSendFavoritePeer],
        lumaLinkPairedNames: Set<String>,
        selfDeviceInfoProvider: @escaping @Sendable () -> LocalSendDeviceInfo,
        onPeersChanged: @escaping @Sendable ([LocalSendPeer]) -> Void
    ) {
        self.port = port
        self.favorites = favorites
        self.lumaLinkPairedNames = lumaLinkPairedNames
        self.selfDeviceInfoProvider = selfDeviceInfoProvider
        self.onPeersChanged = onPeersChanged
    }

    deinit { stop() }

    func start() {
        queue.async { [weak self] in
            self?.startMulticastSocket()
            self?.sendMulticastAnnouncement(announce: true)
            self?.probeFavorites()
        }
    }

    func stop() {
        let (fd, src) = lock.withLock { () -> (Int32, DispatchSourceRead?) in
            guard !stopped else { return (-1, nil) }
            stopped = true
            let s = readSource
            let f = socketFD
            readSource = nil
            socketFD = -1
            return (f, s)
        }
        if let src { src.cancel() }
        else if fd >= 0 { Darwin.close(fd) }
    }

    func updateFavorites(_ next: [LocalSendFavoritePeer]) {
        lock.withLock {
            favorites = next
            let favIPs = Set(next.map { "\($0.ip):\($0.port)" })
            for (fp, var peer) in peersByFingerprint {
                peer.isFavorite = favIPs.contains("\(peer.ip):\(peer.port)")
                peersByFingerprint[fp] = peer
            }
        }
        emitSortedPeers()
        probeFavorites()
    }

    func announceAndProbe() {
        queue.async { [weak self] in
            self?.sendMulticastAnnouncement(announce: true)
            self?.probeFavorites()
        }
    }

    func upsertPeer(from info: LocalSendDeviceInfo, remoteIP: String) {
        let me = selfDeviceInfoProvider()
        guard !info.fingerprint.isEmpty, info.fingerprint != me.fingerprint,
              !remoteIP.isEmpty, remoteIP != "127.0.0.1" else { return }
        let pairedMatch = isLumaLinkMatch(alias: info.alias)
        lock.withLock {
            let isFav = favorites.contains { $0.ip == remoteIP && $0.port == info.port }
            let peer = LocalSendPeer(
                fingerprint: info.fingerprint,
                alias: info.alias,
                ip: remoteIP,
                port: info.port > 0 ? info.port : Int(LocalSendConstants.defaultPort),
                protocolName: info.protocolName.lowercased() == "http" ? "http" : "https",
                deviceModel: info.deviceModel ?? "",
                deviceType: info.deviceType ?? "desktop",
                isFavorite: isFav,
                isLumaLinkPaired: pairedMatch,
                lastSeenEpoch: Date().timeIntervalSince1970
            )
            peersByFingerprint[info.fingerprint] = peer
        }
        emitSortedPeers()
    }

    func peer(forFingerprint fp: String) -> LocalSendPeer? {
        lock.withLock { peersByFingerprint[fp] }
    }

    func snapshotPeers() -> [LocalSendPeer] {
        sortedPeers()
    }

    func probeManualHost(ip: String, port: Int, protocolName: String?, completion: @escaping @Sendable (LocalSendPeer?) -> Void) {
        let schemes: [String] = if let p = protocolName?.lowercased(), p == "http" || p == "https" { [p] } else { ["https", "http"] }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(nil); return }
            for scheme in schemes {
                if let info = self.registerOverHTTP(ip: ip, port: port, scheme: scheme, timeout: 1.5) {
                    self.upsertPeer(from: info, remoteIP: ip)
                    completion(self.peer(forFingerprint: info.fingerprint))
                    return
                }
            }
            completion(nil)
        }
    }

    func deepScanActiveSubnet(onFinished: @escaping @Sendable (Int) -> Void) {
        let lanIfaces = LocalSendNetworkInterfaces.listActive().filter { !$0.isTunnel }
        guard let primary = lanIfaces.first else { onFinished(0); return }
        let targets = LocalSendNetworkInterfaces.subnet24Targets(for: primary.ipv4)
        let targetPort = Int(port)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { onFinished(0); return }
            let sem = DispatchSemaphore(value: 24)
            let group = DispatchGroup()
            let countLock = NSLock()
            var found = 0
            for ip in targets {
                if self.lock.withLock({ self.stopped }) { break }
                sem.wait()
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    defer { sem.signal(); group.leave() }
                    if let info = self.registerOverHTTP(ip: ip, port: targetPort, scheme: "https", timeout: 0.75)
                        ?? self.registerOverHTTP(ip: ip, port: targetPort, scheme: "http", timeout: 0.65) {
                        self.upsertPeer(from: info, remoteIP: ip)
                        countLock.withLock { found += 1 }
                    }
                }
            }
            group.wait()
            onFinished(found)
        }
    }

    private func probeFavorites() {
        let favs = lock.withLock { favorites }
        for fav in favs {
            probeManualHost(ip: fav.ip, port: fav.port, protocolName: fav.protocolName) { _ in }
        }
    }

    private func startMulticastSocket() {
        guard !lock.withLock({ stopped }) else { return }
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = Darwin.fcntl(fd, F_SETFL, O_NONBLOCK)

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = port.bigEndian
        bindAddr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
        let bound = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { Darwin.close(fd); return }

        let lanIPs = LocalSendNetworkInterfaces.listActive().filter { !$0.isTunnel }.map(\.ipv4)
        let joinTargets = lanIPs.isEmpty ? ["0.0.0.0"] : lanIPs
        for localIP in joinTargets {
            var mreq = ip_mreq()
            _ = LocalSendConstants.multicastAddress.withCString { inet_pton(AF_INET, $0, &mreq.imr_multiaddr) }
            _ = localIP.withCString { inet_pton(AF_INET, $0, &mreq.imr_interface) }
            _ = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readPendingPackets(fd: fd) }
        source.setCancelHandler { Darwin.close(fd) }
        lock.withLock {
            socketFD = fd
            readSource = source
        }
        source.resume()
    }

    private func sendMulticastAnnouncement(announce: Bool) {
        var me = selfDeviceInfoProvider()
        me.announce = announce
        guard let payload = try? JSONEncoder().encode(me) else { return }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }

        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        _ = LocalSendConstants.multicastAddress.withCString { inet_pton(AF_INET, $0, &dest.sin_addr) }

        let lanIPs = LocalSendNetworkInterfaces.listActive().filter { !$0.isTunnel }.map(\.ipv4)
        let ifaceIPs = lanIPs.isEmpty ? ["0.0.0.0"] : lanIPs
        for ip in ifaceIPs {
            var ifAddr = in_addr()
            if ip != "0.0.0.0", ip.withCString({ inet_pton(AF_INET, $0, &ifAddr) }) == 1 {
                _ = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifAddr, socklen_t(MemoryLayout<in_addr>.size))
            }
            payload.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                withUnsafePointer(to: &dest) { dPtr in
                    dPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = Darwin.sendto(fd, base, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private func readPendingPackets(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            var sender = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.recvfrom(fd, &buf, buf.count, 0, $0, &senderLen)
                }
            }
            if count <= 0 { break }
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addrCopy = sender.sin_addr
            guard inet_ntop(AF_INET, &addrCopy, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let remoteIP = String(cString: ipBuf)
            let packet = Data(buf.prefix(count))
            guard let info = try? JSONDecoder().decode(LocalSendDeviceInfo.self, from: packet) else { continue }
            let me = selfDeviceInfoProvider()
            guard info.fingerprint != me.fingerprint else { continue }
            upsertPeer(from: info, remoteIP: remoteIP)
            if info.announce == true {
                let targetPort = info.port > 0 ? info.port : Int(LocalSendConstants.defaultPort)
                let scheme = info.protocolName.lowercased() == "http" ? "http" : "https"
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self else { return }
                    if self.registerOverHTTP(ip: remoteIP, port: targetPort, scheme: scheme, timeout: 1.5) == nil {
                        self.sendMulticastAnnouncement(announce: false)
                    }
                }
            }
        }
    }

    private func registerOverHTTP(ip: String, port: Int, scheme: String, timeout: TimeInterval) -> LocalSendDeviceInfo? {
        LocalSendClientHelpers.registerPeerOverHTTP(
            selfInfo: selfDeviceInfoProvider(), ip: ip, port: port, scheme: scheme, timeout: timeout
        )
    }

    private func isLumaLinkMatch(alias: String) -> Bool {
        let lower = alias.lowercased()
        guard !lower.isEmpty else { return false }
        return lumaLinkPairedNames.contains { !$0.isEmpty && (lower.contains($0) || $0.contains(lower)) }
    }

    private func sortedPeers() -> [LocalSendPeer] {
        lock.withLock { Array(peersByFingerprint.values) }.sorted { lhs, rhs in
            if lhs.isLumaLinkPaired != rhs.isLumaLinkPaired { return lhs.isLumaLinkPaired }
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.alias.localizedCaseInsensitiveCompare(rhs.alias) == .orderedAscending
        }
    }

    private func emitSortedPeers() {
        onPeersChanged(sortedPeers())
    }
}
