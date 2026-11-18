import Foundation
import PluginKit

func parseCLIAndQuery(argv: [String], query: String) -> (viewMode: String, action: String, params: [String: Any]) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let flag = argv.first ?? ""
    switch flag {
    case "--toggle": return ("main", "toggle", ["renderQR": true])
    case "--toggle-rdp": return ("main", "toggleRdp", ["renderQR": true])
    case "--regen-pin": return ("pin_detail", "regeneratePin", ["renderQR": true])
    case "--pin": return ("pin_detail", "setEnabled", ["enabled": true, "renderQR": true])
    case "--networks": return ("networks", "status", ["renderQR": false])
    case "--select-net":
        let iface = argv.count >= 2 ? argv[1] : ""
        return ("main", "selectNetwork", ["interface": iface, "customHost": "", "renderQR": true])
    case "--curtain": return ("main", "toggleCurtain", ["renderQR": true])
    case "--caffeine": return ("main", "toggleCaffeine", ["renderQR": true])
    case "--qr": return ("qr_popup", "setEnabled", ["enabled": true, "renderQR": true])
    case "--displays": return ("displays", "status", ["includeDisplays": true, "renderQR": false])
    case "--set-mode" where argv.count >= 3:
        return ("displays", "setDisplayMode", ["displayID": Int(argv[1]) ?? 0, "modeKey": argv[2], "includeDisplays": true])
    case "--restore-displays": return ("displays", "restoreDisplays", ["includeDisplays": true])
    case "--devices": return ("devices", "status", ["renderQR": false])
    case "--revoke" where argv.count >= 2: return ("devices", "revokeDevice", ["deviceId": argv[1], "renderQR": false])
    default: break
    }

    if ["on", "start", "enable", "开启", "启动"].contains(q) { return ("main", "setEnabled", ["enabled": true, "renderQR": true]) }
    if ["off", "stop", "disable", "关闭", "停用"].contains(q) { return ("main", "setEnabled", ["enabled": false, "renderQR": false]) }
    if ["pin", "code", "manual", "配对码", "密码", "手动连接", "连接"].contains(q) { return ("pin_detail", "setEnabled", ["enabled": true, "renderQR": true]) }
    if ["ip", "net", "network", "lan", "网卡", "网络", "内网穿透"].contains(q) { return ("networks", "status", ["renderQR": false]) }
    if ["qr", "二维码", "扫码"].contains(q) { return ("qr_popup", "setEnabled", ["enabled": true, "renderQR": true]) }
    if ["display", "displays", "hidpi", "分辨率", "屏幕"].contains(q) { return ("displays", "status", ["includeDisplays": true, "renderQR": false]) }
    if ["device", "devices", "phone", "手机", "配对", "设备"].contains(q) { return ("devices", "status", ["renderQR": false]) }
    if ["curtain", "黑屏", "幕布", "防窥"].contains(q) { return ("main", "toggleCurtain", ["renderQR": true]) }
    if ["caffeine", "awake", "防休眠", "常亮"].contains(q) { return ("main", "toggleCaffeine", ["renderQR": true]) }
    return ("main", "status", ["renderQR": true])
}

func formatPairedTime(_ epochSec: Double, isEn: Bool) -> String {
    guard epochSec > 0 else { return isEn ? "Unknown time" : "未知时间" }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    let stamp = df.string(from: Date(timeIntervalSince1970: epochSec))
    return isEn ? "Paired at \(stamp)" : "配对于 \(stamp)"
}

func dictInt(_ d: [String: Any], _ key: String, default def: Int = 0) -> Int {
    (d[key] as? Int) ?? (d[key] as? NSNumber)?.intValue ?? def
}

func dictBool(_ d: [String: Any], _ key: String, default def: Bool = false) -> Bool {
    (d[key] as? Bool) ?? (d[key] as? NSNumber)?.boolValue ?? def
}

func dictString(_ d: [String: Any], _ key: String, default def: String = "") -> String {
    let s = (d[key] as? String) ?? ""
    return s.isEmpty ? def : s
}

