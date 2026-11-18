import Darwin
import Foundation
import PluginKit

private let devPorts: Set<Int> = [3000, 3001, 4000, 4200, 5000, 5173, 5174, 5432, 6379, 8000, 8080, 8081, 8888, 9000, 27017]

struct PortRow {
    var port: Int
    var pid: Int
    var proc: String
    var user: String
    var binds: Set<String>
}

private func runOut(_ exe: String, _ args: [String]) -> String {
    SubprocessRunner.run(executable: exe, arguments: args, timeoutSeconds: 3.0).stdout
}

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let pinDev = input.cfgBool("highlightDevPorts", default: true)
let maxRows = input.cfgInt("maxListedPorts", default: 25, min: 5, max: 80)
let args = input.arguments

var toastMsg: String? = nil
if args.count >= 3 && args[0] == "--kill" {
    let sigName = args[1].uppercased()
    if let targetPID = Int32(args[2]) {
        let targetPort = args.count > 3 ? args[3] : ""
        let sig: Int32 = (sigName == "KILL") ? SIGKILL : SIGTERM
        if targetPID > 1 && targetPID != Darwin.getpid() {
            if Darwin.kill(targetPID, sig) == 0 {
                for _ in 0..<8 {
                    Thread.sleep(forTimeInterval: 0.05)
                    if Darwin.kill(targetPID, 0) != 0 && errno == ESRCH {
                        break
                    }
                }
                toastMsg = isEn
                    ? "Sent SIG\(sigName) to PID \(targetPID) (:\(targetPort))"
                    : "已向 PID \(targetPID) (端口 :\(targetPort)) 发送 SIG\(sigName) 释放信号"
            } else {
                let err = String(cString: strerror(errno))
                toastMsg = isEn ? "Kill failed: \(err)" : "终止进程失败：\(err)"
            }
        }
    }
}

