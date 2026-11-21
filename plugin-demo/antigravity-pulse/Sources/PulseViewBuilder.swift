import Foundation
import PluginKit

enum HUDMode: String {
    case dock
    case standard

    static func parse(_ raw: String) -> HUDMode {
        return raw == "standard" ? .standard : .dock
    }

    func size(edge: String = "right") -> (w: Double, h: Double) {
        switch self {
        case .standard: return (376, 356)
        case .dock: return dockTargetSize(for: edge)
        }
    }
}

private func dockStateFileURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("dock-state.json")
}

func saveDockState(dataDir: String, state: DockLaunchState) {
    guard let url = dockStateFileURL(dataDir: dataDir),
          let data = try? JSONEncoder().encode(state) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

func readDockState(dataDir: String, consumeSnap: Bool) -> DockLaunchState? {
    guard let url = dockStateFileURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          var state = try? JSONDecoder().decode(DockLaunchState.self, from: data) else { return nil }
    let result = state
    if consumeSnap && state.pendingSnap {
        state.pendingSnap = false
        saveDockState(dataDir: dataDir, state: state)
    }
    return result
}

func openFloatingHUD(mode: HUDMode, input: PluginInput, isEn: Bool) -> BridgeResponse {
    let existing = readDockState(dataDir: input.dataDir, consumeSnap: false)
    let edge = existing?.edge ?? "right"
    saveDockState(
        dataDir: input.dataDir,
        state: DockLaunchState(edge: edge, fromMode: mode.rawValue, pendingSnap: true)
    )

    let target = mode.size(edge: edge)
    let frames = loadAllWindowFrames(dataDir: input.dataDir)
    for key in [PulseConstants.windowID, "main"] {
        if let f = frames[key] {
            if mode == .dock {
                let origin = computeSnapOrigin(edge: edge, sourceFrame: f, targetW: target.w, targetH: target.h)
                updateSavedWindowFrame(dataDir: input.dataDir, windowId: key, x: origin.x, y: origin.y, width: target.w, height: target.h)
            } else {
                let s = screenContaining(x: f.x, y: f.y, width: target.w, height: target.h)
                let clampedX = max(s.visibleMinX + 8, min(f.x, s.visibleMaxX - target.w - 8))
                let clampedY = max(s.visibleMinY + 8, min(f.y, s.visibleMaxY - target.h - 8))
                if abs(clampedX - f.x) > 1 || abs(clampedY - f.y) > 1 || f.pinOnTop != true {
                    updateSavedWindowFrame(dataDir: input.dataDir, windowId: key, x: clampedX, y: clampedY, width: target.w, height: target.h)
                }
            }
        }
    }

    let params: [String: Any] = [
        "htmlPath": "ui/widget.html",
        "windowID": PulseConstants.windowID,
        "title": isEn ? "Antigravity Pulse" : "Antigravity Pulse · 上下文与会话监控",
        "width": Int(target.w),
        "height": Int(target.h),
        "minWidth": 140,
        "minHeight": 56,
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

func buildLauncherCardPayload(
    outcome: ScanOutcome,
    isEn: Bool,
    openedMode: HUDMode?,
    bridgeResult: BridgeResponse?,
    customToast: String? = nil
) -> ViewPayload {
    var metrics: [KeyValue] = []
    if let active = outcome.activeSession {
        metrics.append(KeyValue(
            key: isEn ? "Context" : "当前上下文",
            value: "\(formatCompactTokens(active.contextTokens)) (\(formatPercent(active.contextRatio)))"
        ))
        metrics.append(KeyValue(
            key: isEn ? "Cache Hit" : "缓存命中",
            value: "\(formatPercent(active.cumulativeCacheHitRate)) · \(isEn ? "Saved" : "省") \(formatUSD(active.estimatedSavedUSD))"
        ))
    }
    metrics.append(KeyValue(
        key: isEn ? "Sessions" : "近期会话",
        value: isEn
            ? "\(outcome.runningCount) running · \(outcome.completedCount) done"
            : "\(outcome.runningCount) 运行中 · \(outcome.completedCount) 已完成"
    ))
    metrics.append(KeyValue(
        key: isEn ? "5h Net / Total" : "5h 净用量",
        value: "\(formatCompactTokens(outcome.window5h.netTokens)) (\(isEn ? "incl. cache" : "含缓存") \(formatCompactTokens(outcome.window5h.totalTokens)))"
    ))

    var items: [ViewItem] = []

    if let br = bridgeResult {
        if br.ok {
            let modeLabel: String = (openedMode == .standard)
                ? (isEn ? "Full Floating Pulse HUD Opened" : "常驻大悬浮窗已开启")
                : (isEn ? "Edge-Retractable Pulse HUD Opened" : "缩边悬浮窗已开启（悬停自动展开大窗）")
            let altFlag = (openedMode == .standard) ? "--open-dock" : "--open-standard"
            let altLabel = (openedMode == .standard)
                ? (isEn ? "Edge Dock" : "缩边停靠")
                : (isEn ? "Always Full" : "常驻大窗")
            items.append(ViewItem(
                id: "hud-status", title: modeLabel,
                subtitle: isEn
                    ? "Hover edge tab to expand full HUD · Scroll wheel to switch active projects"
                    : "鼠标放上自动展开大悬浮窗 · 滚轮切换相邻活跃项目 · 点击直达对应对话",
                icon: "checkmark.circle.fill", badge: "HUD ON", commandArgs: [altFlag],
                actions: [ViewAction(id: "switch-alt", label: altLabel, commandArgs: [altFlag])]
            ))
        } else {
            let detail = br.message ?? br.error ?? (isEn ? "Permission required" : "需要授权")
            items.append(ViewItem(
                id: "hud-auth-needed",
                title: isEn ? "Grant Floating Window Permission in Plugin Settings" : "请在 Lucent 插件中心开启「悬浮窗」权限",
                subtitle: "\(detail) · \(isEn ? "Enable floatingWindow & filesystem scopes" : "授权 floatingWindow 与 filesystem 即可零侵入弹出悬浮窗")",
                icon: "lock.shield", badge: "AUTH", commandArgs: ["--open-floating"]
            ))
        }
    } else {
        items.append(ViewItem(
            id: "open-dock",
            title: isEn ? "Open Edge-Retractable Pulse HUD →" : "打开缩边悬浮窗（悬停自动展开大窗）→",
            subtitle: isEn
                ? "Hugs screen edge unobtrusively · Hover expands full HUD · Scroll wheel switches projects"
                : "默认贴边不挡视野，鼠标放上自动展开完整大悬浮窗，滚轮切换活跃项目",
            icon: "sidebar.right", badge: "DOCK", commandArgs: ["--open-dock"],
            actions: [
                ViewAction(id: "act-full", label: isEn ? "Always Full" : "常驻大窗", commandArgs: ["--open-standard"])
            ]
        ))
        items.append(ViewItem(
            id: "open-standard",
            title: isEn ? "Open Always-Expanded Large HUD →" : "打开常驻大悬浮窗 →",
            subtitle: isEn
                ? "Keep full context, cache, net usage & recent sessions visible · Drag to edge to retract"
                : "保持大悬浮窗常驻展示，拖到屏幕左/右/顶边缘随时自动缩边",
            icon: "macwindow.on.rectangle", badge: "FULL", commandArgs: ["--open-standard"]
        ))
    }

    for sess in outcome.recentSessions.prefix(6) {
        let srcTag = sess.source == "cli" ? "CLI" : "APP"
        let iconName = sess.activityState == "running" ? "waveform.path.ecg" : (sess.isCompleted ? "checkmark.circle.fill" : "pause.circle")
        let tint = sess.activityState == "running" ? "blue" : (sess.isCompleted ? "green" : (sess.activityState == "error" ? "red" : "slate"))
        let badgeText = "\(sess.activityLabel) · \(srcTag)"
        let copyText = sess.source == "cli" ? sess.resumeCommand : sess.title
        let displayTitle = sess.projectName.isEmpty ? sess.title : "[\(sess.projectName)] \(sess.title)"
        let jumpArgs: [String]? = sess.source == "desktop" ? ["--focus-session-card", sess.sessionId, sess.title] : nil
        items.append(ViewItem(
            id: "session-\(sess.sessionId)",
            title: displayTitle,
            subtitle: isEn
                ? "\(sess.modelShortName) · \(formatCompactTokens(sess.contextTokens)) (\(formatPercent(sess.contextRatio))) · Cache \(formatPercent(sess.cumulativeCacheHitRate)) · \(sess.updatedLabel)"
                : "\(sess.modelShortName) · 上下文 \(formatCompactTokens(sess.contextTokens)) (\(formatPercent(sess.contextRatio))) · 缓存 \(formatPercent(sess.cumulativeCacheHitRate)) · \(sess.updatedLabel)",
            icon: iconName, tintColor: tint, badge: badgeText, copyText: copyText,
            openURL: sess.source == "desktop" ? nil : sess.resumeURL,
            commandArgs: jumpArgs,
            actions: [
                ViewAction(id: "hud-\(sess.sessionId)", label: isEn ? "HUD" : "悬浮窗", commandArgs: ["--open-dock"])
            ]
        ))
    }

    if !outcome.window7d.topModels.isEmpty {
        let modelSummary = outcome.window7d.topModels.prefix(3).map { "\($0.shortName) \(formatCompactTokens($0.totalTokens))" }.joined(separator: " · ")
        items.append(ViewItem(
            id: "window-summary",
            title: isEn
                ? "7-Day Breakdown · \(formatCompactTokens(outcome.window7d.totalTokens)) (\(formatPercent(outcome.window7d.cacheHitRate)) cached)"
                : "7 天模型分布 · 共 \(formatCompactTokens(outcome.window7d.totalTokens))（缓存 \(formatPercent(outcome.window7d.cacheHitRate))）",
            subtitle: modelSummary, icon: "chart.bar.xaxis", badge: formatUSD(outcome.window7d.estimatedCostUSD),
            copyText: "Antigravity 7d: \(formatCompactTokens(outcome.window7d.totalTokens)) tokens · \(modelSummary)"
        ))
    }

    let headerTitle: String
    let headerSubtitle: String
    let headerBadge: String
    if let active = outcome.activeSession {
        headerTitle = "Antigravity Pulse · \(formatCompactTokens(active.contextTokens)) (\(active.activityLabel))"
        headerSubtitle = isEn
            ? "\(active.modelName) · Cache \(formatPercent(active.cumulativeCacheHitRate)) · \(outcome.runningCount) running / \(outcome.completedCount) done"
            : "\(active.modelName) · 缓存 \(formatPercent(active.cumulativeCacheHitRate)) · \(outcome.runningCount) 运行中 / \(outcome.completedCount) 已完成"
        headerBadge = active.cacheDropped ? "CACHE DROP" : active.activityLabel
    } else {
        headerTitle = "Antigravity Pulse"
        headerSubtitle = isEn ? "Zero-invasion local transcript context & session monitor" : "零侵入本地日志上下文与会话完成状态监控"
        headerBadge = "READY"
    }

    let toast = customToast ?? ((bridgeResult?.ok == true)
        ? (isEn ? "Antigravity Pulse HUD opened" : "Antigravity Pulse 悬浮窗已开启")
        : nil)

    return ViewPayload(
        schemaVersion: 2, title: headerTitle, subtitle: headerSubtitle, badge: headerBadge,
        metrics: metrics, items: items, effect: toast.map { PostActionEffect(toast: $0) }
    )
}
