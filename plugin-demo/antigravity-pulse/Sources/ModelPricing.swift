import Foundation

struct ModelProfile {
    let displayName: String
    let shortName: String
    let family: String // "gemini" | "claude_gpt"
    let defaultContextLimit: Int
    let inputUSDPerMillion: Double
    let cacheReadUSDPerMillion: Double
    let outputUSDPerMillion: Double
}

struct TurnCostEstimate {
    let actualUSD: Double
    let uncachedUSD: Double
    let savedUSD: Double
}

struct ModelPricingReference: Codable {
    let name: String
    let family: String
    let contextLimitK: Int
    let inputPerM: Double
    let cacheReadPerM: Double
    let outputPerM: Double
}

func allModelPricingReferences() -> [ModelPricingReference] {
    [
        ModelPricingReference(name: "Gemini 4 Carbon", family: "gemini", contextLimitK: 512, inputPerM: 3.00, cacheReadPerM: 0.30, outputPerM: 18.00),
        ModelPricingReference(name: "Gemini 4 Neon / Orchestrator", family: "gemini", contextLimitK: 512, inputPerM: 2.50, cacheReadPerM: 0.25, outputPerM: 15.00),
        ModelPricingReference(name: "Gemini 4 Argon / Legacy", family: "gemini", contextLimitK: 512, inputPerM: 2.00, cacheReadPerM: 0.20, outputPerM: 12.00),
        ModelPricingReference(name: "Gemini 4 Hydrogen", family: "gemini", contextLimitK: 512, inputPerM: 1.25, cacheReadPerM: 0.125, outputPerM: 10.00),
        ModelPricingReference(name: "Gemini Flash / Worker", family: "gemini", contextLimitK: 512, inputPerM: 0.30, cacheReadPerM: 0.03, outputPerM: 2.50),
        ModelPricingReference(name: "Claude Opus", family: "claude_gpt", contextLimitK: 200, inputPerM: 15.00, cacheReadPerM: 1.50, outputPerM: 75.00),
        ModelPricingReference(name: "Claude Sonnet", family: "claude_gpt", contextLimitK: 200, inputPerM: 3.00, cacheReadPerM: 0.30, outputPerM: 15.00),
        ModelPricingReference(name: "GPT-OSS 120B", family: "claude_gpt", contextLimitK: 80, inputPerM: 0.50, cacheReadPerM: 0.05, outputPerM: 2.00)
    ]
}

private func effortSuffix(from lower: String) -> String {
    if lower.contains("tiered") { return " Tiered" }
    if lower.contains("xhigh") { return " XHigh" }
    if lower.contains("high") { return " High" }
    if lower.contains("medium") { return " Medium" }
    if lower.contains("low") { return " Low" }
    return ""
}

