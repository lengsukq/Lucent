import Foundation
import PluginKit

private func parseCLIAndQuery(argv: [String], query: String) -> (viewMode: String, action: String, params: [String: Any]) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let flag = argv.first ?? ""

    switch flag {
    case "--toggle":
        return ("main", "toggle", ["renderQR": true])
    case "--toggle-rdp":
        return ("main", "toggleRdp", ["renderQR": true])
    case "--regen-pin":
        return ("pin_detail", "regeneratePin", ["renderQR": true])
    case "--pin":
        return ("pin_detail", "setEnabled", ["enabled": true, "renderQR": true])
    case "--networks":
        return ("networks", "status", ["renderQR": false])
    case "--select-net":
        let iface = argv.count >= 2 ? argv[1] : ""
        return ("main", "selectNetwork", ["interface": iface, "customHost": "", "renderQR": true])
    case "--curtain":
        return ("main", "toggleCurtain", ["renderQR": true])
    case "--caffeine":
        return ("main", "toggleCaffeine", ["renderQR": true])
    case "--qr":
        return ("qr_popup", "setEnabled", ["enabled": true, "renderQR": true])
    case "--displays":
        return ("displays", "status", ["includeDisplays": true, "renderQR": false])
    case "--set-mode" where argv.count >= 3:
        let dispID = Int(argv[1]) ?? 0
        return ("displays", "setDisplayMode", ["displayID": dispID, "modeKey": argv[2], "includeDisplays": true])
    case "--restore-displays":
        return ("displays", "restoreDisplays", ["includeDisplays": true])
    case "--devices":
        return ("devices", "status", ["renderQR": false])
    case "--revoke" where argv.count >= 2:
        return ("devices", "revokeDevice", ["deviceId": argv[1], "renderQR": false])
    default:
        break
    }

    if ["on", "start", "enable", "开启", "启动"].contains(q) {
        return ("main", "setEnabled", ["enabled": true, "renderQR": true])
    }
    if ["off", "stop", "disable", "关闭", "停用"].contains(q) {
        return ("main", "setEnabled", ["enabled": false, "renderQR": false])
    }
    if ["pin", "code", "manual", "配对码", "密码", "手动连接", "连接"].contains(q) {
        return ("pin_detail", "setEnabled", ["enabled": true, "renderQR": true])
    }
    if ["ip", "net", "network", "lan", "网卡", "网络", "内网穿透"].contains(q) {
        return ("networks", "status", ["renderQR": false])
    }
    if ["qr", "二维码", "扫码"].contains(q) {
        return ("qr_popup", "setEnabled", ["enabled": true, "renderQR": true])
    }
    if ["display", "displays", "hidpi", "分辨率", "屏幕"].contains(q) {
        return ("displays", "status", ["includeDisplays": true, "renderQR": false])
    }
    if ["device", "devices", "phone", "手机", "配对", "设备"].contains(q) {
        return ("devices", "status", ["renderQR": false])
    }
    if ["curtain", "黑屏", "幕布", "防窥"].contains(q) {
        return ("main", "toggleCurtain", ["renderQR": true])
    }
    if ["caffeine", "awake", "防休眠", "常亮"].contains(q) {
        return ("main", "toggleCaffeine", ["renderQR": true])
    }
    return ("main", "status", ["renderQR": true])
}

private func formatPairedTime(_ epochSec: Double, isEn: Bool) -> String {
    guard epochSec > 0 else { return isEn ? "Unknown time" : "未知时间" }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    let stamp = df.string(from: Date(timeIntervalSince1970: epochSec))
    return isEn ? "Paired at \(stamp)" : "配对于 \(stamp)"
}

private func dictInt(_ d: [String: Any], _ key: String, default def: Int = 0) -> Int {
    if let i = d[key] as? Int { return i }
    if let n = d[key] as? NSNumber { return n.intValue }
    return def
}

private func dictBool(_ d: [String: Any], _ key: String, default def: Bool = false) -> Bool {
    if let b = d[key] as? Bool { return b }
    if let n = d[key] as? NSNumber { return n.boolValue }
    return def
}

private func dictString(_ d: [String: Any], _ key: String, default def: String = "") -> String {
    let s = (d[key] as? String) ?? ""
    return s.isEmpty ? def : s
}

