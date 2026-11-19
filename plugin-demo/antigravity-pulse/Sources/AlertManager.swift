import Foundation
import PluginKit

private struct AlertDebounceRecord: Codable {
    var lastStep: Int
    var lastTriggeredAt: TimeInterval
}

private struct PulseAlertStore: Codable {
    var triggers: [String: AlertDebounceRecord]
    var lastActivityStates: [String: String]
}

private func alertStateURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("alert-state.json")
}

private func loadAlertStore(dataDir: String) -> PulseAlertStore {
    guard let url = alertStateURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(PulseAlertStore.self, from: data) else {
        return PulseAlertStore(triggers: [:], lastActivityStates: [:])
    }
    return decoded
}

private func saveAlertStore(dataDir: String, store: PulseAlertStore) {
    guard let url = alertStateURL(dataDir: dataDir),
          let data = try? JSONEncoder().encode(store) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

func evaluatePulseAlerts(
    outcome: ScanOutcome,
    cacheAlertsEnabled: Bool,
    sessionDoneAlertEnabled: Bool,
    input: PluginInput,
    isEn: Bool
) -> PulseAlertBanner? {
    let now = Date().timeIntervalSince1970
    let bridge = HostBridgeClient(input: input)
    var store = loadAlertStore(dataDir: input.dataDir)
    var dirty = false

    func shouldNotify(key: String, step: Int, enabled: Bool, updatedAt: TimeInterval) -> Bool {
        guard enabled, (now - updatedAt) <= PulseConstants.freshNotificationGraceSeconds else { return false }
        if let rec = store.triggers[key] {
            if rec.lastStep == step { return false }
            if (now - rec.lastTriggeredAt) < PulseConstants.alertCooldownSeconds { return false }
        }
        store.triggers[key] = AlertDebounceRecord(lastStep: step, lastTriggeredAt: now)
        dirty = true
        return true
    }

    // Detect any recent session transitioning from `running` -> `done`
    var newlyCompleted: SessionListItem? = nil
    for sess in outcome.recentSessions {
        let prev = store.lastActivityStates[sess.sessionId]
        if prev == SessionActivityState.running.rawValue && sess.isCompleted,
           (now - sess.updatedAt) <= PulseConstants.freshNotificationGraceSeconds,
           newlyCompleted == nil {
            newlyCompleted = sess
        }
        if prev != sess.activityState {
            store.lastActivityStates[sess.sessionId] = sess.activityState
            dirty = true
        }
    }

    defer {
        if dirty { saveAlertStore(dataDir: input.dataDir, store: store) }
    }

    if let finished = newlyCompleted {
        let title = isEn ? "Conversation Ready" : "会话已完成 · 可回来继续"
        let detail = isEn
            ? "\(finished.title) (\(finished.modelShortName))"
            : "\(finished.title)（\(finished.modelShortName)）"
        var sent = false
        if shouldNotify(key: "done:\(finished.sessionId)", step: finished.turnCount, enabled: sessionDoneAlertEnabled, updatedAt: finished.updatedAt) {
            let resp = bridge.call(capability: "notifications", action: "send", params: [
                "title": title, "subtitle": finished.modelShortName, "body": finished.title, "sound": true
            ])
            sent = resp.ok
        }
        return PulseAlertBanner(
            kind: "session_done", sessionId: finished.sessionId, source: finished.source,
            resumeURL: finished.resumeURL, resumeCommand: finished.resumeCommand,
            title: title, detail: detail, notificationSent: sent
        )
    }

    guard let session = outcome.activeSession else { return nil }

    if session.cacheDropped {
        let prevText = session.cacheDropPrevRate.map(formatPercent) ?? "--"
        let currText = formatPercent(session.latestCacheHitRate)
        let title = isEn ? "Prompt Cache Dropped" : "检测到缓存命中骤降"
        let detail = isEn
            ? "\(session.modelShortName) \(prevText) → \(currText) (#\(session.latestStep))"
            : "\(session.modelShortName) 缓存 \(prevText) → \(currText)（Step #\(session.latestStep)）"
        var sent = false
        if shouldNotify(key: "cache:\(session.sessionId)", step: session.latestStep, enabled: cacheAlertsEnabled, updatedAt: session.updatedAt) {
            let resp = bridge.call(capability: "notifications", action: "send", params: [
                "title": title, "subtitle": session.title, "body": detail, "sound": true
            ])
            sent = resp.ok
        }
        return PulseAlertBanner(
            kind: "cache_drop", sessionId: session.sessionId, source: session.source,
            resumeURL: session.resumeURL, resumeCommand: session.resumeCommand,
            title: title, detail: detail, notificationSent: sent
        )
    }

    if session.contextRatio >= PulseConstants.highContextCriticalRatio {
        let pct = formatPercent(session.contextRatio)
        let title = isEn ? "High Context (\(pct))" : "上下文占用较高（\(pct)）"
        let detail = isEn
            ? "\(formatCompactTokens(session.contextTokens)) / \(formatCompactTokens(session.contextLimit)) · Consider /compact"
            : "已用 \(formatCompactTokens(session.contextTokens)) / \(formatCompactTokens(session.contextLimit))，建议适时 /compact"
        var sent = false
        if shouldNotify(key: "ctx:\(session.sessionId)", step: session.latestStep, enabled: cacheAlertsEnabled, updatedAt: session.updatedAt) {
            let resp = bridge.call(capability: "notifications", action: "send", params: [
                "title": title, "subtitle": session.title, "body": detail, "sound": true
            ])
            sent = resp.ok
        }
        return PulseAlertBanner(
            kind: "high_context", sessionId: session.sessionId, source: session.source,
            resumeURL: session.resumeURL, resumeCommand: session.resumeCommand,
            title: title, detail: detail, notificationSent: sent
        )
    }

    return nil
}
