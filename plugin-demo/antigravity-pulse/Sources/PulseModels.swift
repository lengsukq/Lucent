import Foundation

enum PulseConstants {
    static let windowID = "antigravity-pulse-hud"
    static let cacheSchemaVersion = 4
    static let maxRecentSessions = 12
    static let maxCachedRecentSessions = 24
    static let maxChartPoints = 48
    static let fiveHoursSeconds: TimeInterval = 5 * 3600
    static let sevenDaysSeconds: TimeInterval = 7 * 86400
    static let scanRetentionSeconds: TimeInterval = 8 * 86400
    static let activeRunningGraceSeconds: TimeInterval = 600
    static let freshNotificationGraceSeconds: TimeInterval = 360
    static let cacheDropMinPreviousReadTokens = 10_000
    static let cacheDropRateDeltaThreshold = 0.35
    static let cacheDropReadDropRatio = 0.50
    static let highContextCriticalRatio = 0.85
    static let alertCooldownSeconds: TimeInterval = 180
}

enum SessionActivityState: String, Codable {
    case running
    case done
    case error
    case idle

    func label(isEn: Bool) -> String {
        switch self {
        case .running: return isEn ? "Running" : "运行中"
        case .done: return isEn ? "Done" : "已完成"
        case .error: return isEn ? "Error" : "异常"
        case .idle: return isEn ? "Paused" : "已暂停"
        }
    }
}

struct CachedTurnRecord: Codable {
    let stepIndex: Int
    let timestamp: TimeInterval
    let model: String
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let durationSeconds: Double?
}

struct CachedTranscriptFile: Codable {
    let sessionId: String
    let source: String
    let title: String
    let fileSize: Int64
    let mtimeEpoch: TimeInterval
    let dbMtimeEpoch: TimeInterval
    let lastEventType: String
    let lastEventStatus: String
    let lastEventHasToolCalls: Bool
    let lastEventTimestamp: TimeInterval
    let turns: [CachedTurnRecord]
}

struct TranscriptIndexCache: Codable {
    let schemaVersion: Int
    var files: [String: CachedTranscriptFile]
}

struct TurnPoint: Codable {
    let step: Int
    let time: String
    let timestamp: TimeInterval
    let contextTokens: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let durationSeconds: Double?
    let tokensPerSec: Double?
    let cacheHitRate: Double
    let model: String
}

struct SessionSummary: Codable {
    let sessionId: String
    let source: String
    let projectName: String
    let title: String
    let modelId: String
    let modelName: String
    let modelShortName: String
    let activityState: String
    let activityLabel: String
    let isCompleted: Bool
    let resumeURL: String?
    let resumeCommand: String
    let turnCount: Int
    let latestStep: Int
    let updatedAt: TimeInterval
    let updatedLabel: String
    let contextTokens: Int
    let contextLimit: Int
    let contextRatio: Double
    let latestInputTokens: Int
    let latestCacheReadTokens: Int
    let latestOutputTokens: Int
    let latestCacheHitRate: Double
    let cumulativeInputTokens: Int
    let cumulativeCacheReadTokens: Int
    let cumulativeOutputTokens: Int
    let cumulativeCacheHitRate: Double
    let avgOutputTokensPerSec: Double?
    let totalOutputDurationSeconds: Double
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let cacheDropped: Bool
    let cacheDropPrevRate: Double?
    let cacheDropDelta: Double?
    let turns: [TurnPoint]
}

struct SessionListItem: Codable {
    let sessionId: String
    let source: String
    let projectName: String
    let title: String
    let modelShortName: String
    let activityState: String
    let activityLabel: String
    let isCompleted: Bool
    let resumeURL: String?
    let resumeCommand: String
    let contextTokens: Int
    let contextLimit: Int
    let contextRatio: Double
    let cumulativeCacheHitRate: Double
    let avgOutputTokensPerSec: Double?
    let turnCount: Int
    let updatedAt: TimeInterval
    let updatedLabel: String
    let isActive: Bool
}

struct ModelBreakdown: Codable {
    let modelName: String
    let shortName: String
    let totalTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let turns: Int
    let cacheHitRate: Double
    let estimatedCostUSD: Double
}

struct WindowUsageStats: Codable {
    let label: String
    let netTokens: Int
    let totalTokens: Int
    let inputTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let timedOutputTokens: Int
    let timedDurationSeconds: Double
    let avgTokensPerSec: Double?
    let turns: Int
    let cacheHitRate: Double
    let estimatedCostUSD: Double
    let estimatedSavedUSD: Double
    let topModels: [ModelBreakdown]
}

struct PulseAlertBanner: Codable {
    let kind: String
    let sessionId: String?
    let source: String?
    let resumeURL: String?
    let resumeCommand: String?
    let title: String
    let detail: String
    let notificationSent: Bool
}

struct DockLaunchState: Codable {
    var edge: String
    var fromMode: String?
    var pendingSnap: Bool
}

struct PulseSnapshot: Codable {
    let ok: Bool
    let error: String?
    let scannedFiles: Int
    let parsedFilesNow: Int
    let scanDurationMs: Double
    let refreshedAt: String
    let refreshIntervalSec: Int
    let defaultMode: String
    let themeStyle: String
    let runningCount: Int
    let completedCount: Int
    let activeSession: SessionSummary?
    let recentSessions: [SessionListItem]
    let window5h: WindowUsageStats
    let windowToday: WindowUsageStats
    let window7d: WindowUsageStats
    let alertBanner: PulseAlertBanner?
    let dockState: DockLaunchState?
}

func emitEncodableJSON<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes]
    if let data = try? enc.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