private func buildNetworksCard(_ d: [String: Any], isEn: Bool) -> ViewPayload {
    let interfaces = (d["networkInterfaces"] as? [[String: Any]]) ?? []
    let prefIface = dictString(d, "preferredInterface")
    let customHost = dictString(d, "customConnectHost")
    let autoSelected = prefIface.isEmpty && customHost.isEmpty

    var items: [ViewItem] = [
        ViewItem(
            id: "nav-back-main",
            title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台",
            subtitle: isEn ? "Return to remote control overview & pairing PIN" : "返回远控总开关、配对码与手动连接主视图",
            icon: "chevron.backward.circle",
            badge: "BACK",
            commandArgs: []
        ),
        ViewItem(
            id: "net-auto",
            title: isEn ? "Auto-Select Physical LAN (Recommended)" : "自动优选物理局域网网卡（推荐默认）",
            subtitle: isEn
                ? "Prioritizes Wi-Fi / Ethernet (en0/en1) and skips proxy Fake-IPs"
                : "优先选择 Wi-Fi / 以太网 (en0/en1)，自动跳过代理与内网穿透虚拟网段",
            icon: autoSelected ? "checkmark.circle.fill" : "sparkles",
            badge: autoSelected ? "ACTIVE" : "AUTO",
            commandArgs: autoSelected ? [] : ["--select-net", ""]
        )
    ]

    for cand in interfaces {
        let cid = dictString(cand, "id")
        let ifname = dictString(cand, "interfaceName")
        let ipv4 = dictString(cand, "ipv4")
        let kind = dictString(cand, "kind", default: "lan")
        let label = dictString(cand, "displayLabel", default: "\(ifname) (\(ipv4))")
        let explicitSel = customHost.isEmpty && (prefIface == cid || prefIface == ifname)
        let icon = kind == "lan" ? "wifi" : (kind == "tunnel" ? "point.3.connected.trianglepath.dotted" : "network")
        let badge = explicitSel ? "SELECTED" : (kind == "lan" ? "LAN" : kind.uppercased())
        let sub: String
        if isEn {
            sub = kind == "lan"
                ? "Physical local network interface (same Wi-Fi/router)"
                : "Intranet penetration / VPN overlay (Tailscale / ZeroTier / WireGuard)"
        } else {
            sub = kind == "lan"
                ? "物理局域网网卡（手机与 Mac 在同一路由器/Wi-Fi 下请选择此项）"
                : "内网穿透 / 异地组网虚拟网卡（跨外网通过 Tailscale / ZeroTier 远控时选择）"
        }
        items.append(ViewItem(
            id: "net-\(cid)",
            title: label,
            subtitle: sub,
            icon: explicitSel ? "checkmark.circle.fill" : icon,
            badge: badge,
            commandArgs: explicitSel ? [] : ["--select-net", cid]
        ))
    }

    items.append(ViewItem(
        id: "open-native-net-settings",
        title: isEn ? "Custom Hostname / Port in Plugin Settings →" : "在设置页填写自定义域名或修改端口 →",
        subtitle: isEn
            ? (!customHost.isEmpty ? "Current custom host: \(customHost)" : "Configure DDNS domain or custom port")
            : (!customHost.isEmpty ? "当前自定义地址：\(customHost)" : "支持填写 FRP/DDNS 域名及修改默认 59480 控制端口"),
        icon: "slider.horizontal.3",
        badge: !customHost.isEmpty ? "CUSTOM" : "SETTINGS",
        openURL: "lumakey://settings/plugin/lumalink-companion"
    ))

    return ViewPayload(
        schemaVersion: 2,
        title: isEn ? "LumaLink · Network & IP Selector" : "流光随行 · 连接网卡与 IP 选择",
        subtitle: isEn
            ? "\(interfaces.count) active IPv4 interface(s) detected"
            : "检测到 \(interfaces.count) 张可用网卡 · 点击即可切换配对二维码与手动连接地址",
        badge: "NETWORK",
        items: items
    )
}

