import Foundation

// MARK: - Incremental Cold Archive Models

struct DailyModelBucket: Codable {
    let dateKey: String
    let model: String
    var inputTokens: Int
    var cacheReadTokens: Int
    var outputTokens: Int
    var turns: Int
    var timedOutputTokens: Int
    var timedDurationSeconds: Double
}

struct ArchivedFileUsage: Codable {
    let sessionId: String
    let source: String
    let title: String
    let fileSize: Int64
    let mtimeEpoch: TimeInterval
    let firstTimestamp: TimeInterval
    let lastTimestamp: TimeInterval
    let primaryModel: String
    let totalInputTokens: Int
    let totalCacheReadTokens: Int
    let totalOutputTokens: Int
    let turnCount: Int
    let timedOutputTokens: Int
    let timedDurationSeconds: Double
    let hourlyTokens: [Int]
    let hourlyNetTokens: [Int]
    let hourlyTurns: [Int]
    let buckets: [DailyModelBucket]
}

struct UsageArchiveCache: Codable {
    let schemaVersion: Int
    var files: [String: ArchivedFileUsage]
}

// MARK: - Dashboard Preferences & Compact Analytics Payload Models

struct DashboardPrefs: Codable {
    var currency: String
    var usdToCnyRate: Double
    var exclusiveQuota: Bool

    init(currency: String, usdToCnyRate: Double, exclusiveQuota: Bool = false) {
        self.currency = currency
        self.usdToCnyRate = usdToCnyRate
        self.exclusiveQuota = exclusiveQuota
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.currency = (try? c.decode(String.self, forKey: .currency)) ?? "USD"
        self.usdToCnyRate = (try? c.decode(Double.self, forKey: .usdToCnyRate)) ?? 7.25
        self.exclusiveQuota = (try? c.decode(Bool.self, forKey: .exclusiveQuota)) ?? false
    }
}

/// Compact active-day heatmap record (empty days are reconstructed client-side between `heatmapStartDate` and `heatmapEndDate`).
struct HeatmapDayPoint: Codable {
    let d: String      // YYYY-MM-DD
    let t: Int         // totalTokens
    let n: Int         // netTokens
    let i: Int         // inputTokens
    let c: Int         // cacheReadTokens
    let o: Int         // outputTokens
    let r: Int         // turns
    let s: Int         // sessions
    let u: Double      // estimatedCostUSD (rounded)
    let v: Double      // estimatedSavedUSD (rounded)
    let h: Double      // cacheHitRate (0..1, rounded)
    let p: Double?     // avgTokensPerSec (rounded)
    let lv: [Int]      // [levelTotal, levelNet, levelCost, levelTurns]
}

struct HeatmapThresholds: Codable {
    let total: [Double]
    let net: [Double]
    let cost: [Double]
    let turns: [Double]
}

struct StreakStats: Codable {
    let currentStreakDays: Int
    let longestStreakDays: Int
    let activeDaysYear: Int
    let totalTokensYear: Int
    let netTokensYear: Int
    let avgDailyTotalTokens: Int
    let avgDailyNetTokens: Int
    let peakDate: String?
    let peakTotalTokens: Int
    let peakNetTokens: Int
}

struct DailyTrendPoint: Codable {
    let key: String
    let label: String
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let netTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let turns: Int
    let avgTokensPerSec: Double?
}

struct HourlyRhythmPoint: Codable {
    let hour: Int
    let totalTokens: Int
    let netTokens: Int
    let turns: Int
}

struct ModelUsageDetail: Codable {
    let modelName: String
    let shortName: String
    let family: String
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let netTokens: Int
    let totalTokens: Int
    let turns: Int
    let cacheHitRate: Double
    let avgTokensPerSec: Double?
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let shareRatio: Double
}

struct ProjectUsageDetail: Codable {
    let projectName: String
    let workspacePath: String
    let sessions: Int
    let turns: Int
    let netTokens: Int
    let totalTokens: Int
    let cacheHitRate: Double
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let shareRatio: Double
}

struct SessionHistoryRow: Codable {
    let sessionId: String
    let source: String
    let projectName: String
    let title: String
    let modelShortName: String
    let activityState: String
    let activityLabel: String
    let isSubagent: Bool
    let turns: Int
    let netTokens: Int
    let totalTokens: Int
    let cacheHitRate: Double
    let avgTokensPerSec: Double?
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let updatedAt: Int
    let updatedLabel: String
}

struct RangeOverviewKPI: Codable {
    let rangeKey: String
    let rangeLabel: String
    let totalTokens: Int
    let netTokens: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let turns: Int
    let sessions: Int
    let activeDays: Int
    let cacheHitRate: Double
    let avgTokensPerSec: Double?
    let estimatedCostUSD: Double
    let estimatedUncachedUSD: Double
    let estimatedSavedUSD: Double
}

struct DayDetailPayload: Codable {
    let ok: Bool
    let date: String
    let weekdayLabel: String
    let totalTokens: Int
    let netTokens: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let turns: Int
    let cacheHitRate: Double
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let models: [ModelUsageDetail]
    let sessions: [SessionHistoryRow]
}

struct AnalyticsPayload: Codable {
    let ok: Bool
    let refreshedAt: String
    let scanDurationMs: Double
    let totalArchivedFiles: Int
    let parsedNow: Int
    let rangeKey: String
    let themeStyle: String
    let currency: String
    let usdToCnyRate: Double
    let overview: RangeOverviewKPI
    let quota: OfficialQuotaSummary
    let heatmapStartDate: String
    let heatmapEndDate: String
    let heatmap: [HeatmapDayPoint]
    let heatmapThresholds: HeatmapThresholds
    let streaks: StreakStats
    let trendGranularity: String
    let trends: [DailyTrendPoint]
    let hourlyRhythm: [HourlyRhythmPoint]
    let models: [ModelUsageDetail]
    let projects: [ProjectUsageDetail]
    let totalSessionRows: Int
    let sessions: [SessionHistoryRow]
    let pricingRefs: [ModelPricingReference]
}

func roundMetric(_ v: Double, places: Double = 1000.0) -> Double {
    guard v.isFinite else { return 0 }
    return (v * places).rounded() / places
}

func roundOptionalMetric(_ v: Double?, places: Double = 10.0) -> Double? {
    guard let v, v.isFinite else { return nil }
    return (v * places).rounded() / places
}
