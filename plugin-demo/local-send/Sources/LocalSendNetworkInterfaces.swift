import Darwin
import Foundation

struct LocalSendNetworkInterface: Sendable, Equatable {
    let name: String
    let ipv4: String
    let netmask: String
    let isTunnel: Bool
    let priority: Int
}

enum LocalSendNetworkInterfaces {
    private static let ignoredPrefixes = ["lo", "awdl", "llw", "anpi", "pktap", "gif", "stf", "xhc", "ap1", "bridge", "vmenet", "vmnet", "vboxnet", "docker"]
    private static let tunnelPrefixes = ["utun", "tun", "tap", "ppp", "ipsec", "zt", "wg", "tailscale", "nebula"]

    static func listActive() -> [LocalSendNetworkInterface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()
        var results: [LocalSendNetworkInterface] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            let lower = name.lowercased()
            if ignoredPrefixes.contains(where: { lower == $0 || lower.hasPrefix($0) }) { continue }
            guard let ip = numericIPv4(addr), !isIgnoredIPv4(ip) else { continue }
            let mask = ptr.pointee.ifa_netmask.flatMap { numericIPv4($0) } ?? "255.255.255.0"
            let key = "\(name):\(ip)"
            guard seen.insert(key).inserted else { continue }

            let isTunnel = tunnelPrefixes.contains(where: { lower.hasPrefix($0) }) || isCGNAT(ip)
            let prio: Int
            if !isTunnel && lower == "en0" && isRFC1918(ip) { prio = 100 }
            else if !isTunnel && lower == "en1" && isRFC1918(ip) { prio = 95 }
            else if !isTunnel && lower.hasPrefix("en") { prio = isRFC1918(ip) ? 90 : 80 }
            else if !isTunnel && isRFC1918(ip) { prio = 70 }
            else { prio = 40 }
            results.append(LocalSendNetworkInterface(name: name, ipv4: ip, netmask: mask, isTunnel: isTunnel, priority: prio))
        }
        return results.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.ipv4 < $1.ipv4 }
    }

    static func primaryIPv4() -> String {
        listActive().first?.ipv4 ?? "127.0.0.1"
    }

    static func subnet24Targets(for ip: String) -> [String] {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return [] }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
        return (1...254).compactMap { host in
            host == parts[3] ? nil : "\(prefix)\(host)"
        }
    }

    static func isIgnoredIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return true }
        if parts[0] == 127 || parts[0] == 0 || parts[0] >= 224 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 198 && (parts[1] == 18 || parts[1] == 19) { return true }
        return false
    }

    private static func isRFC1918(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
    }

    private static func isCGNAT(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    private static func numericIPv4(_ addr: UnsafePointer<sockaddr>) -> String? {
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return buf.withUnsafeBufferPointer {
            String(decoding: $0.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        }
    }
}