private func buildPinDetailCard(_ d: [String: Any], actionTriggered: String, isEn: Bool, pinQROnTop: Bool) -> ViewPayload {
    let ip = dictString(d, "localIPv4", default: "127.0.0.1")
    let portRaw = dictInt(d, "port")
    let port = portRaw > 0 ? portRaw : dictInt(d, "preferredPort", default: 59480)
    let rdpPort = dictInt(d, "rdpPort", default: 3389)
    let pin = dictString(d, "pairingPin", default: "------")
    let netLabel = dictString(d, "selectedNetworkLabel", default: ip)
    let pairURI = dictString(d, "pairURI", default: "lumalink://pair?host=\(ip)&port=\(port)&pin=\(pin)")
    let qrPath = dictString(d, "qrImagePath")

    var items: [ViewItem] = [
        ViewItem(
            id: "nav-back-main",
            title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台",
            subtitle: isEn ? "Return to main LumaLink remote control overview" : "返回远控服务总览与快捷控制",
            icon: "chevron.backward.circle",
            badge: "BACK",
            commandArgs: []
        ),
        ViewItem(
            id: "copy-pin",
            title: isEn ? "6-Digit Pairing PIN: \(pin)" : "6 位安全配对码：\(pin)（回车复制）",
            subtitle: isEn
                ? "Auto-rotates after each successful pairing; 5 wrong attempts trigger 60s lockout"
                : "每次成功配对后自动轮换；连续输错 5 次自动锁定 60 秒防爆破",
            icon: "key.horizontal.fill",
            badge: "COPY PIN",
            copyText: pin,
            actions: [ViewAction(id: "act-rotate-pin", label: isEn ? "Rotate PIN" : "轮换新配对码", commandArgs: ["--regen-pin"])]
        ),
        ViewItem(
            id: "copy-host-port",
            title: isEn ? "Manual Host & Port: \(ip):\(port)" : "手动连接地址与端口：\(ip):\(port)（回车复制 IP）",
            subtitle: isEn ? "Interface: \(netLabel) · Control Port: \(port)" : "当前网卡：\(netLabel) · 控制端口：\(port)",
            icon: "network",
            badge: "HOST",
            copyText: ip,
            actions: [ViewAction(id: "act-switch-net", label: isEn ? "Switch Network/IP" : "切换网卡/IP", commandArgs: ["--networks"])]
        ),
        ViewItem(
            id: "copy-uri",
            title: isEn ? "Copy Full Pairing Link (lumalink://)" : "复制完整配对直连 URI（含 IP + 端口 + 配对码）",
            subtitle: pairURI,
            icon: "link",
            badge: "URI",
            copyText: pairURI
        )
    ]

    if !qrPath.isEmpty {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encodedQR = qrPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? qrPath
        let pinFlag = pinQROnTop ? "1" : "0"
        items.append(ViewItem(
            id: "popup-qr",
            title: isEn ? "Pop Up Scannable Pairing QR Code" : "弹出高清扫码配对二维码窗口",
            subtitle: isEn ? "Scan from LumaLink mobile client on the same network" : "手机与 Mac 在同一网络下可直接扫码一键填入连接信息",
            icon: "qrcode.viewfinder",
            badge: "QR",
            openURL: "lumakey://image?path=\(encodedQR)&pin=\(pinFlag)"
        ))
    }

    let mdBlock = isEn
        ? "**Manual Connection Guide**\n- **Host / IP**: `\(ip)`\n- **Control Port**: `\(port)`\n- **6-Digit PIN**: `\(pin)`\n- **RDP Port (Optional)**: `\(rdpPort)`"
        : "**手机端手动连接四要素**\n- **主机地址 (Host / IP)**：`\(ip)`（\(netLabel)）\n- **控制端口 (Port)**：`\(port)`\n- **6 位配对码 (PIN)**：`\(pin)`\n- **RDP 桌面端口（可选）**：`\(rdpPort)`"

    let eff = actionTriggered == "regeneratePin"
        ? PostActionEffect(toast: isEn ? "New PIN: \(pin)" : "已生成新 6 位配对码：\(pin)")
        : nil

    return ViewPayload(
        schemaVersion: 2,
        title: isEn ? "PIN: \(pin) · \(ip):\(port)" : "配对码：\(pin) · 连接地址 \(ip):\(port)",
        subtitle: isEn
            ? "Select any row below to copy or switch network interface"
            : "回车即可复制对应项；若 IP 显示为内网穿透网卡可点击「切换网卡/IP」改为局域网",
        badge: "PIN READY",
        markdown: mdBlock,
        items: items,
        effect: eff
    )
}

