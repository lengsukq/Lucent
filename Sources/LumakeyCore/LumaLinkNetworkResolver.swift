import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Darwin
import Foundation

public enum LumaLinkInterfaceKind: String, Codable, Sendable, Hashable {
    case lan
    case tunnel
    case bridge

    public var badgeTitle: String {
        switch self {
        case .lan: L10n.pick("局域网", "LAN")
        case .tunnel: L10n.pick("内网穿透/组网", "Tunnel/VPN")
        case .bridge: L10n.pick("虚拟桥接", "Bridge")
        }
    }
}

public struct LumaLinkNetworkCandidate: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let interfaceName: String
    public let ipv4: String
    public let kind: LumaLinkInterfaceKind
    public let priority: Int

    public var displayLabel: String {
        "\(kind.badgeTitle) · \(interfaceName) (\(ipv4))"
    }

    public init(interfaceName: String, ipv4: String, kind: LumaLinkInterfaceKind, priority: Int) {
        self.id = "\(interfaceName):\(ipv4)"
        self.interfaceName = interfaceName
        self.ipv4 = ipv4
        self.kind = kind
        self.priority = priority
    }
}

public enum LumaLinkNetworkResolver {
    private static let ignoredInterfacePrefixes: [String] = [
        "lo", "awdl", "llw", "anpi", "pktap", "gif", "stf", "xhc", "ap1"
    ]

    private static let tunnelInterfacePrefixes: [String] = [
        "utun", "tun", "tap", "ppp", "ipsec", "zt", "feth", "wg", "tailscale", "nebula"
    ]

    private static let bridgeInterfacePrefixes: [String] = [
        "bridge", "vmenet", "vmnet", "vboxnet", "docker"
    ]

    public static func isIgnoredIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return true }
        if parts[0] == 127 || parts[0] == 0 || parts[0] >= 224 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true } // APIPA link-local
        if parts[0] == 198 && (parts[1] == 18 || parts[1] == 19) { return true } // Clash/Surge Fake-IP benchmark subnet
        return false
    }

    public static func isRFC1918PrivateLAN(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    public static func isCarrierGradeOrTailscaleSubnet(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    public static func classifyInterface(name: String, ipv4: String) -> LumaLinkNetworkCandidate? {
        let lower = name.lowercased()
        guard !lower.isEmpty, !isIgnoredIPv4(ipv4) else { return nil }
        if ignoredInterfacePrefixes.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
            return nil
        }

        if bridgeInterfacePrefixes.contains(where: { lower.hasPrefix($0) }) {
            return LumaLinkNetworkCandidate(interfaceName: name, ipv4: ipv4, kind: .bridge, priority: 20)
        }

        if tunnelInterfacePrefixes.contains(where: { lower.hasPrefix($0) }) || isCarrierGradeOrTailscaleSubnet(ipv4) {
            return LumaLinkNetworkCandidate(interfaceName: name, ipv4: ipv4, kind: .tunnel, priority: 40)
        }

        if lower.hasPrefix("en") {
            let isPrimaryWiFiOrEth = (lower == "en0" || lower == "en1")
            let base: Int = if isRFC1918PrivateLAN(ipv4) {
                isPrimaryWiFiOrEth ? (lower == "en0" ? 100 : 96) : 90
            } else {
                isPrimaryWiFiOrEth ? 82 : 76
            }
            return LumaLinkNetworkCandidate(interfaceName: name, ipv4: ipv4, kind: .lan, priority: base)
        }

        let fallbackKind: LumaLinkNetworkInterfaceFallback = isRFC1918PrivateLAN(ipv4) ? .lan : .tunnel
        let prio = fallbackKind == .lan ? 65 : 35
        return LumaLinkNetworkCandidate(
            interfaceName: name,
            ipv4: ipv4,
            kind: fallbackKind == .lan ? .lan : .tunnel,
            priority: prio
        )
    }

    private enum LumaLinkNetworkInterfaceFallback { case lan, tunnel }

    public static func listActiveCandidates() -> [LumaLinkNetworkCandidate] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()
        var results: [LumaLinkNetworkCandidate] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ifName = String(cString: ptr.pointee.ifa_name)
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = buf.withUnsafeBufferPointer {
                String(decoding: $0.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
            guard let candidate = classifyInterface(name: ifName, ipv4: ip),
                  seen.insert(candidate.id).inserted else { continue }
            results.append(candidate)
        }

        return results.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id < rhs.id
        }
    }

    public static func resolveConnectHost(
        config: LumaLinkConfig,
        candidates: [LumaLinkNetworkCandidate] = listActiveCandidates()
    ) -> (host: String, activeCandidate: LumaLinkNetworkCandidate?, isCustomHost: Bool) {
        let custom = sanitizeHostInput(config.customConnectHost)
        if !custom.isEmpty {
            return (custom, nil, true)
        }
        let pref = config.preferredInterface.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pref.isEmpty {
            if let exact = candidates.first(where: { $0.id == pref || $0.interfaceName == pref || $0.ipv4 == pref }) {
                return (exact.ipv4, exact, false)
            }
        }
        if let best = candidates.first {
            return (best.ipv4, best, false)
        }
        return ("127.0.0.1", nil, false)
    }

    public static func sanitizeHostInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard trimmed.count <= 128,
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return ""
        }
        return trimmed
    }
}
