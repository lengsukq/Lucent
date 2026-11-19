import Foundation
import PluginKit

func fmtPrice(_ v: Double) -> String { String(format: "%.2f", v) }

func fmtSigned(_ v: Double, suffix: String = "") -> String {
    String(format: "%@%.2f%@", v > 0 ? "+" : "", v, suffix)
}

func dockStateFile(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("dock_state.json")
}

func saveDockState(dataDir: String, state: DockLaunchState) {
    guard let url = dockStateFile(dataDir: dataDir),
          let data = try? JSONEncoder().encode(state) else { return }
    try? data.write(to: url, options: .atomic)
}

func readDockState(dataDir: String, consumeSnap: Bool) -> DockLaunchState? {
    guard let url = dockStateFile(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          var state = try? JSONDecoder().decode(DockLaunchState.self, from: data) else { return nil }
    let result = state
    if consumeSnap && state.pendingSnap {
        state.pendingSnap = false
        saveDockState(dataDir: dataDir, state: state)
    }
    return result
}

func openFloatingWindow(style: WindowStyle, input: PluginInput, isEn: Bool) -> BridgeResponse {
    let existing = readDockState(dataDir: input.dataDir, consumeSnap: false)
    saveDockState(
        dataDir: input.dataDir,
        state: DockLaunchState(edge: existing?.edge ?? "right", anchorX: nil, anchorY: nil, fromMode: style.rawValue, pendingSnap: true)
    )

    let targetW: Double = style == .dock ? 212 : (style == .mini ? 280 : 352)
    let targetH: Double = style == .dock ? 96 : (style == .mini ? 112 : 240)

    let check = checkWindowEdgeState(dataDir: input.dataDir, windowId: "gold-monitor-hud", mode: style.rawValue)
    if check.ok && check.outOfBounds, let sx = check.snapX, let sy = check.snapY {
        updateSavedWindowFrame(dataDir: input.dataDir, windowId: "gold-monitor-hud", x: sx, y: sy, width: targetW, height: targetH, opacity: 1.0)
    }

    let params: [String: Any] = [
        "htmlPath": "ui/widget.html",
        "windowID": "gold-monitor-hud",
        "title": isEn ? "Gold Monitor · Au99.99" : "黄金大盘 · Au99.99",
        "width": Int(targetW),
        "height": Int(targetH),
        "minWidth": 212,
        "minHeight": 96,
        "resizable": false,
        "chrome": "frameless",
        "transparent": true,
        "pinOnTop": true,
        "clickThrough": false,
        "showInDock": false,
        "opacity": 1.0
    ]
    return HostBridgeClient(input: input).call(capability: "floatingWindow", action: "open", params: params)
}

func buildQuoteViewPayload(
    quotes: [GoldSymbol: GoldQuote],
    primarySymbol: GoldSymbol,
    isEn: Bool,
    openedStyle: WindowStyle?,
    bridgeResult: BridgeResponse?,
    toast: String?
) -> ViewPayload {
    let primary = quotes[primarySymbol] ?? quotes[.au9999] ?? quotes[.autd]
    let secondarySymbol: GoldSymbol = (primarySymbol == .au9999) ? .autd : .au9999
    let secondary = quotes[secondarySymbol]

    var metrics: [KeyValue] = []
    if let q = primary {
        metrics.append(KeyValue(key: isEn ? q.symbol : q.name, value: "¥\(fmtPrice(q.price))/g"))
        metrics.append(KeyValue(key: isEn ? "Change" : "涨跌幅", value: "\(fmtSigned(q.change)) (\(fmtSigned(q.changePct, suffix: "%")))"))
        metrics.append(KeyValue(key: isEn ? "High / Low" : "最高 / 最低", value: "\(fmtPrice(q.high)) / \(fmtPrice(q.low))"))
    }

    var items: [ViewItem] = []

    if let br = bridgeResult {
        if br.ok {
            let isMini = (openedStyle == .mini)
            items.append(ViewItem(
                id: "hud-opened",
                title: isEn
                    ? (isMini ? "Mini Gold Ticker Opened (Always on Top)" : "Floating Gold HUD Opened (Always on Top)")
                    : (isMini ? "Mini 极简金价悬浮条已开启" : "桌面置顶黄金悬浮窗已开启"),
                subtitle: isEn
                    ? "Switch anytime between Standard Chart & Mini Pill directly from the HUD"
                    : "可在悬浮窗右上角一键切换「标准分时图」与「Mini 极简条」形态",
                icon: isMini ? "rectangle.compress.vertical" : "macwindow.on.rectangle",
                badge: isMini ? "MINI ON" : "HUD ON",
                commandArgs: [isMini ? "--open-floating" : "--open-mini"],
                actions: [
                    ViewAction(
                        id: "switch-other",
                        label: isEn ? (isMini ? "Open Standard" : "Open Mini") : (isMini ? "打开标准窗" : "打开 Mini 条"),
                        commandArgs: [isMini ? "--open-floating" : "--open-mini"]
                    )
                ]
            ))
        } else {
            let errText = br.message ?? br.error ?? (isEn ? "Permission required" : "需要授权")
            items.append(ViewItem(
                id: "hud-auth-needed",
                title: isEn ? "Enable Floating Window Permission in Plugin Settings" : "请在插件中心授权「桌面置顶悬浮窗」权限",
                subtitle: "\(errText) · \(isEn ? "Grant floatingWindow & network in Lucent Settings" : "开启 floatingWindow 权限后即可弹出桌面置顶悬浮窗")",
                icon: "lock.shield",
                badge: "AUTH",
                commandArgs: ["--open-floating"]
            ))
        }
    } else {
        items.append(ViewItem(
            id: "open-hud-action",
            title: isEn ? "Open Standard Floating Gold HUD →" : "打开标准图表悬浮窗 →",
            subtitle: isEn ? "Frameless Liquid Glass HUD with live price & intraday sparkline" : "透明毛玻璃置顶挂件，实时展示金价、涨跌幅与分时折线图",
            icon: "macwindow.on.rectangle",
            badge: "STANDARD",
            commandArgs: ["--open-floating"]
        ))
        items.append(ViewItem(
            id: "open-mini-action",
            title: isEn ? "Open Mini Gold Ticker Pill →" : "打开 Mini 极简金价悬浮条 →",
            subtitle: isEn ? "Ultra-compact single-row ticker pill with one-click expand" : "超紧凑单行桌面胶囊，不遮挡工作区并支持一键展开",
            icon: "rectangle.compress.vertical",
            badge: "MINI",
            commandArgs: ["--open-mini"]
        ))
    }

    for sym in [primarySymbol, secondarySymbol] {
        guard let q = quotes[sym] else { continue }
        let symTitle = isEn ? sym.englishName : q.name
        let trendIcon = q.change >= 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
        let copyStr = "\(symTitle): \(fmtPrice(q.price)) 元/克 (\(fmtSigned(q.changePct, suffix: "%"))) @ \(q.date) \(q.time)"
        items.append(ViewItem(
            id: "quote-\(sym.rawValue)",
            title: "\(symTitle)  ·  ¥\(fmtPrice(q.price))/g   \(fmtSigned(q.changePct, suffix: "%"))",
            subtitle: isEn
                ? "Open \(fmtPrice(q.open)) · Prev \(fmtPrice(q.preClose)) · High \(fmtPrice(q.high)) · Low \(fmtPrice(q.low)) · \(q.time)"
                : "今开 \(fmtPrice(q.open)) · 昨收 \(fmtPrice(q.preClose)) · 最高 \(fmtPrice(q.high)) · 最低 \(fmtPrice(q.low)) · \(q.time)",
            icon: trendIcon,
            badge: sym.rawValue,
            copyText: copyStr,
            actions: [
                ViewAction(id: "open-\(sym.rawValue)", label: isEn ? "Standard HUD" : "标准窗", commandArgs: ["--open-floating"]),
                ViewAction(id: "mini-\(sym.rawValue)", label: isEn ? "Mini Pill" : "Mini 条", commandArgs: ["--open-mini"])
            ]
        ))
    }

    if primary == nil && secondary == nil {
        items.append(ViewItem(
            id: "network-error",
            title: isEn ? "Unable to fetch live gold quotes" : "暂未获取到实时黄金行情",
            subtitle: isEn ? "Please check network permission (networkAccess) in Lucent Plugin Settings" : "请检查网络连接或确认插件已开启「允许访问网络」权限",
            icon: "wifi.exclamationmark",
            badge: "OFFLINE",
            commandArgs: ["--card"]
        ))
    }

    let headerTitle = primary.map { "\(isEn ? primarySymbol.englishName : $0.name)  ¥\(fmtPrice($0.price))/g" }
        ?? (isEn ? "Gold Monitor · Au99.99" : "黄金大盘悬浮窗 · Au99.99")
    let headerSubtitle = primary.map { "\(fmtSigned($0.change)) (\(fmtSigned($0.changePct, suffix: "%"))) · \($0.source) \($0.time)" }
        ?? (isEn ? "Domestic SGE spot gold real-time monitor" : "国内上海黄金交易所 Au99.99 / Au(T+D) 实时行情")
    let headerBadge = primary.map { fmtSigned($0.changePct, suffix: "%") } ?? "SGE"

    return ViewPayload(
        schemaVersion: 2, title: headerTitle, subtitle: headerSubtitle, badge: headerBadge,
        metrics: metrics.isEmpty ? nil : metrics, items: items,
        effect: toast.map { PostActionEffect(toast: $0) }
    )
}