private func buildDisplaysCard(_ d: [String: Any], actionTriggered: String, isEn: Bool) -> ViewPayload {
    let displays = (d["displays"] as? [[String: Any]]) ?? []
    let modified = dictBool(d, "hasModifiedDisplays")
    var items: [ViewItem] = [
        ViewItem(
            id: "nav-back-main",
            title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台",
            subtitle: isEn ? "Return to service, QR pairing, privacy curtain & RDP controls" : "返回远控开关、扫码配对、隐私幕布与 RDP 主视图",
            icon: "chevron.backward.circle",
            badge: "BACK",
            commandArgs: []
        )
    ]
    if modified {
        items.append(ViewItem(
            id: "restore-native-displays",
            title: isEn ? "Restore Original Display Resolutions" : "一键恢复切换前的原生分辨率",
            subtitle: isEn ? "Revert all displays modified during remote session" : "还原远控期间调整过的全部显示器模式",
            icon: "arrow.uturn.backward.circle.fill",
            badge: "RESTORE",
            commandArgs: ["--restore-displays"]
        ))
    }

    for disp in displays {
        let dispID = dictInt(disp, "displayID")
        let dispName = dictString(disp, "name", default: "Display \(dispID)")
        let modes = (disp["modes"] as? [[String: Any]]) ?? []
        for m in modes {
            let modeKey = dictString(m, "modeKey")
            let isCur = dictBool(m, "isCurrent")
            let label = dictString(m, "label", default: modeKey)
            let hz = dictInt(m, "refreshHz", default: 60)
            let isHiDPI = dictBool(m, "isHiDPI")
            items.append(ViewItem(
                id: "mode-\(dispID)-\(modeKey)",
                title: "\(dispName) · \(label)",
                subtitle: "\(modeKey) · \(hz)Hz",
                icon: isCur ? "checkmark.circle.fill" : "display",
                badge: isCur ? "CURRENT" : (isHiDPI ? "HiDPI" : "STD"),
                commandArgs: isCur ? [] : ["--set-mode", String(dispID), modeKey]
            ))
        }
    }

    var toast: String? = nil
    if actionTriggered == "setDisplayMode" {
        toast = isEn ? "Display resolution updated" : "已切换显示器分辨率"
    } else if actionTriggered == "restoreDisplays" {
        toast = isEn ? "Original display modes restored" : "已恢复原生显示分辨率"
    }

    return ViewPayload(
        schemaVersion: 2,
        title: isEn ? "LumaLink · Display Resolution Switcher" : "流光随行 · 多屏 HiDPI 分辨率切换",
        subtitle: isEn ? "\(displays.count) active display(s)" : "检测到 \(displays.count) 台活跃显示器 · 点击条目立即切换",
        badge: "DISPLAY",
        items: items,
        effect: toast.map { PostActionEffect(toast: $0) }
    )
}

