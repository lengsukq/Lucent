import Darwin
import Foundation

public struct BridgeResponse: @unchecked Sendable {
    public let ok: Bool
    public let error: String?
    public let message: String?
    public let data: [String: Any]
    public let raw: [String: Any]

    public init(ok: Bool, error: String? = nil, message: String? = nil, data: [String: Any] = [:], raw: [String: Any] = [:]) {
        self.ok = ok
        self.error = error
        self.message = message
        self.data = data
        self.raw = raw
    }

    public func string(_ key: String, default defaultValue: String = "") -> String {
        (data[key] as? String) ?? defaultValue
    }

    public func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if let b = data[key] as? Bool { return b }
        if let n = data[key] as? NSNumber { return n.boolValue }
        return defaultValue
    }

    public func int(_ key: String, default defaultValue: Int = 0) -> Int {
        if let i = data[key] as? Int { return i }
        if let n = data[key] as? NSNumber { return n.intValue }
        return defaultValue
    }

    public func double(_ key: String, default defaultValue: Double = 0) -> Double {
        if let d = data[key] as? Double { return d }
        if let n = data[key] as? NSNumber { return n.doubleValue }
        return defaultValue
    }
}

public struct HostBridgeClient: Sendable {
    public let socketPath: String
    public let token: String
    public let timeoutSeconds: Int

    public init(socketPath: String, token: String, timeoutSeconds: Int = 4) {
        self.socketPath = socketPath
        self.token = token
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    public init(input: PluginInput, timeoutSeconds: Int = 4) {
        self.init(socketPath: input.bridgeSocket, token: input.bridgeToken, timeoutSeconds: timeoutSeconds)
    }

    public var isAvailable: Bool {
        !socketPath.isEmpty && !token.isEmpty
    }

    @discardableResult
    public func call(capability: String, action: String, params: [String: Any] = [:]) -> BridgeResponse {
        sendPayload([
            "token": token,
            "capability": capability,
            "action": action,
            "params": params
        ])
    }

    @discardableResult
    public func reportProgress(message: String, fraction: Double? = nil) -> BridgeResponse {
        var params: [String: Any] = ["message": message]
        if let fraction { params["fraction"] = fraction }
        return sendPayload([
            "token": token,
            "op": "progress",
            "params": params
        ])
    }

    private func sendPayload(_ requestObj: [String: Any]) -> BridgeResponse {
        guard isAvailable else {
            return BridgeResponse(ok: false, error: "bridge_unavailable", message: "Host Bridge 未就绪")
        }
        guard var reqData = try? JSONSerialization.data(withJSONObject: requestObj, options: [.withoutEscapingSlashes]) else {
            return BridgeResponse(ok: false, error: "invalid_request", message: "无法编码桥接请求 JSON")
        }
        reqData.append(0x0A)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return BridgeResponse(ok: false, error: "socket_failed", message: "创建 Unix Socket 失败")
        }
        defer { Darwin.close(fd) }

        var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return BridgeResponse(ok: false, error: "socket_path_too_long", message: "Socket 路径超长")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes.map(UInt8.init(bitPattern:)))
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return BridgeResponse(ok: false, error: "connect_failed", message: String(cString: strerror(errno)))
        }

        let writeOK = reqData.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            var sent = 0
            while sent < reqData.count {
                let w = Darwin.write(fd, base.advanced(by: sent), reqData.count - sent)
                if w <= 0 { return false }
                sent += w
            }
            return true
        }
        guard writeOK else {
            return BridgeResponse(ok: false, error: "write_failed", message: "写入 Host Bridge 失败")
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while responseData.count < 262_144 {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            responseData.append(contentsOf: buffer.prefix(n))
            if responseData.contains(0x0A) { break }
        }

        let lineData = responseData.firstIndex(of: 0x0A).map { Data(responseData[..<$0]) } ?? responseData
        guard !lineData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return BridgeResponse(ok: false, error: "invalid_response", message: "Host Bridge 返回无法解析的内容")
        }

        let ok = (json["ok"] as? Bool) ?? false
        let err = json["error"] as? String
        let msg = json["message"] as? String
        let payload = (json["data"] as? [String: Any]) ?? [:]
        return BridgeResponse(ok: ok, error: err, message: msg, data: payload, raw: json)
    }
}