func buildNetworksCard(_ d: [String: Any], isEn: Bool) -> ViewPayload {
    let interfaces = (d["networkInterfaces"] as? [[String: Any]]) ?? []
    let prefIface = dictString(d, "preferredInterface")
    let customHost = dictString(d, "customConnectHost")
    let autoSelected = prefIface.isEmpty && customHost.isEmpty

    var items: [ViewItem] = [
        ViewItem(id: "nav-back-main", title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台", subtitle: isEn ? "Return to remote control overview & pairing PIN" : "返回远控总开关、配对码与手动连接主视图", icon: "chevron.backward.circle", badge: "BACK", commandArgs: []),
        ViewItem(id: "net-auto", title: isEn ? "Auto-Select Physical LAN (Recommended)" : "自动优选物理局域网网卡（推荐默认）", subtitle: isEn ? "Prioritizes Wi-Fi / Ethernet (en0/en1) and skips proxy Fake-IPs" : "优先选择 Wi-Fi / 以太网 (en0/en1)，自动跳过代理与内网穿透虚拟网段", icon: autoSelected ? "checkmark.circle.fill" : "sparkles", badge: autoSelected ? "ACTIVE" : "AUTO", commandArgs: autoSelected ? [] : ["--select-net", ""])
    ]

    for cand in interfaces {
        let cid = dictString(cand, "id"), ifname = dictString(cand, "interfaceName")
        let ipv4 = dictString(cand, "ipv4"), kind = dictString(cand, "kind", default: "lan")
        let label = dictString(cand, "displayLabel", default: "\(ifname) (\(ipv4))")
        let explicitSel = customHost.isEmpty && (prefIface == cid || prefIface == ifname)
        let icon = kind == "lan" ? "wifi" : (kind == "tunnel" ? "point.3.connected.trianglepath.dotted" : "network")
        let sub = isEn
            ? (kind == "lan" ? "Physical local network interface (same Wi-Fi/router)" : "Intranet penetration / VPN overlay (Tailscale / ZeroTier / WireGuard)")
            : (kind == "lan" ? "物理局域网网卡（手机与 Mac 在同一路由器/Wi-Fi 下请选择此项）" : "内网穿透 / 异地组网虚拟网卡（跨外网通过 Tailscale / ZeroTier 远控时选择）")
        items.append(ViewItem(id: "net-\(cid)", title: label, subtitle: sub, icon: explicitSel ? "checkmark.circle.fill" : icon, badge: explicitSel ? "SELECTED" : (kind == "lan" ? "LAN" : kind.uppercased()), commandArgs: explicitSel ? [] : ["--select-net", cid]))
    }

    items.append(ViewItem(
        id: "open-native-net-settings",
        title: isEn ? "Custom Hostname / Port in Plugin Settings →" : "在设置页填写自定义域名或修改端口 →",
        subtitle: isEn ? (!customHost.isEmpty ? "Current custom host: \(customHost)" : "Configure DDNS domain or custom port") : (!customHost.isEmpty ? "当前自定义地址：\(customHost)" : "支持填写 FRP/DDNS 域名及修改默认 59480 控制端口"),
        icon: "slider.horizontal.3", badge: !customHost.isEmpty ? "CUSTOM" : "SETTINGS",
        openURL: "lucent://settings/plugin/lumalink-companion"
    ))

    return ViewPayload(schemaVersion: 2, title: isEn ? "LumaLink · Network & IP Selector" : "流光随行 · 连接网卡与 IP 选择", subtitle: isEn ? "\(interfaces.count) active IPv4 interface(s) detected" : "检测到 \(interfaces.count) 张可用网卡 · 点击即可切换配对二维码与手动连接地址", badge: "NETWORK", items: items)
}

func buildPinDetailCard(_ d: [String: Any], actionTriggered: String, isEn: Bool, pinQROnTop: Bool) -> ViewPayload {
    let ip = dictString(d, "localIPv4", default: "127.0.0.1")
    let portRaw = dictInt(d, "port")
    let port = portRaw > 0 ? portRaw : dictInt(d, "preferredPort", default: 59480)
    let rdpPort = dictInt(d, "rdpPort", default: 3389)
    let pin = dictString(d, "pairingPin", default: "------")
    let netLabel = dictString(d, "selectedNetworkLabel", default: ip)
    let pairURI = dictString(d, "pairURI", default: "lumalink://pair?host=\(ip)&port=\(port)&pin=\(pin)")
    let qrPath = dictString(d, "qrImagePath")

    var items: [ViewItem] = [
        ViewItem(id: "nav-back-main", title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台", subtitle: isEn ? "Return to main LumaLink remote control overview" : "返回远控服务总览与快捷控制", icon: "chevron.backward.circle", badge: "BACK", commandArgs: []),
        ViewItem(id: "copy-pin", title: isEn ? "6-Digit Pairing PIN: \(pin)" : "6 位安全配对码：\(pin)（回车复制）", subtitle: isEn ? "Auto-rotates after each successful pairing; 5 wrong attempts trigger 60s lockout" : "每次成功配对后自动轮换；连续输错 5 次自动锁定 60 秒防爆破", icon: "key.horizontal.fill", badge: "COPY PIN", copyText: pin, actions: [ViewAction(id: "act-rotate-pin", label: isEn ? "Rotate PIN" : "轮换新配对码", commandArgs: ["--regen-pin"])]),
        ViewItem(id: "copy-host-port", title: isEn ? "Manual Host & Port: \(ip):\(port)" : "手动连接地址与端口：\(ip):\(port)（回车复制 IP）", subtitle: isEn ? "Interface: \(netLabel) · Control Port: \(port)" : "当前网卡：\(netLabel) · 控制端口：\(port)", icon: "network", badge: "HOST", copyText: ip, actions: [ViewAction(id: "act-switch-net", label: isEn ? "Switch Network/IP" : "切换网卡/IP", commandArgs: ["--networks"])]),
        ViewItem(id: "copy-uri", title: isEn ? "Copy Full Pairing Link (lumalink://)" : "复制完整配对直连 URI（含 IP + 端口 + 配对码）", subtitle: pairURI, icon: "link", badge: "URI", copyText: pairURI)
    ]

    if !qrPath.isEmpty {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encodedQR = qrPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? qrPath
        items.append(ViewItem(id: "popup-qr", title: isEn ? "Pop Up Scannable Pairing QR Code" : "弹出高清扫码配对二维码窗口", subtitle: isEn ? "Scan from LumaLink mobile client on the same network" : "手机与 Mac 在同一网络下可直接扫码一键填入连接信息", icon: "qrcode.viewfinder", badge: "QR", openURL: "lucent://image?path=\(encodedQR)&pin=\(pinQROnTop ? "1" : "0")"))
    }

    let mdBlock = isEn
        ? "**Manual Connection Guide**\n- **Host / IP**: `\(ip)`\n- **Control Port**: `\(port)`\n- **6-Digit PIN**: `\(pin)`\n- **RDP Port (Optional)**: `\(rdpPort)`"
        : "**手机端手动连接四要素**\n- **主机地址 (Host / IP)**：`\(ip)`（\(netLabel)）\n- **控制端口 (Port)**：`\(port)`\n- **6 位配对码 (PIN)**：`\(pin)`\n- **RDP 桌面端口（可选）**：`\(rdpPort)`"
    let eff = actionTriggered == "regeneratePin" ? PostActionEffect(toast: isEn ? "New PIN: \(pin)" : "已生成新 6 位配对码：\(pin)") : nil

    return ViewPayload(schemaVersion: 2, title: isEn ? "PIN: \(pin) · \(ip):\(port)" : "配对码：\(pin) · 连接地址 \(ip):\(port)", subtitle: isEn ? "Select any row below to copy or switch network interface" : "回车即可复制对应项；若 IP 显示为内网穿透网卡可点击「切换网卡/IP」改为局域网", badge: "PIN READY", markdown: mdBlock, items: items, effect: eff)
}

func buildDisplaysCard(_ d: [String: Any], actionTriggered: String, isEn: Bool) -> ViewPayload {
    let displays = (d["displays"] as? [[String: Any]]) ?? []
    var items: [ViewItem] = [
        ViewItem(id: "nav-back-main", title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台", subtitle: isEn ? "Return to service, QR pairing, privacy curtain & RDP controls" : "返回远控开关、扫码配对、隐私幕布与 RDP 主视图", icon: "chevron.backward.circle", badge: "BACK", commandArgs: [])
    ]
    if dictBool(d, "hasModifiedDisplays") {
        items.append(ViewItem(id: "restore-native-displays", title: isEn ? "Restore Original Display Resolutions" : "一键恢复切换前的原生分辨率", subtitle: isEn ? "Revert all displays modified during remote session" : "还原远控期间调整过的全部显示器模式", icon: "arrow.uturn.backward.circle.fill", badge: "RESTORE", commandArgs: ["--restore-displays"]))
    }
    for disp in displays {
        let dispID = dictInt(disp, "displayID"), dispName = dictString(disp, "name", default: "Display \(dispID)")
        for m in (disp["modes"] as? [[String: Any]]) ?? [] {
            let modeKey = dictString(m, "modeKey"), isCur = dictBool(m, "isCurrent")
            let label = dictString(m, "label", default: modeKey), hz = dictInt(m, "refreshHz", default: 60)
            items.append(ViewItem(id: "mode-\(dispID)-\(modeKey)", title: "\(dispName) · \(label)", subtitle: "\(modeKey) · \(hz)Hz", icon: isCur ? "checkmark.circle.fill" : "display", badge: isCur ? "CURRENT" : (dictBool(m, "isHiDPI") ? "HiDPI" : "STD"), commandArgs: isCur ? [] : ["--set-mode", String(dispID), modeKey]))
        }
    }
    let toast: String? = actionTriggered == "setDisplayMode" ? (isEn ? "Display resolution updated" : "已切换显示器分辨率") : (actionTriggered == "restoreDisplays" ? (isEn ? "Original display modes restored" : "已恢复原生显示分辨率") : nil)
    return ViewPayload(schemaVersion: 2, title: isEn ? "LumaLink · Display Resolution Switcher" : "流光随行 · 多屏 HiDPI 分辨率切换", subtitle: isEn ? "\(displays.count) active display(s)" : "检测到 \(displays.count) 台活跃显示器 · 点击条目立即切换", badge: "DISPLAY", items: items, effect: toast.map { PostActionEffect(toast: $0) })
}

func buildDevicesCard(_ d: [String: Any], actionTriggered: String, isEn: Bool) -> ViewPayload {
    let devices = (d["pairedDevices"] as? [[String: Any]]) ?? []
    var items: [ViewItem] = [
        ViewItem(id: "nav-back-main", title: isEn ? "← Back to LumaLink Console" : "← 返回流光随行主控台", subtitle: isEn ? "Return to main LumaLink remote control overview" : "返回远控服务状态与快捷控制中心", icon: "chevron.backward.circle", badge: "BACK", commandArgs: [])
    ]
    if devices.isEmpty {
        items.append(ViewItem(id: "empty-devices", title: isEn ? "No Paired Phones Yet" : "当前暂无已配对手机", subtitle: isEn ? "Enable LumaLink and scan the pairing QR code or enter 6-digit PIN" : "启用远控服务后，在手机端扫码或手动输入主机 IP + 端口 + 6 位配对码即可绑定", icon: "iphone.slash", badge: "EMPTY", commandArgs: ["--pin"]))
    } else {
        for dev in devices {
            let devID = dictString(dev, "id"), devName = dictString(dev, "name", default: isEn ? "Mobile Device" : "移动设备")
            let pairedAt = (dev["pairedAt"] as? NSNumber)?.doubleValue ?? 0
            items.append(ViewItem(id: "dev-\(devID)", title: devName, subtitle: "\(formatPairedTime(pairedAt, isEn: isEn)) · Token Vault Sealed", icon: "iphone.gen3", badge: "PAIRED", actions: [
                ViewAction(id: "revoke-\(devID)", label: isEn ? "Revoke" : "解绑吊销", style: "destructive", commandArgs: ["--revoke", devID], confirmMessage: isEn ? "Revoke paired phone '\(devName)' and delete its encrypted token?" : "确认解绑「\(devName)」并立即从保险箱吊销其配对凭证吗？")
            ]))
        }
    }
    let eff = actionTriggered == "revokeDevice" ? PostActionEffect(toast: isEn ? "Paired device revoked" : "已吊销该设备的配对凭证") : nil
    return ViewPayload(schemaVersion: 2, title: isEn ? "LumaLink · Paired Devices" : "流光随行 · 已配对手机管理", subtitle: isEn ? "\(devices.count) authorized device(s) · Tokens encrypted in LocalSecretVault" : "共 \(devices.count) 台授权设备 · 令牌由本机 AES-GCM 保险箱密封", badge: "\(devices.count) DEV", items: items, effect: eff)
}
