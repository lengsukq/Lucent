import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Darwin
import Foundation
import Security

public final class PluginHostBridgeServer: @unchecked Sendable {
    public let socketPath: String
    public let token: String

    private let descriptor: PluginDescriptor
    private let grantedCapabilities: Set<PluginCapability>
    private let hostContext: PluginBridgeHostContext
    private let queue = DispatchQueue(label: "com.queensu.lumakey.plugin-bridge", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "com.queensu.lumakey.plugin-bridge.clients", qos: .userInitiated, attributes: .concurrent)
    private let clientSemaphore = DispatchSemaphore(value: 8)
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var activeClientFDs: Set<Int32> = []
    private var stopped = false

    public init(
        descriptor: PluginDescriptor,
        grantedCapabilities: Set<PluginCapability>,
        hostContext: PluginBridgeHostContext = .default
    ) throws {
        self.descriptor = descriptor
        self.grantedCapabilities = grantedCapabilities
        self.hostContext = hostContext.scoped(to: descriptor)

        var randomBytes = [UInt8](repeating: 0, count: 24)
        let rc = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if rc != errSecSuccess {
            randomBytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        }
        self.token = randomBytes.map { String(format: "%02x", $0) }.joined()
        let sockDir = PluginDataPaths.runtimeSocketDirectory()
        let pid = ProcessInfo.processInfo.processIdentifier
        self.socketPath = sockDir.appendingPathComponent("b-\(pid)-\(self.token.prefix(10)).sock").path
        try startListening()
    }

    deinit { stop() }

    public func stop() {
        let (fd, src, path, clients) = lock.withLock { () -> (Int32, DispatchSourceRead?, String, [Int32]) in
            guard !stopped else { return (-1, nil, socketPath, []) }
            stopped = true
            let s = acceptSource
            let f = listenFD
            let c = Array(activeClientFDs)
            acceptSource = nil
            listenFD = -1
            return (f, s, socketPath, c)
        }
        src?.cancel()
        if fd >= 0 { Darwin.close(fd) }
        for cfd in clients { _ = Darwin.shutdown(cfd, SHUT_RDWR) }
        Darwin.unlink(path)
    }

    private func startListening() throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LumakeyError.pluginExecutionFailed("无法创建 Host Bridge UDS 监听句柄")
        }
        _ = Darwin.fcntl(fd, F_SETFD, FD_CLOEXEC)
        Darwin.unlink(socketPath)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw LumakeyError.pluginExecutionFailed("Host Bridge Socket 路径超长")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes.map(UInt8.init(bitPattern:)))
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 8) == 0 else {
            let errText = String(cString: strerror(errno))
            Darwin.close(fd)
            Darwin.unlink(socketPath)
            throw LumakeyError.pluginExecutionFailed("Host Bridge UDS 绑定失败：\(errText)")
        }
        Darwin.chmod(socketPath, 0o600)
        _ = Darwin.fcntl(fd, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        lock.withLock {
            self.listenFD = fd
            self.acceptSource = source
        }
        source.resume()
    }

    private func acceptPending() {
        let fd = lock.withLock { stopped ? -1 : listenFD }
        guard fd >= 0 else { return }
        while true {
            var clientAddr = sockaddr_un()
            var len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(fd, $0, &len) }
            }
            if clientFD < 0 { break }
            _ = Darwin.fcntl(clientFD, F_SETFD, FD_CLOEXEC)
            clientSemaphore.wait()
            clientQueue.async { [weak self] in
                defer { self?.clientSemaphore.signal() }
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ clientFD: Int32) {
        lock.withLock { _ = activeClientFDs.insert(clientFD) }
        defer {
            lock.withLock { _ = activeClientFDs.remove(clientFD) }
            Darwin.close(clientFD)
        }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 4096)
        var raw = Data()
        while raw.count < 65_536 {
            let n = Darwin.read(clientFD, &buffer, buffer.count)
            if n <= 0 { break }
            raw.append(contentsOf: buffer.prefix(n))
            if raw.contains(0x0A) { break }
        }
        let trimmed = raw.drop(while: { $0 == 0x0A })
        let lineData = trimmed.firstIndex(of: 0x0A).map { Data(trimmed[..<$0]) } ?? Data(trimmed)
        let response = Self.evaluateRequestData(
            lineData,
            expectedToken: token,
            descriptor: descriptor,
            grantedCapabilities: grantedCapabilities,
            hostContext: hostContext
        )
        if var outData = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .withoutEscapingSlashes]) {
            outData.append(0x0A)
            outData.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                var sent = 0
                while sent < outData.count {
                    let w = Darwin.write(clientFD, base.advanced(by: sent), outData.count - sent)
                    if w <= 0 { break }
                    sent += w
                }
            }
        }
    }

    public static func evaluateRequestData(
        _ data: Data,
        expectedToken: String,
        descriptor: PluginDescriptor,
        grantedCapabilities: Set<PluginCapability>,
        hostContext: PluginBridgeHostContext
    ) -> [String: Any] {
        guard let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PluginHostBridgeHandlers.errorJSON("invalid_json", "请求必须是单行 JSON 对象")
        }
        guard let supplied = req["token"] as? String, supplied == expectedToken else {
            return PluginHostBridgeHandlers.errorJSON("invalid_token", "Host Bridge 一次性令牌校验失败")
        }
        let opRaw = (req["op"] as? String) ?? (req["capability"] as? String) ?? ""
        if opRaw == "progress" {
            let params = (req["params"] as? [String: Any]) ?? req
            let msg = (params["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !msg.isEmpty else {
                return PluginHostBridgeHandlers.errorJSON("invalid_params", "progress 上报缺少非空 message 参数")
            }
            let frac = (params["fraction"] as? NSNumber)?.doubleValue
            let progress = PluginExecutionProgress(pluginID: descriptor.id, message: msg, fraction: frac)
            hostContext.progressReporter?(progress)
            return ["ok": true, "action": "progress", "data": ["message": progress.message]]
        }
        guard let capRaw = req["capability"] as? String,
              let capability = PluginCapability(rawValue: capRaw)
        else {
            return PluginHostBridgeHandlers.errorJSON("invalid_capability", "未识别的 capability 名称")
        }
        let isDeclared = descriptor.declaredCapabilities.contains(capability)
            || (capability == .window && descriptor.declaredCapabilities.contains(.floatingWindow))
        guard isDeclared else {
            return PluginHostBridgeHandlers.errorJSON("capability_not_declared", "plugin.json 未声明 capability '\(capability.rawValue)'", capability: capability)
        }
        let isGranted = grantedCapabilities.contains(capability)
            || (capability == .window && grantedCapabilities.contains(.floatingWindow))
        guard isGranted else {
            return PluginHostBridgeHandlers.errorJSON("capability_not_granted", "用户尚未在 Lumakey 插件中心授权 '\(capability.rawValue)'", capability: capability)
        }
        let action = req["action"] as? String ?? ""
        let params = req["params"] as? [String: Any] ?? [:]
        return PluginHostBridgeHandlers.dispatch(
            capability: capability, action: action, params: params, hostContext: hostContext
        )
    }
}
