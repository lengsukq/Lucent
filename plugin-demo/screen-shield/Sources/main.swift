import Foundation
import PluginKit

let input = PluginInput.read()
let isEn = input.isEnglish
let query = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 4)

let blockInput = input.cfgBool("blockInput", default: true)
let keepAwake = input.cfgBool("keepAwake", default: true)
let muteAudio = input.cfgBool("muteAudio", default: false)
let holdSecs = input.cfgDouble("holdSeconds", default: 2.0, min: 1.0, max: 5.0)
let holdInt = Int(holdSecs)

let rawIcon = input.cfgString("customIcon", default: "🐱")
let customIcon = rawIcon.isEmpty ? "🐱" : rawIcon
let customTitle = input.cfgString("customTitle", default: isEn ? "Do Not Touch Keyboard" : "请勿触碰键盘")
let customSub = input.cfgString("customSubtitle", default: isEn ? "Background task in progress" : "后台任务执行中，稍后即回")

let args = input.arguments
let flag = args.first ?? ""

if flag == "--dismiss" {
    let resp = bridge.call(capability: "systemControl", action: "clearStatusScreen")
    if resp.ok {
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2,
            title: isEn ? "Status Screen Dismissed" : "已退出状态屏保护",
            badge: "IDLE",
            effect: PostActionEffect(
                toast: isEn ? "Status screen closed" : "状态屏已关闭",
                closeOverlay: true
            )
        ))
        exit(0)
    }
}

var targetPreset: String? = nil
var overrideTitle = ""
let qLower = query.lowercased()

if flag == "--preset", args.count >= 2 {
    targetPreset = args[1].lowercased()
} else if flag == "--custom" {
    targetPreset = "custom"
    overrideTitle = query.isEmpty ? customTitle : query
} else if ["clean", "清洁", "擦屏幕", "擦键盘"].contains(qLower) {
    targetPreset = "clean"
} else if ["busy", "勿碰", "请勿触碰", "跑任务"].contains(qLower) {
    targetPreset = "busy"
} else if ["brb", "马上回来", "暂离"].contains(qLower) {
    targetPreset = "brb"
} else if !query.isEmpty {
    targetPreset = "custom"
    overrideTitle = query
}

if let preset = targetPreset {
    var params: [String: Any] = [
        "active": true,
        "preset": preset,
        "blockInput": blockInput,
        "keepAwake": keepAwake,
        "muteAudio": muteAudio,
        "holdSeconds": holdSecs,
        "delaySeconds": 0.14
    ]
    if preset == "custom" {
        params["icon"] = customIcon
        params["title"] = overrideTitle.isEmpty ? customTitle : overrideTitle
        params["subtitle"] = customSub
    }
    let resp = bridge.call(capability: "systemControl", action: "setStatusScreen", params: params)
    if !resp.ok {
        let fallbackMsg = isEn
            ? "Open Screen Shield settings to enable Host Bridge"
            : "授权 systemControl 后即可一键启动全屏防误触状态屏"
        PluginOutput.emit(ViewPayload(
            schemaVersion: 2,
            title: isEn ? "Grant 'systemControl' Permission First" : "请先在插件设置页授权「系统控制与状态屏」",
            subtitle: (resp.message?.isEmpty == false) ? resp.message! : fallbackMsg,
            badge: "GRANT",
            items: [
                ViewItem(
                    id: "open-shield-settings",
                    title: isEn ? "Open Screen Shield Settings →" : "打开状态屏插件设置并授权 systemControl →",
                    subtitle: "lumakey://settings/plugin/screen-shield",
                    icon: "lock.shield.fill",
                    badge: "SETTINGS",
                    openURL: "lumakey://settings/plugin/screen-shield"
                )
            ]
        ))
        exit(0)
    }
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Activating Status Screen…" : "正在开启全屏状态屏…",
        subtitle: isEn ? "Hold Esc for \(holdInt)s to exit" : "按住 Esc \(holdInt) 秒即可安全退出",
        badge: "ACTIVE",
        effect: PostActionEffect(
            closeOverlay: true,
            statusSummary: "Shield ready (Esc \(holdInt)s)",
            statusBadge: "READY"
        )
    ))
    exit(0)
}

