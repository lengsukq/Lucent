import Foundation

struct ModelProfile {
    let displayName: String
    let shortName: String
    let defaultContextLimit: Int
    let inputUSDPerMillion: Double
    let cacheReadUSDPerMillion: Double
    let outputUSDPerMillion: Double
}

struct TurnCostEstimate {
    let actualUSD: Double
    let savedUSD: Double
}

func resolveModelProfile(rawModel: String) -> ModelProfile {
    let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    if lower.isEmpty {
        return ModelProfile(
            displayName: "Antigravity Legacy", shortName: "Legacy", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.2, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("orchestrator") {
        let tag = lower.contains("neon") ? " Neon" : (lower.contains("argon") ? " Argon" : "")
        return ModelProfile(
            displayName: "Gemini Orchestrator\(tag)", shortName: "Orchestrator\(tag)", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 2.5, cacheReadUSDPerMillion: 0.25, outputUSDPerMillion: 15.0
        )
    }
    if lower.contains("neon") {
        let suffix = lower.contains("xhigh") ? " XHigh" : (lower.contains("high") ? " High" : "")
        return ModelProfile(
            displayName: "Gemini 4 Neon\(suffix)", shortName: "Neon\(suffix)", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 2.5, cacheReadUSDPerMillion: 0.25, outputUSDPerMillion: 15.0
        )
    }
    if lower.contains("carbon") {
        let suffix = lower.contains("xhigh") ? " XHigh" : (lower.contains("high") ? " High" : "")
        return ModelProfile(
            displayName: "Gemini 4 Carbon\(suffix)", shortName: "Carbon\(suffix)", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 3.0, cacheReadUSDPerMillion: 0.30, outputUSDPerMillion: 18.0
        )
    }
    if lower.contains("argon") {
        let suffix = lower.contains("high") ? " High" : ""
        return ModelProfile(
            displayName: "Gemini 4 Argon\(suffix)", shortName: "Argon\(suffix)", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.20, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("hydrogen") {
        let suffix = lower.contains("xhigh") ? " XHigh" : (lower.contains("high") ? " High" : "")
        return ModelProfile(
            displayName: "Gemini 4 Hydrogen\(suffix)", shortName: "Hydrogen\(suffix)", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 1.25, cacheReadUSDPerMillion: 0.125, outputUSDPerMillion: 10.0
        )
    }
    if lower.contains("flash") {
        return ModelProfile(
            displayName: "Gemini Flash", shortName: "Flash", defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 0.30, cacheReadUSDPerMillion: 0.03, outputUSDPerMillion: 2.50
        )
    }
    if lower.contains("gemini") {
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: compactModelId(trimmed), defaultContextLimit: 1_000_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.20, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("opus") {
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: "Claude Opus", defaultContextLimit: 200_000,
            inputUSDPerMillion: 15.0, cacheReadUSDPerMillion: 1.50, outputUSDPerMillion: 75.0
        )
    }
    if lower.contains("sonnet") || lower.contains("claude") {
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: "Claude Sonnet", defaultContextLimit: 200_000,
            inputUSDPerMillion: 3.0, cacheReadUSDPerMillion: 0.30, outputUSDPerMillion: 15.0
        )
    }
    return ModelProfile(
        displayName: humanizeRawModelId(trimmed), shortName: compactModelId(trimmed), defaultContextLimit: 200_000,
        inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.20, outputUSDPerMillion: 10.0
    )
}

private func humanizeRawModelId(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(of: "MODEL_", with: "").replacingOccurrences(of: "_", with: "-")
    return cleaned.split(separator: "-").map { part -> String in
        let s = String(part)
        if s.lowercased() == "xhigh" { return "XHigh" }
        if s.lowercased() == "gpt" { return "GPT" }
        if s.lowercased() == "agy" { return "AGY" }
        return s.prefix(1).uppercased() + s.dropFirst()
    }.joined(separator: " ")
}

private func compactModelId(_ raw: String) -> String {
    let pretty = humanizeRawModelId(raw)
    return pretty.count <= 18 ? pretty : String(pretty.prefix(17)) + "…"
}

func resolveContextLimit(profile: ModelProfile, configOverrideK: String) -> Int {
    let trimmed = configOverrideK.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let kVal = Int(trimmed), kVal >= 32, kVal <= 4096 { return kVal * 1_000 }
    return profile.defaultContextLimit
}

func estimateTurnCost(inputTokens: Int, cacheReadTokens: Int, outputTokens: Int, profile: ModelProfile) -> TurnCostEstimate {
    let million = 1_000_000.0
    let inpCost = Double(inputTokens) / million * profile.inputUSDPerMillion
    let cacheCost = Double(cacheReadTokens) / million * profile.cacheReadUSDPerMillion
    let outCost = Double(outputTokens) / million * profile.outputUSDPerMillion
    let saved = Double(cacheReadTokens) / million * max(0.0, profile.inputUSDPerMillion - profile.cacheReadUSDPerMillion)
    return TurnCostEstimate(actualUSD: inpCost + cacheCost + outCost, savedUSD: saved)
}

func formatCompactTokens(_ count: Int) -> String {
    let absVal = Double(abs(count))
    let sign = count < 0 ? "-" : ""
    if absVal >= 1_000_000_000 { return String(format: "%@%.2fB", sign, absVal / 1_000_000_000.0) }
    if absVal >= 1_000_000 { return String(format: "%@%.2fM", sign, absVal / 1_000_000.0) }
    if absVal >= 100_000 { return String(format: "%@%.0fK", sign, absVal / 1_000.0) }
    if absVal >= 1_000 { return String(format: "%@%.1fK", sign, absVal / 1_000.0) }
    return "\(count)"
}

func formatPercent(_ ratio: Double) -> String {
    let pct = max(0.0, min(1.0, ratio)) * 100.0
    if pct == 0 { return "0%" }
    if pct < 0.1 { return "<0.1%" }
    return String(format: "%.1f%%", pct)
}

func formatUSD(_ amount: Double) -> String {
    amount < 0.005 ? "$0.00" : String(format: "$%.2f", amount)
}

func formatTokensPerSec(_ tps: Double?) -> String {
    guard let tps, tps.isFinite, tps > 0 else { return "--" }
    return tps >= 100 ? String(format: "%.0f tok/s", tps) : String(format: "%.1f tok/s", tps)
}

func formatShortClock(_ epoch: TimeInterval) -> String {
    let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: Date(timeIntervalSince1970: epoch))
    return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
}

func formatRelativeUpdated(_ epoch: TimeInterval, now: TimeInterval, isEn: Bool) -> String {
    let delta = max(0, Int(now - epoch))
    if delta < 15 { return isEn ? "Just now" : "刚刚" }
    if delta < 60 { return isEn ? "\(delta)s ago" : "\(delta)秒前" }
    let mins = delta / 60
    if mins < 60 { return isEn ? "\(mins)m ago" : "\(mins)分钟前" }
    let hours = mins / 60
    if hours < 24 { return isEn ? "\(hours)h ago" : "\(hours)小时前" }
    let days = hours / 24
    return isEn ? "\(days)d ago" : "\(days)天前"
}
