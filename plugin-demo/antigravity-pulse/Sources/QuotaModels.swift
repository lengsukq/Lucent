import Foundation

// MARK: - Official Antigravity CLI statusLine Quota Models & Pure Math Helpers

struct AgyQuotaBucket: Codable, Equatable {
    let remaining_fraction: Double?
    let remaining_amount: Double?
    let reset_time: String?
    let reset_in_seconds: Int64?
    let disabled: Bool?
}

struct AgyQuotaSnapshotFile: Codable {
    let observed_at: Int64
    let plan_tier: String?
    let model_id: String?
    let model_name: String?
    let quota: [String: AgyQuotaBucket]?
}

struct AutoQuotaSample: Codable {
    let planTier: String
    let family: String
    let windowKind: String
    let cycleKey: String
    let recordedAt: TimeInterval
    let usedPercent: Double
    let usedCostUSD: Double
    let inferredFullUSD: Double
}

struct QuotaLearningCache: Codable {
    var samples: [AutoQuotaSample]
}

struct StatusLineHookStatus: Codable {
    let installed: Bool
    let managedByPulse: Bool
    let managedByOther: String?
    let settingsPath: String
    let agyInstalled: Bool
}

struct OfficialQuotaWindowEstimate: Codable {
    let windowKind: String
    let label: String
    let family: String
    let familyLabel: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAtEpoch: TimeInterval?
    let resetLabel: String
    let expired: Bool
    let usedInQuotaUSD: Double
    let usedInQuotaSavedUSD: Double
    let usedInQuotaTotalTokens: Int
    let usedInQuotaNetTokens: Int
    let fullQuotaUSD: Double?
    let fullQuotaConfidence: String
    let sampleCount: Int
    let remainingValueUSD: Double?
}

struct OfficialQuotaGroupBrief: Codable {
    let family: String
    let familyLabel: String
    let remaining5hPct: Double?
    let remainingWeeklyPct: Double?
}

struct OfficialQuotaSummary: Codable {
    let available: Bool
    let exclusiveQuota: Bool
    let sourceLabel: String
    let planTier: String
    let observedAt: TimeInterval
    let observedLabel: String
    let activeFamily: String
    let activeFamilyLabel: String
    let window5h: OfficialQuotaWindowEstimate?
    let windowWeekly: OfficialQuotaWindowEstimate?
    let monthlyFullQuotaUSD: Double?
    let otherGroups: [OfficialQuotaGroupBrief]
    let hookStatus: StatusLineHookStatus
}

func classifyAgyQuotaBucket(key: String, bucket: AgyQuotaBucket) -> (family: String, kind: String) {
    let lk = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let family: String
    if lk.contains("gemini") {
        family = "gemini"
    } else if lk.hasPrefix("3p") || lk.contains("claude") || lk.contains("gpt") || lk.contains("partner") || lk.contains("third") {
        family = "claude_gpt"
    } else {
        family = "default"
    }

    let kind: String
    if lk.contains("week") || lk.contains("7d") || lk.contains("168h") {
        kind = "weekly"
    } else if lk.contains("5h") || lk.contains("five") || lk.contains("hour") || lk.contains("short") {
        kind = "5h"
    } else if let sec = bucket.reset_in_seconds, sec > 24 * 3600 {
        kind = "weekly"
    } else if let sec = bucket.reset_in_seconds, sec > 0, sec <= 12 * 3600 {
        kind = "5h"
    } else {
        kind = "other"
    }
    return (family, kind)
}

func quotaFamilyLabel(_ family: String, isEn: Bool) -> String {
    switch family {
    case "gemini": return isEn ? "Gemini Pool" : "Gemini 组"
    case "claude_gpt": return isEn ? "Claude / GPT Pool" : "Claude / GPT 组"
    default: return isEn ? "Active Pool" : "当前模型组"
    }
}

func formatResetCountdown(resetsAt: TimeInterval?, now: TimeInterval, isEn: Bool) -> String {
    guard let resetsAt, resetsAt > 0 else { return isEn ? "Rolling window" : "滚动周期" }
    let rem = Int(resetsAt - now)
    if rem <= 0 { return isEn ? "Window reset" : "本轮已重置" }
    let days = rem / 86_400
    let hours = (rem % 86_400) / 3600
    let mins = (rem % 3600) / 60
    if days > 0 { return isEn ? "Resets in \(days)d \(hours)h" : "\(days)天\(hours)小时后重置" }
    if hours > 0 { return isEn ? "Resets in \(hours)h \(mins)m" : "\(hours)h \(mins)m 后重置" }
    return isEn ? "Resets in \(max(1, mins))m" : "\(max(1, mins)) 分钟后重置"
}

func inferWeightedMedianFullQuota(
    samples: [AutoQuotaSample],
    planTier: String,
    family: String,
    windowKind: String,
    maxSamples: Int = 12
) -> (value: Double?, count: Int) {
    let normPlan = planTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matching = samples.filter { s in
        s.planTier.lowercased() == normPlan && s.family == family && s.windowKind == windowKind
            && s.inferredFullUSD.isFinite && s.inferredFullUSD > 0
    }.sorted { $0.recordedAt > $1.recordedAt }.prefix(maxSamples)

    guard !matching.isEmpty else { return (nil, 0) }
    var weighted: [(val: Double, w: Double)] = matching.map { s in
        let w = s.usedPercent >= 50.0 ? 2.0 : (s.usedPercent >= 20.0 ? 1.5 : 1.0)
        return (s.inferredFullUSD, w)
    }
    weighted.sort { $0.val < $1.val }
    let totalW = weighted.reduce(0.0) { $0 + $1.w }
    var acc = 0.0
    for item in weighted {
        acc += item.w
        if acc >= totalW * 0.5 { return (item.val, weighted.count) }
    }
    return (weighted.last?.val, weighted.count)
}