private func buildDevicesCard(_ d: [String: Any], actionTriggered: String, isEn: Bool) -> ViewPayload {
    let devices = (d["pairedDevices"] as? [[String: Any]]) ?? []
    var items: [ViewItem] = [
        ViewItem(
            id: "nav-back-main",
            title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台",
            subtitle: isEn ? "Return to main LumaLink remote control overview" : "返回远控服务状态与快捷控制中心",
            icon: "chevron.backward.circle",
            badge: "BACK",
            commandArgs: []
        )
    ]

    if devices.isEmpty {
        items.append(ViewItem(
            id: "empty-devices",
            title: isEn ? "No Paired Phones Yet" : "当前暂无已配对手机",
            subtitle: isEn
                ? "Enable LumaLink and scan the pairing QR code or enter 6-digit PIN"
                : "启用远控服务后，在手机端扫码或手动输入主机 IP + 端口 + 6 位配对码即可绑定",
            icon: "iphone.slash",
            badge: "EMPTY",
            commandArgs: ["--pin"]
        ))
    } else {
        for dev in devices {
            let devID = dictString(dev, "id")
            let devName = dictString(dev, "name", default: isEn ? "Mobile Device" : "移动设备")
            let pairedAt = (dev["pairedAt"] as? NSNumber)?.doubleValue ?? 0
            items.append(ViewItem(
                id: "dev-\(devID)",
                title: devName,
                subtitle: "\(formatPairedTime(pairedAt, isEn: isEn)) · Token Vault Sealed",
                icon: "iphone.gen3",
                badge: "PAIRED",
                actions: [
                    ViewAction(
                        id: "revoke-\(devID)",
                        label: isEn ? "Revoke" : "解绑吊销",
                        style: "destructive",
                        commandArgs: ["--revoke", devID],
                        confirmMessage: isEn
                            ? "Revoke paired phone '\(devName)' and delete its encrypted token?"
                            : "确认解绑「\(devName)」并立即从保险箱吊销其配对凭证吗？"
                    )
                ]
            ))
        }
    }

    let eff = actionTriggered == "revokeDevice"
        ? PostActionEffect(toast: isEn ? "Paired device revoked" : "已吊销该设备的配对凭证")
        : nil

    return ViewPayload(
        schemaVersion: 2,
        title: isEn ? "LumaLink · Paired Devices" : "流光随行 · 已配对手机管理",
        subtitle: isEn
            ? "\(devices.count) authorized device(s) · Tokens encrypted in LocalSecretVault"
            : "共 \(devices.count) 台授权设备 · 令牌由本机 AES-GCM 保险箱密封",
        badge: "\(devices.count) DEV",
        items: items,
        effect: eff
    )
}

let input = PluginInput.read()
let isEn = input.isEnglish
let showPairURI = input.cfgBool("showPairURIInCard", default: true)
let pinQROnTop = input.cfgBool("pinQRWindowOnTop", default: true)
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 4)

let (viewMode, action, params) = parseCLIAndQuery(argv: input.arguments, query: input.query)
let resp = bridge.call(capability: "lumaLinkStatus", action: action, params: params)

if !resp.ok {
    let fallbackMsg = isEn
        ? "Open LumaLink Plugin Settings to view PIN, pick network IP, or grant Host Bridge."
        : "打开流光随行设置页即可直接查看 6 位配对码、切换网卡 IP，或开启 lumaLinkStatus 浮窗桥接授权。"
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "LumaLink · Open Console & Grant Bridge" : "流光随行 · 打开控制台查看配对码或授权浮窗",
        subtitle: (resp.message?.isEmpty == false) ? resp.message! : fallbackMsg,
        badge: "SETUP",
        items: [
            ViewItem(
                id: "grant-cap",
                title: isEn
                    ? "Open LumaLink Settings (PIN, Network Switcher & Bridge Grant)"
                    : "打开流光随行设置页（直接查看配对码 / 切换局域网网卡 / 授权桥接）",
                subtitle: isEn
                    ? "Manage listener, 6-digit PIN, LAN vs Tunnel IP & permissions"
                    : "设置页顶部已内置完整远控开关、网卡选择器、6 位配对码与手动连接参数",
                icon: "ipad.and.iphone",
                badge: "OPEN",
                openURL: "lumakey://settings/plugin/lumalink-companion"
            )
        ]
    ))
    exit(0)
}

let d = resp.data
if viewMode == "networks" {
    PluginOutput.emit(buildNetworksCard(d, isEn: isEn)); exit(0)
}
if viewMode == "pin_detail" {
    PluginOutput.emit(buildPinDetailCard(d, actionTriggered: action, isEn: isEn, pinQROnTop: pinQROnTop)); exit(0)
}
if viewMode == "displays" {
    PluginOutput.emit(buildDisplaysCard(d, actionTriggered: action, isEn: isEn)); exit(0)
}
if viewMode == "devices" {
    PluginOutput.emit(buildDevicesCard(d, actionTriggered: action, isEn: isEn)); exit(0)
}

let enabled = dictBool(d, "enabled")
let listening = dictBool(d, "isListening")
let ip = dictString(d, "localIPv4", default: "127.0.0.1")
let netLabel = dictString(d, "selectedNetworkLabel", default: ip)
let portRaw = dictInt(d, "port")
let port = portRaw > 0 ? portRaw : dictInt(d, "preferredPort", default: 59480)
let pin = dictString(d, "pairingPin", default: "------")
let qrPath = dictString(d, "qrImagePath")
let connected = dictInt(d, "connectedDeviceCount")
let paired = dictInt(d, "pairedDeviceCount")
let rdpOn = dictBool(d, "rdpEnabled")
let rdpRunning = dictBool(d, "rdpRunning")
let rdpPort = dictInt(d, "rdpPort", default: 3389)
let curtainOn = dictBool(d, "curtainActive")
let caffeineOn = dictBool(d, "caffeineActive")
let axOK = dictBool(d, "accessibilityTrusted", default: true)
let srOK = dictBool(d, "screenRecordingTrusted", default: true)