let lsofOut = runOut("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
var entriesByKey: [String: PortRow] = [:]
var pids = Set<Int>()
let portRe = try! NSRegularExpression(pattern: #":(\d+)$"#)

for (idx, line) in lsofOut.components(separatedBy: .newlines).enumerated() {
    if idx == 0 || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
    guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
    let procName = parts[0]
    let user = parts[2]
    let addrCol = parts[8]
    let nsRange = NSRange(addrCol.startIndex..<addrCol.endIndex, in: addrCol)
    guard let m = portRe.firstMatch(in: addrCol, range: nsRange),
          let portR = Range(m.range(at: 1), in: addrCol),
          let fullR = Range(m.range(at: 0), in: addrCol),
          let port = Int(addrCol[portR]) else { continue }
    let hostPart = String(addrCol[..<fullR.lowerBound])
    let key = "\(port):\(pid)"
    if var existing = entriesByKey[key] {
        existing.binds.insert(hostPart)
        entriesByKey[key] = existing
    } else {
        entriesByKey[key] = PortRow(port: port, pid: pid, proc: procName, user: user, binds: [hostPart])
        pids.insert(pid)
    }
}

var psMeta: [Int: (rssMB: Double, etime: String, command: String)] = [:]
if !pids.isEmpty {
    let pidList = pids.sorted().map(String.init).joined(separator: ",")
    let psOut = runOut("/bin/ps", ["-p", pidList, "-o", "pid=,rss=,etime=,command="])
    let psRe = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$"#)
    for pline in psOut.components(separatedBy: .newlines) {
        let range = NSRange(pline.startIndex..<pline.endIndex, in: pline)
        if let m = psRe.firstMatch(in: pline, range: range),
           let r1 = Range(m.range(at: 1), in: pline),
           let r2 = Range(m.range(at: 2), in: pline),
           let r3 = Range(m.range(at: 3), in: pline),
           let r4 = Range(m.range(at: 4), in: pline),
           let pid = Int(pline[r1]),
           let rssKB = Double(pline[r2]) {
            let rssMB = (rssKB / 102.4).rounded() / 10.0
            psMeta[pid] = (rssMB, String(pline[r3]), pline[r4].trimmingCharacters(in: .whitespaces))
        }
    }
}

var rows = Array(entriesByKey.values)
let qClean = query.trimmingCharacters(in: CharacterSet(charactersIn: ":")).lowercased()
if !qClean.isEmpty {
    rows = rows.filter { r in
        let cmdFull = psMeta[r.pid]?.command ?? r.proc
        let hay = "\(r.port) \(r.proc) \(r.pid) \(cmdFull)".lowercased()
        return hay.contains(qClean)
    }
}

rows.sort { a, b in
    let devA = (pinDev && devPorts.contains(a.port)) ? 0 : 1
    let devB = (pinDev && devPorts.contains(b.port)) ? 0 : 1
    if devA != devB { return devA < devB }
    if a.port != b.port { return a.port < b.port }
    return a.pid < b.pid
}

let totalMatched = rows.count
let shown = Array(rows.prefix(maxRows))

var items: [ViewItem] = []
if shown.isEmpty {
    let emptyPort = (!qClean.isEmpty && qClean.allSatisfy(\.isNumber)) ? qClean : ""
    let title: String
    if isEn {
        title = !emptyPort.isEmpty ? "Port :\(emptyPort) is free" : "No matching TCP LISTEN processes"
    } else {
        title = !emptyPort.isEmpty ? "端口 :\(emptyPort) 当前空闲可用" : "未匹配到活跃的 TCP LISTEN 进程"
    }
    items.append(ViewItem(
        id: "no-listen-hit",
        title: title,
        subtitle: isEn ? "Press Return to refresh active listeners" : "未检测到监听占用，回车可重新扫描全量端口",
        icon: "checkmark.seal.fill",
        badge: "FREE",
        commandArgs: []
    ))
} else {
    for r in shown {
        let meta = psMeta[r.pid] ?? (0.0, "-", r.proc)
        let isWildcard = r.binds.contains("*") || r.binds.contains("0.0.0.0") || r.binds.contains("[::]")
        let bindScope = isWildcard ? "0.0.0.0/*" : "127.0.0.1"
        let shortCmd = meta.command.count <= 68 ? meta.command : (String(meta.command.prefix(65)) + "...")
        let isDev = devPorts.contains(r.port)
        let rssStr = String(format: "%.1f", meta.rssMB)
        items.append(ViewItem(
            id: "listen-\(r.port)-\(r.pid)",
            title: ":\(r.port) · \(r.proc) (PID \(r.pid))",
            subtitle: "\(bindScope) · \(rssStr) MB · \(meta.etime) · \(shortCmd)",
            icon: isDev ? "hammer.circle.fill" : "network",
            badge: isDev ? "DEV" : bindScope,
            copyText: String(r.pid),
            actions: [
                ViewAction(
                    id: "term-\(r.port)-\(r.pid)",
                    label: isEn ? "SIGTERM" : "优雅释放",
                    style: "primary",
                    commandArgs: ["--kill", "TERM", String(r.pid), String(r.port)],
                    confirmMessage: isEn
                        ? "Send graceful SIGTERM to \(r.proc) (PID \(r.pid)) listening on port :\(r.port)?"
                        : "确认向占用端口 :\(r.port) 的进程 \(r.proc) (PID \(r.pid)) 发送 SIGTERM 优雅退出信号吗？"
                ),
                ViewAction(
                    id: "kill-\(r.port)-\(r.pid)",
                    label: isEn ? "Force Kill" : "强杀",
                    style: "destructive",
                    commandArgs: ["--kill", "KILL", String(r.pid), String(r.port)],
                    confirmMessage: isEn
                        ? "Force-kill \(r.proc) (PID \(r.pid)) on port :\(r.port) immediately with SIGKILL?"
                        : "进程无响应时使用：确认立即使用 SIGKILL 强制终止 \(r.proc) (PID \(r.pid) · :\(r.port)) 吗？"
                )
            ]
        ))
    }
}

let devCount = rows.filter { devPorts.contains($0.port) }.count
let lanExposed = rows.filter { $0.binds.contains("*") || $0.binds.contains("0.0.0.0") }.count
let uniquePIDs = Set(rows.map(\.pid)).count

let subtitle: String
if isEn {
    subtitle = "Showing \(shown.count)/\(totalMatched) listener(s)" + (query.isEmpty ? "" : " matching '\(query)'")
} else {
    subtitle = "共 \(totalMatched) 个监听端口（当前展示 \(shown.count) 个）" + (query.isEmpty ? "" : " · 筛选「\(query)」")
}

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Dev Port & Listener Manager" : "开发端口与监听进程管家",
    subtitle: subtitle,
    badge: "\(totalMatched) LISTEN",
    metrics: [
        KeyValue(key: isEn ? "Listening" : "活跃监听端口", value: String(totalMatched)),
        KeyValue(key: isEn ? "Dev Ports" : "常见开发端口", value: String(devCount)),
        KeyValue(key: isEn ? "LAN Exposed" : "全网卡暴露 (*)", value: String(lanExposed)),
        KeyValue(key: isEn ? "Unique PIDs" : "驻留进程数", value: String(uniquePIDs))
    ],
    items: items,
    effect: toastMsg.map { PostActionEffect(toast: $0) }
))
