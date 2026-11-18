import Foundation
import PluginKit

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
                openURL: "lucent://settings/plugin/lumalink-companion"
            )
        ]
    ))
    exit(0)
}

let d = resp.data
if viewMode == "networks" { PluginOutput.emit(buildNetworksCard(d, isEn: isEn)); exit(0) }
if viewMode == "pin_detail" { PluginOutput.emit(buildPinDetailCard(d, actionTriggered: action, isEn: isEn, pinQROnTop: pinQROnTop)); exit(0) }
if viewMode == "displays" { PluginOutput.emit(buildDisplaysCard(d, actionTriggered: action, isEn: isEn)); exit(0) }
if viewMode == "devices" { PluginOutput.emit(buildDevicesCard(d, actionTriggered: action, isEn: isEn)); exit(0) }

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
        title: isEn ? (enabled ? "Stop LumaLink Remote Service" : "Start LumaLink Remote Service") : (enabled ? "停用流光随行远控服务" : "启用流光随行远控服务"),
        subtitle: summary, icon: enabled ? "pause.circle" : "play.circle.fill",
        badge: enabled ? "ON" : "OFF", commandArgs: ["--toggle"]
    )
]

if enabled {
    if showPairURI || viewMode == "qr_popup" {
        items.append(ViewItem(
            id: "pair-pin-qr",
            title: isEn ? "Pairing PIN: \(pin) · Manual Connect \(ip):\(port)" : "6 位配对码：\(pin) · 手动连接 \(ip):\(port)",
            subtitle: isEn ? "Click for manual connection breakdown, or use buttons to copy PIN / pop up QR" : "点击打开手动连接详情卡，或使用右侧按钮复制配对码 / 弹出二维码",
            icon: "key.horizontal.fill", badge: "PIN \(pin)", commandArgs: ["--pin"],
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
        icon: "key.horizontal.fill", badge: "START + PIN", commandArgs: ["--pin"]
    ))
}

items.append(contentsOf: [
    ViewItem(
        id: "toggle-rdp",
        title: isEn ? (rdpOn ? "Disable Turbo RDP Service (Port 3389)" : "Enable Turbo RDP Service (Live Screen Control)") : (rdpOn ? "关闭极速 RDP 远程桌面服务" : "开启极速 RDP 远程桌面服务（手机端看桌面必开）"),
        subtitle: isEn ? "Port \(rdpPort) · Engine: \(rdpRunning ? "Running" : "Idle") · TCC AX:\(axOK ? "OK" : "Missing") SR:\(srOK ? "OK" : "Missing")" : "端口 \(rdpPort) · 引擎：\(rdpRunning ? "运行中" : "待启动") · 辅助功能:\(axOK ? "已授" : "未授") 录屏:\(srOK ? "已授" : "未授")",
        icon: rdpOn ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle",
        badge: (rdpOn && rdpRunning) ? "RDP ON" : (rdpOn ? "STARTING" : "RDP OFF"), commandArgs: ["--toggle-rdp"]
    ),
    ViewItem(
        id: "switch-network",
        title: isEn ? "Network / IP: \(netLabel) →" : "连接网卡与 IP：\(netLabel) →",
        subtitle: isEn ? "Switch between physical LAN (Wi-Fi/Ethernet) and Tunnel/VPN (Tailscale/ZeroTier)" : "在物理局域网 (en0/en1) 与内网穿透网卡 (Tailscale/ZeroTier/utun) 之间切换",
        icon: "network", badge: "IP", commandArgs: ["--networks"]
    ),
    ViewItem(
        id: "switch-displays",
        title: isEn ? "Switch HiDPI Display Resolution →" : "切换多屏 HiDPI 分辨率与恢复 →",
        subtitle: isEn ? "Pick mobile-friendly HiDPI modes or restore native resolution" : "选择适合手机屏幕比例的 HiDPI 分辨率或一键还原原生模式",
        icon: "display", badge: dictBool(d, "hasModifiedDisplays") ? "RESTORE" : "HiDPI", commandArgs: ["--displays"]
    ),
    ViewItem(
        id: "privacy-guards",
        title: isEn ? "Privacy Curtain: \(curtainOn ? "ON" : "OFF") · Caffeine: \(caffeineOn ? "ON" : "OFF")" : "物理防窥黑屏：\(curtainOn ? "已开启" : "关闭") · 防休眠：\(caffeineOn ? "已开启" : "关闭")",
        subtitle: isEn ? "Blank physical Mac screen or keep system awake during remote control" : "远控期间遮蔽物理显示器防窥，或阻止 Mac 空闲休眠断联",
        icon: curtainOn ? "eye.slash.fill" : "lock.display", badge: "GUARD",
        actions: [
            ViewAction(id: "act-curtain", label: isEn ? (curtainOn ? "Curtain Off" : "Curtain On") : (curtainOn ? "关闭黑屏" : "开启黑屏"), commandArgs: ["--curtain"]),
            ViewAction(id: "act-caffeine", label: isEn ? (caffeineOn ? "Allow Sleep" : "Keep Awake") : (caffeineOn ? "关闭防休眠" : "开启防休眠"), commandArgs: ["--caffeine"])
        ]
    ),
    ViewItem(
        id: "manage-devices",
        title: isEn ? "Manage Paired Phones (\(paired)) →" : "管理已配对手机与解绑 (\(paired) 台) →",
        subtitle: isEn ? "Inspect authorized phones and revoke individual Vault tokens" : "查看已授权手机列表，支持二次确认吊销单台设备加密凭证",
        icon: "iphone.gen3.radiowaves.left.and.right", badge: "\(paired) DEV", commandArgs: ["--devices"]
    )
])

var toast: String? = nil, openImg: String? = nil, pinImg: String? = nil
if action == "selectNetwork" { toast = isEn ? "Switched to \(netLabel)" : "已切换连接网卡：\(netLabel)" }
if viewMode == "qr_popup" && !qrPath.isEmpty {
    if pinQROnTop { pinImg = qrPath } else { openImg = qrPath }
    toast = isEn ? "Pairing QR code ready" : "已生成并弹出扫码配对二维码"
}

let statusBadge = enabled ? "ON" : "OFF"
PluginOutput.writeRuntimeStatus(summary: summary, badge: statusBadge, to: dataDir)

PluginOutput.emit(ViewPayload(
    schemaVersion: 2, title: isEn ? "LumaLink Remote Companion" : "流光随行 · LumaLink 远控控制台",
    subtitle: summary, badge: enabled ? "ONLINE" : "IDLE",
    metrics: [
        KeyValue(key: isEn ? "PIN" : "6 位配对码", value: enabled ? pin : (isEn ? "Off" : "未开启")),
        KeyValue(key: isEn ? "Endpoint" : "手动连接地址", value: "\(ip):\(port)"),
        KeyValue(key: isEn ? "Paired" : "已配对手机", value: isEn ? "\(paired) (\(connected) live)" : "\(paired) 台 (\(connected) 在线)"),
        KeyValue(key: isEn ? "Guards" : "幕布 / 防休眠", value: "\(curtainOn ? "ON" : "OFF") / \(caffeineOn ? "ON" : "OFF")")
    ],
    items: items,
    effect: PostActionEffect(toast: toast, statusSummary: summary, statusBadge: statusBadge, openImagePath: openImg, pinImagePath: pinImg)
))
