import Darwin
import Foundation
import PluginKit

struct NICInfo {
    var name: String
    var up: Bool
    var v4: [String]
    var v6: [String]
    var mac: String
}

private func runOut(_ exe: String, _ args: [String] = [], timeout: Double = 2.0) -> String {
    SubprocessRunner.run(executable: exe, arguments: args, timeoutSeconds: timeout).stdout
}

private func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r])
}

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
let args = input.arguments

var didFlush = false
if args.contains("--flush-dns") || ["flush", "flushdns", "刷新dns"].contains(query) {
    _ = runOut("/usr/bin/dscacheutil", ["-flushcache"])
    didFlush = true
}

let routeOut = runOut("/sbin/route", ["-n", "get", "default"])
let gateway = firstMatch(#"gateway:\s*(\S+)"#, in: routeOut) ?? (isEn ? "None" : "未连接")
let defaultIf = firstMatch(#"interface:\s*(\S+)"#, in: routeOut) ?? "en0"
let prefIf = input.cfgString("preferredInterface", default: "auto")
let primaryIf = prefIf == "auto" ? defaultIf : prefIf

let ifcfg = runOut("/sbin/ifconfig")
var nics: [NICInfo] = []
var cur: NICInfo? = nil
let hdrRe = try! NSRegularExpression(pattern: #"^([a-zA-Z0-9]+):\s+flags=.*<([^>]*)>"#)

for rawLine in ifcfg.components(separatedBy: .newlines) {
    let nsRange = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
    if let m = hdrRe.firstMatch(in: rawLine, range: nsRange),
       let nameR = Range(m.range(at: 1), in: rawLine),
       let flagsR = Range(m.range(at: 2), in: rawLine) {
        if let c = cur, (!c.v4.isEmpty || !c.v6.isEmpty) {
            nics.append(c)
        }
        let flags = rawLine[flagsR].split(separator: ",").map(String.init)
        cur = NICInfo(
            name: String(rawLine[nameR]),
            up: flags.contains("UP") && !flags.contains("LOOPBACK"),
            v4: [],
            v6: [],
            mac: ""
        )
        continue
    }
    guard var c = cur, c.up else { continue }
    let s = rawLine.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("inet ") {
        let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2 && !parts[1].hasPrefix("127.") {
            c.v4.append(parts[1])
        }
    } else if s.hasPrefix("inet6 ") {
        let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2 {
            let addr = parts[1].split(separator: "%").first.map(String.init) ?? parts[1]
            if !addr.hasPrefix("fe80:") && addr != "::1" {
                c.v6.append(addr)
            }
        }
    } else if s.hasPrefix("ether ") {
        let parts = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2 {
            c.mac = parts[1]
        }
    }
    cur = c
}
if let c = cur, (!c.v4.isEmpty || !c.v6.isEmpty) {
    nics.append(c)
}

nics.sort { a, b in
    let rankA = a.name == primaryIf ? 0 : (a.name.hasPrefix("en") ? 1 : 2)
    let rankB = b.name == primaryIf ? 0 : (b.name.hasPrefix("en") ? 1 : 2)
    return rankA != rankB ? rankA < rankB : a.name < b.name
}

let primaryIP = nics.first?.v4.first ?? "127.0.0.1"

let dnsOut = runOut("/usr/sbin/scutil", ["--dns"])
var resolvers: [String] = []
if let dnsRe = try? NSRegularExpression(pattern: #"nameserver\[\d+\]\s*:\s*(\S+)"#) {
    let range = NSRange(dnsOut.startIndex..<dnsOut.endIndex, in: dnsOut)
    for m in dnsRe.matches(in: dnsOut, range: range) {
        if let r = Range(m.range(at: 1), in: dnsOut) {
            let ipVal = String(dnsOut[r])
            if !resolvers.contains(ipVal) {
                resolvers.append(ipVal)
            }
        }
    }
}

let proxyOut = runOut("/usr/sbin/scutil", ["--proxy"])
func px(_ key: String) -> String {
    firstMatch("\\b\(NSRegularExpression.escapedPattern(for: key))\\s*:\\s*(\\S+)", in: proxyOut) ?? ""
}
var proxies: [String] = []
if px("HTTPEnable") == "1" && !px("HTTPProxy").isEmpty {
    proxies.append("HTTP \(px("HTTPProxy")):\(px("HTTPPort"))")
}
if px("SOCKSEnable") == "1" && !px("SOCKSProxy").isEmpty {
    proxies.append("SOCKS \(px("SOCKSProxy")):\(px("SOCKSPort"))")
}
let proxySummary = !proxies.isEmpty
    ? proxies.joined(separator: " · ")
    : (isEn ? "Direct (No Proxy)" : "直连 (未开启系统代理)")

let wantPub = args.contains("--public")
    || ["pub", "public", "公网"].contains(query)
    || input.cfgBool("probePublicEgress", default: false)
var pubIP = isEn ? "On-Demand" : "按需探测"
let probeEndpoint = "https" + "://api.ipify.org?format=json"
if wantPub, let url = URL(string: probeEndpoint) {
    let resp = SyncHTTPClient.request(url: url, timeoutSeconds: 1.6)
    if resp.isSuccess, let ip = resp.jsonObject()?["ip"] as? String, !ip.isEmpty {
        pubIP = ip
    } else {
        pubIP = isEn ? "Timeout/Offline" : "离线或超时"
    }
}

let scHost = runOut("/usr/sbin/scutil", ["--get", "LocalHostName"]).trimmingCharacters(in: .whitespacesAndNewlines)
let hostName = scHost.isEmpty ? ProcessInfo.processInfo.hostName : scHost
let vpnNICs = nics.filter { $0.name.hasPrefix("utun") }.map(\.name)

var items: [ViewItem] = []
for n in nics {
    let v4Txt = n.v4.isEmpty ? "IPv6 Only" : n.v4.joined(separator: ", ")
    var subParts: [String] = [
        n.name == defaultIf ? "Gateway \(gateway)" : (n.name.hasPrefix("utun") ? "VPN Tunnel" : "Active NIC")
    ]
    if !n.mac.isEmpty { subParts.append("MAC \(n.mac)") }
    if let firstV6 = n.v6.first { subParts.append("IPv6 \(firstV6)") }
    items.append(ViewItem(
        id: "nic-\(n.name)",
        title: "\(n.name) · \(v4Txt)",
        subtitle: subParts.joined(separator: " · "),
        icon: n.name.hasPrefix("utun") ? "lock.shield.fill" : "wifi",
        badge: n.name == defaultIf ? "DEFAULT" : (n.name.hasPrefix("utun") ? "VPN" : "NIC"),
        copyText: n.v4.first ?? n.v6.first ?? ""
    ))
}

let dnsJoined = resolvers.isEmpty ? (isEn ? "System Auto" : "系统自动") : resolvers.prefix(4).joined(separator: ", ")
items.append(ViewItem(
    id: "dns-chain",
    title: isEn ? "DNS Resolvers: \(dnsJoined)" : "DNS 解析链：\(dnsJoined)",
    subtitle: isEn ? "Default Gateway: \(gateway) (\(defaultIf))" : "默认路由网关：\(gateway)（出接口 \(defaultIf)）",
    icon: "server.rack",
    badge: "\(resolvers.count) DNS",
    copyText: resolvers.first ?? gateway,
    actions: [ViewAction(id: "act-flush", label: isEn ? "Flush DNS" : "刷新 DNS", commandArgs: ["--flush-dns"])]
))

let proxyCopy = proxies.first?.split(separator: " ").last.map(String.init) ?? primaryIP
items.append(ViewItem(
    id: "sys-proxy",
    title: isEn ? "System Proxy: \(proxySummary)" : "系统代理：\(proxySummary)",
    subtitle: isEn ? "Public Egress: \(pubIP)" : "公网出口：\(pubIP)",
    icon: "arrow.triangle.branch",
    badge: proxies.isEmpty ? "DIRECT" : "PROXY",
    copyText: proxyCopy,
    actions: wantPub ? [] : [ViewAction(id: "act-pub", label: isEn ? "Probe Public IP" : "查公网出口", commandArgs: ["--public"])]
))

let topBadge: String
if !vpnNICs.isEmpty && !proxies.isEmpty {
    topBadge = "VPN+PROXY"
} else if !vpnNICs.isEmpty {
    topBadge = "VPN"
} else if !proxies.isEmpty {
    topBadge = "PROXY"
} else {
    topBadge = "ONLINE"
}

let vpnMetric = wantPub ? pubIP : (vpnNICs.isEmpty ? (isEn ? "No VPN" : "无隧道") : vpnNICs.joined(separator: ", "))
let effect: PostActionEffect? = didFlush
    ? PostActionEffect(toast: isEn ? "macOS DNS cache flushed" : "已刷新本机 DNS 解析缓存")
    : nil

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Network Stack & Proxy Inspector" : "本机网络栈与代理全维诊断",
    subtitle: "\(hostName) · Default \(defaultIf) -> \(gateway)",
    badge: topBadge,
    metrics: [
        KeyValue(key: isEn ? "Primary IPv4" : "首选局域网 IP", value: primaryIP),
        KeyValue(key: isEn ? "Gateway" : "默认网关", value: "\(gateway) (\(defaultIf))"),
        KeyValue(key: isEn ? "Primary DNS" : "主用 DNS", value: resolvers.first ?? "Auto"),
        KeyValue(key: isEn ? "Public / VPN" : "公网 / 隧道", value: vpnMetric)
    ],
    items: items,
    effect: effect
))