let summary: String
if enabled && listening {
    summary = isEn ? "Listening \(ip):\(port) · PIN \(pin) · \(connected) active" : "监听 \(ip):\(port) · 配对码 \(pin) · 在线 \(connected) 台"
} else if enabled {
    summary = isEn ? "Starting on \(ip):\(port) · PIN \(pin)" : "正在启动监听 \(ip):\(port) · 配对码 \(pin)"
} else {
    summary = isEn ? "Stopped · Zero resident ports" : "已停用 · 零监听零端口占用"
}

var items: [ViewItem] = [
    ViewItem(
        id: "toggle-service",
        title: isEn
            ? (enabled ? "Stop LumaLink Remote Service" : "Start LumaLink Remote Service")
            : (enabled ? "停用流光随行远控服务" : "启用流光随行远控服务"),
        subtitle: summary,
        icon: enabled ? "pause.circle" : "play.circle.fill",
        badge: enabled ? "ON" : "OFF",
        commandArgs: ["--toggle"]
    )
]

if enabled {
    if showPairURI || viewMode == "qr_popup" {
        items.append(ViewItem(
            id: "pair-pin-qr",
            title: isEn ? "Pairing PIN: \(pin) · Manual Connect \(ip):\(port)" : "6 位配对码：\(pin) · 手动连接 \(ip):\(port)",
            subtitle: isEn
                ? "Click for manual connection breakdown, or use buttons to copy PIN / pop up QR"
                : "点击打开手动连接详情卡，或使用右侧按钮复制配对码 / 弹出二维码",
            icon: "key.horizontal.fill",
            badge: "PIN \(pin)",
            commandArgs: ["--pin"],
            actions: [
                ViewAction(id: "rotate-pin", label: isEn ? "Rotate PIN" : "轮换配对码", commandArgs: ["--regen-pin"]),
                ViewAction(id: "pop-qr", label: isEn ? "QR Code" : "扫码二维码", commandArgs: ["--qr"])
            ]
        ))
    }
} else {
    items.append(ViewItem(
        id: "start-and-show-pin",
        title: isEn ? "Enable & Show 6-Digit Pairing PIN / Manual Connect →" : "一键开启并查看 6 位配对码与手动连接地址 →",
        subtitle: isEn ? "Target endpoint: \(ip):\(port) (\(netLabel))" : "目标连接地址：\(ip):\(port)（\(netLabel)）",
        icon: "key.horizontal.fill",
        badge: "START + PIN",
        commandArgs: ["--pin"]
    ))
}