let st = bridge.call(capability: "systemControl", action: "status")
let axOK = st.ok ? st.bool("accessibilityTrusted", default: true) : true

let summary = isEn
    ? "Hold Esc \(holdInt)s · Input Block \(blockInput ? "ON" : "OFF")"
    : "长按 Esc \(holdInt) 秒退出 · 键鼠拦截\(blockInput ? "开启" : "关闭")"
PluginOutput.writeRuntimeStatus(summary: summary, badge: "READY", to: dataDir)

var items: [ViewItem] = []
if !st.ok {
    items.append(ViewItem(
        id: "grant-row",
        title: isEn ? "Grant 'systemControl' Bridge Permission First →" : "首次使用请点此授权「系统控制与状态屏 (systemControl)」→",
        subtitle: isEn ? "Required to display fullscreen status overlay & intercept touches" : "开启后即可一键盖住所有屏幕并拦截键盘误触",
        icon: "lock.open.display",
        badge: "SETUP",
        openURL: "lumakey://settings/plugin/screen-shield"
    ))
}

items.append(contentsOf: [
    ViewItem(
        id: "p-clean",
        title: isEn ? "🧹 Cleaning Screen & Keyboard" : "🧹 清洁屏幕与键盘（防擦拭/宠物误触）",
        subtitle: isEn ? "Covers all displays & blocks accidental key/scroll events" : "盖住所有屏幕并临时拦下按键与滚轮，放心擦键盘",
        icon: "sparkles",
        badge: "CLEAN",
        commandArgs: ["--preset", "clean"]
    ),
    ViewItem(
        id: "p-busy",
        title: isEn ? "⚡ Task Running · Do Not Touch" : "⚡ 任务运行中 · 请勿触碰（跑编译/下载/备份）",
        subtitle: isEn ? "Keeps Mac awake while displaying a clear do-not-touch banner" : "联动开启防休眠常亮并展示勿碰告示，防止他人误操作",
        icon: "bolt.shield.fill",
        badge: "BUSY",
        commandArgs: ["--preset", "busy"]
    ),
    ViewItem(
        id: "p-brb",
        title: isEn ? "☕ Be Right Back" : "☕ 马上回来（暂时离开座位）",
        subtitle: isEn ? "Polite fullscreen away notice across all monitors" : "离开座位倒水或取快递时一键盖上暂离告示",
        icon: "cup.and.saucer.fill",
        badge: "BRB",
        commandArgs: ["--preset", "brb"]
    ),
    ViewItem(
        id: "p-custom",
        title: "\(customIcon) Custom: \(customTitle)",
        subtitle: isEn
            ? "\(customSub) · Or type any message in search bar and press Return"
            : "\(customSub) · 也可直接在搜索框输入临时告示语回车开启",
        icon: "text.bubble.fill",
        badge: "CUSTOM",
        commandArgs: ["--custom"]
    )
])

let axNote = axOK ? "" : (isEn ? " · Grant Accessibility for global key block" : " · 建议授予辅助功能以拦截全局按键")
PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: isEn ? "Screen Shield · Status Screen" : "状态屏 · 清洁屏幕与暂离防误触",
    subtitle: summary + axNote,
    badge: "SHIELD",
    metrics: [
        KeyValue(key: isEn ? "Exit Key" : "退出方式", value: "Hold Esc \(holdInt)s"),
        KeyValue(key: isEn ? "Key Block" : "键鼠拦截", value: blockInput ? "ON" : "OFF"),
        KeyValue(key: isEn ? "Keep Awake" : "防休眠联动", value: keepAwake ? "ON" : "OFF")
    ],
    items: items
))