func resolveModelProfile(rawModel: String) -> ModelProfile {
    let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    if lower.isEmpty {
        return ModelProfile(
            displayName: "Antigravity Legacy", shortName: "Legacy", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.2, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("orchestrator") {
        let tag = lower.contains("neon") ? " Neon" : (lower.contains("argon") ? " Argon" : "")
        return ModelProfile(
            displayName: "Gemini Orchestrator\(tag)", shortName: "Orchestrator\(tag)", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 2.5, cacheReadUSDPerMillion: 0.25, outputUSDPerMillion: 15.0
        )
    }
    if lower.contains("neon") {
        let suffix = effortSuffix(from: lower)
        return ModelProfile(
            displayName: "Gemini 4 Neon\(suffix)", shortName: "Neon\(suffix)", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 2.5, cacheReadUSDPerMillion: 0.25, outputUSDPerMillion: 15.0
        )
    }
    if lower.contains("carbon") {
        let suffix = effortSuffix(from: lower)
        return ModelProfile(
            displayName: "Gemini 4 Carbon\(suffix)", shortName: "Carbon\(suffix)", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 3.0, cacheReadUSDPerMillion: 0.30, outputUSDPerMillion: 18.0
        )
    }
    if lower.contains("argon") {
        let suffix = effortSuffix(from: lower)
        return ModelProfile(
            displayName: "Gemini 4 Argon\(suffix)", shortName: "Argon\(suffix)", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.20, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("hydrogen") {
        let suffix = effortSuffix(from: lower)
        return ModelProfile(
            displayName: "Gemini 4 Hydrogen\(suffix)", shortName: "Hydrogen\(suffix)", family: "gemini", defaultContextLimit: 512_000,
            inputUSDPerMillion: 1.25, cacheReadUSDPerMillion: 0.125, outputUSDPerMillion: 10.0
        )
    }
    if lower.contains("flash") {
        let isLegacy25 = lower.contains("2.5") || lower.contains("2-5")
        let tag = lower.contains("worker") ? " Worker" : ""
        return ModelProfile(
            displayName: "Gemini Flash\(tag)", shortName: "Flash\(tag)", family: "gemini",
            defaultContextLimit: isLegacy25 ? 128_000 : 512_000,
            inputUSDPerMillion: 0.30, cacheReadUSDPerMillion: 0.03, outputUSDPerMillion: 2.50
        )
    }
    if lower.contains("gemini") {
        let isLegacy25 = lower.contains("2.5") || lower.contains("2-5")
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: compactModelId(trimmed), family: "gemini",
            defaultContextLimit: isLegacy25 ? 128_000 : 512_000,
            inputUSDPerMillion: 2.0, cacheReadUSDPerMillion: 0.20, outputUSDPerMillion: 12.0
        )
    }
    if lower.contains("gpt-oss") || lower.contains("oss-120b") {
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: compactModelId(trimmed), family: "claude_gpt", defaultContextLimit: 80_000,
            inputUSDPerMillion: 0.5, cacheReadUSDPerMillion: 0.05, outputUSDPerMillion: 2.0
        )
    }
    if lower.contains("opus") {
        let limit = lower.contains("1m") ? 1_000_000 : 200_000
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: "Claude Opus", family: "claude_gpt", defaultContextLimit: limit,
            inputUSDPerMillion: 15.0, cacheReadUSDPerMillion: 1.50, outputUSDPerMillion: 75.0
        )
    }
    if lower.contains("sonnet") || lower.contains("claude") {
        let limit = lower.contains("1m") ? 1_000_000 : 200_000
        return ModelProfile(
            displayName: humanizeRawModelId(trimmed), shortName: "Claude Sonnet", family: "claude_gpt", defaultContextLimit: limit,
            inputUSDPerMillion: 3.0, cacheReadUSDPerMillion: 0.30, outputUSDPerMillion: 15.0
        )
    }
    let family = (lower.contains("gpt") || lower.contains("openai") || lower.contains("o3") || lower.contains("o4")) ? "claude_gpt" : "gemini"
    return ModelProfile(
        displayName: humanizeRawModelId(trimmed), shortName: compactModelId(trimmed), family: family, defaultContextLimit: 200_000,
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

func resolveContextLimit(profile: ModelProfile, configOverrideK: String, maxObservedContext: Int = 0) -> Int {
    let trimmed = configOverrideK.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let kVal = Int(trimmed), kVal >= 32, kVal <= 4096 { return kVal * 1_000 }
    if maxObservedContext > 600_000 && profile.defaultContextLimit < 1_000_000 { return 1_000_000 }
    if maxObservedContext > 260_000 && profile.defaultContextLimit < 512_000 { return 512_000 }
    return profile.defaultContextLimit
}

func estimateTurnCost(inputTokens: Int, cacheReadTokens: Int, outputTokens: Int, profile: ModelProfile) -> TurnCostEstimate {
    let million = 1_000_000.0
    let inpCost = Double(inputTokens) / million * profile.inputUSDPerMillion
    let cacheCost = Double(cacheReadTokens) / million * profile.cacheReadUSDPerMillion
    let outCost = Double(outputTokens) / million * profile.outputUSDPerMillion
    let uncached = Double(inputTokens + cacheReadTokens) / million * profile.inputUSDPerMillion + outCost
    let actual = inpCost + cacheCost + outCost
    let saved = max(0.0, uncached - actual)
    return TurnCostEstimate(actualUSD: actual, uncachedUSD: uncached, savedUSD: saved)
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

func formatCurrency(_ usd: Double, currency: String, rate: Double) -> String {
    if currency.uppercased() == "CNY" {
        let cny = usd * max(0.1, rate)
        return cny < 0.005 ? "¥0.00" : String(format: "¥%.2f", cny)
    }
    return formatUSD(usd)
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