items.append(contentsOf: [
    ViewItem(
        id: "toggle-rdp",
        title: isEn
            ? (rdpOn ? "Disable Turbo RDP Service (Port 3389)" : "Enable Turbo RDP Service (Live Screen Control)")
            : (rdpOn ? "关闭极速 RDP 远程桌面服务" : "开启极速 RDP 远程桌面服务（手机端看桌面必开）"),
        subtitle: isEn
            ? "Port \(rdpPort) · Engine: \(rdpRunning ? "Running" : "Idle") · TCC AX:\(axOK ? "OK" : "Missing") SR:\(srOK ? "OK" : "Missing")"
            : "端口 \(rdpPort) · 引擎：\(rdpRunning ? "运行中" : "待启动") · 辅助功能:\(axOK ? "已授" : "未授") 录屏:\(srOK ? "已授" : "未授")",
        icon: rdpOn ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle",
        badge: (rdpOn && rdpRunning) ? "RDP ON" : (rdpOn ? "STARTING" : "RDP OFF"),
        commandArgs: ["--toggle-rdp"]
    ),
    ViewItem(
        id: "switch-network",
        title: isEn ? "Network / IP: \(netLabel) →" : "连接网卡与 IP：\(netLabel) →",
        subtitle: isEn
            ? "Switch between physical LAN (Wi-Fi/Ethernet) and Tunnel/VPN (Tailscale/ZeroTier)"
            : "在物理局域网 (en0/en1) 与内网穿透网卡 (Tailscale/ZeroTier/utun) 之间切换",
        icon: "network",
        badge: "IP",
        commandArgs: ["--networks"]
    ),
    ViewItem(
        id: "switch-displays",
        title: isEn ? "Switch HiDPI Display Resolution →" : "切换多屏 HiDPI 分辨率与恢复 →",
        subtitle: isEn
            ? "Pick mobile-friendly HiDPI modes or restore native resolution"
            : "选择适合手机屏幕比例的 HiDPI 分辨率或一键还原原生模式",
        icon: "display",
        badge: dictBool(d, "hasModifiedDisplays") ? "RESTORE" : "HiDPI",
        commandArgs: ["--displays"]
    ),
    ViewItem(
        id: "privacy-guards",
        title: isEn
            ? "Privacy Curtain: \(curtainOn ? "ON" : "OFF") · Caffeine: \(caffeineOn ? "ON" : "OFF")"
            : "物理防窥黑屏：\(curtainOn ? "已开启" : "关闭") · 防休眠：\(caffeineOn ? "已开启" : "关闭")",
        subtitle: isEn
            ? "Blank physical Mac screen or keep system awake during remote control"
            : "远控期间遮蔽物理显示器防窥，或阻止 Mac 空闲休眠断联",
        icon: curtainOn ? "eye.slash.fill" : "lock.display",
        badge: "GUARD",
        actions: [
            ViewAction(id: "act-curtain", label: isEn ? (curtainOn ? "Curtain Off" : "Curtain On") : (curtainOn ? "关闭黑屏" : "开启黑屏"), commandArgs: ["--curtain"]),
            ViewAction(id: "act-caffeine", label: isEn ? (caffeineOn ? "Allow Sleep" : "Keep Awake") : (caffeineOn ? "关闭防休眠" : "开启防休眠"), commandArgs: ["--caffeine"])
        ]
    ),
    ViewItem(
        id: "manage-devices",
        title: isEn ? "Manage Paired Phones (\(paired)) →" : "管理已配对手机与解绑 (\(paired) 台) →",
        subtitle: isEn
            ? "Inspect authorized phones and revoke individual Vault tokens"
            : "查看已授权手机列表，支持二次确认吊销单台设备加密凭证",
        icon: "iphone.gen3.radiowaves.left.and.right",
        badge: "\(paired) DEV",
        commandArgs: ["--devices"]
    )
])

var toast: String? = nil
var openImg: String? = nil
var pinImg: String? = nil
if action == "selectNetwork" {
    toast = isEn ? "Switched to \(netLabel)" : "已切换连接网卡：\(netLabel)"
}
if viewMode == "qr_popup" && !qrPath.isEmpty {
    if pinQROnTop { pinImg = qrPath } else { openImg = qrPath }
    toast = isEn ? "Pairing QR code ready" : "已生成并弹出扫码配对二维码"
}

let statusBadge = enabled ? "ON" : "OFF"
PluginOutput.writeRuntimeStatus(summary: summary, badge: statusBadge, to: dataDir)

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "LumaLink Remote Companion" : "流光随行 · LumaLink 远控控制台",
    subtitle: summary,
    badge: enabled ? "ONLINE" : "IDLE",
    metrics: [
        KeyValue(key: isEn ? "PIN" : "6 位配对码", value: enabled ? pin : (isEn ? "Off" : "未开启")),
        KeyValue(key: isEn ? "Endpoint" : "手动连接地址", value: "\(ip):\(port)"),
        KeyValue(key: isEn ? "Paired" : "已配对手机", value: isEn ? "\(paired) (\(connected) live)" : "\(paired) 台 (\(connected) 在线)"),
        KeyValue(key: isEn ? "Guards" : "幕布 / 防休眠", value: "\(curtainOn ? "ON" : "OFF") / \(caffeineOn ? "ON" : "OFF")")
    ],
    items: items,
    effect: PostActionEffect(
        toast: toast,
        statusSummary: summary,
        statusBadge: statusBadge,
        openImagePath: openImg,
        pinImagePath: pinImg
    )
))
