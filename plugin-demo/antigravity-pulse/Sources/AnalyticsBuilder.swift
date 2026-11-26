import Foundation
import PluginKit

private struct ProjectAcc {
    let projectName: String
    let workspacePath: String
    var sessions: Set<String> = []
    var turns = 0
    var inputTokens = 0
    var cacheReadTokens = 0
    var outputTokens = 0
    var costUSD = 0.0
    var savedUSD = 0.0

    var netTokens: Int { inputTokens + outputTokens }
    var totalTokens: Int { inputTokens + cacheReadTokens + outputTokens }
}

private func resolveRangeSpec(_ rawKey: String, now: Date, isEn: Bool) -> (key: String, label: String, startDateKey: String?) {
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: now)
    switch rawKey.lowercased() {
    case "today":
        return ("today", isEn ? "Today" : "今日", localDateKey(for: todayStart))
    case "7d":
        let d = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return ("7d", isEn ? "Last 7 Days" : "近 7 天", localDateKey(for: d))
    case "30d":
        let d = cal.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        return ("30d", isEn ? "Last 30 Days" : "近 30 天", localDateKey(for: d))
    case "90d":
        let d = cal.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
        return ("90d", isEn ? "Last 90 Days" : "近 90 天", localDateKey(for: d))
    case "all":
        return ("all", isEn ? "All Time" : "全部历史", nil)
    default:
        let d = cal.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
        return ("365d", isEn ? "Past Year" : "过去一年", localDateKey(for: d))
    }
}

func buildAnalyticsPayload(
    rangeKey: String,
    includeCliLogs: Bool,
    themeStyle: String,
    dataDir: String,
    input: PluginInput,
    isEn: Bool
) -> AnalyticsPayload {
    let startWall = CFAbsoluteTimeGetCurrent()
    let nowDate = Date()
    let nowEpoch = nowDate.timeIntervalSince1970

    let hotOutcome = scanTranscripts(options: ScanOptions(
        includeCliLogs: includeCliLogs,
        contextWindowOverrideK: input.cfgString("contextWindowK", default: "auto"),
        requestedSessionId: nil,
        dataDir: dataDir,
        isEn: isEn
    ))
    let (archive, parsedNow) = loadOrUpdateUsageArchive(
        includeCliLogs: includeCliLogs,
        dataDir: dataDir,
        hotCacheFiles: hotOutcome.hotFilesByPath,
        input: input
    )
    let dbMeta = loadConversationSummaries(includeCliLogs: includeCliLogs)
    let prefs = loadDashboardPrefs(dataDir: dataDir, input: input)
    let quotaSummary = evaluateOfficialQuota(
        dataDir: dataDir, hotFiles: hotOutcome.hotFiles, exclusiveQuota: prefs.exclusiveQuota, now: nowEpoch, isEn: isEn
    )

    let range = resolveRangeSpec(rangeKey, now: nowDate, isEn: isEn)
    let hotBySession = Dictionary(hotOutcome.hotFiles.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })

    var dailyMap: [String: DailyAggregateBucket] = [:]
    var modelMap: [String: SharedModelAcc] = [:]
    var projectMap: [String: ProjectAcc] = [:]
    var hourlyTotal = [Int](repeating: 0, count: 24)
    var hourlyNet = [Int](repeating: 0, count: 24)
    var hourlyTurns = [Int](repeating: 0, count: 24)

    var ovIn = 0, ovCache = 0, ovOut = 0, ovTurns = 0, ovTimedOut = 0
    var ovTimedDur = 0.0, ovCost = 0.0, ovUncached = 0.0, ovSaved = 0.0
    var ovSessions = Set<String>()
    var ovActiveDays = Set<String>()
    var sessionRows: [SessionHistoryRow] = []

    for file in archive.files.values where file.turnCount > 0 {
        let meta = dbMeta[file.sessionId]
        let projName = (meta?.projectName.isEmpty == false) ? meta!.projectName : (isEn ? "Unassigned" : "未归属工作区")
        let projPath = meta?.workspacePath ?? ""

        var sessInRange = false
        var sIn = 0, sCache = 0, sOut = 0, sTurns = 0, sTimedOut = 0
        var sTimedDur = 0.0, sCost = 0.0, sSaved = 0.0

        for b in file.buckets {
            let prof = resolveModelProfile(rawModel: b.model)
            let cost = estimateTurnCost(inputTokens: b.inputTokens, cacheReadTokens: b.cacheReadTokens, outputTokens: b.outputTokens, profile: prof)

            var dAgg = dailyMap[b.dateKey] ?? DailyAggregateBucket()
            dAgg.inputTokens += b.inputTokens
            dAgg.cacheReadTokens += b.cacheReadTokens
            dAgg.outputTokens += b.outputTokens
            dAgg.turns += b.turns
            dAgg.sessions.insert(file.sessionId)
            dAgg.costUSD += cost.actualUSD
            dAgg.savedUSD += cost.savedUSD
            dAgg.timedOut += b.timedOutputTokens
            dAgg.timedDur += b.timedDurationSeconds
            dailyMap[b.dateKey] = dAgg

            guard (range.startDateKey == nil) || (b.dateKey >= range.startDateKey!) else { continue }
            sessInRange = true
            ovActiveDays.insert(b.dateKey)
            ovIn += b.inputTokens; ovCache += b.cacheReadTokens; ovOut += b.outputTokens; ovTurns += b.turns
            ovTimedOut += b.timedOutputTokens; ovTimedDur += b.timedDurationSeconds
            ovCost += cost.actualUSD; ovUncached += cost.uncachedUSD; ovSaved += cost.savedUSD

            sIn += b.inputTokens; sCache += b.cacheReadTokens; sOut += b.outputTokens; sTurns += b.turns
            sTimedOut += b.timedOutputTokens; sTimedDur += b.timedDurationSeconds
            sCost += cost.actualUSD; sSaved += cost.savedUSD

            var mAcc = modelMap[prof.displayName] ?? SharedModelAcc(modelName: prof.displayName, shortName: prof.shortName, family: prof.family)
            mAcc.inputTokens += b.inputTokens; mAcc.cacheReadTokens += b.cacheReadTokens; mAcc.outputTokens += b.outputTokens
            mAcc.turns += b.turns; mAcc.timedOut += b.timedOutputTokens; mAcc.timedDur += b.timedDurationSeconds
            mAcc.costUSD += cost.actualUSD; mAcc.savedUSD += cost.savedUSD
            modelMap[prof.displayName] = mAcc

            var pAcc = projectMap[projName] ?? ProjectAcc(projectName: projName, workspacePath: projPath)
            pAcc.sessions.insert(file.sessionId)
            pAcc.turns += b.turns; pAcc.inputTokens += b.inputTokens; pAcc.cacheReadTokens += b.cacheReadTokens; pAcc.outputTokens += b.outputTokens
            pAcc.costUSD += cost.actualUSD; pAcc.savedUSD += cost.savedUSD
            projectMap[projName] = pAcc
        }

        if sessInRange {
            ovSessions.insert(file.sessionId)
            if file.hourlyTokens.count == 24 && file.hourlyNetTokens.count == 24 && file.hourlyTurns.count == 24 {
                for h in 0..<24 {
                    hourlyTotal[h] += file.hourlyTokens[h]
                    hourlyNet[h] += file.hourlyNetTokens[h]
                    hourlyTurns[h] += file.hourlyTurns[h]
                }
            }
            let primaryProf = resolveModelProfile(rawModel: file.primaryModel)
            let actState: SessionActivityState = hotBySession[file.sessionId].map {
                resolveSessionActivityState(file: $0, meta: meta, now: nowEpoch)
            } ?? ((meta?.isRunning == true) ? .running : .done)
            let fallbackTitle = isEn ? "Session \(String(file.sessionId.prefix(8)))" : "对话 \(String(file.sessionId.prefix(8)))"
            let title = (meta?.title.isEmpty == false) ? meta!.title : (file.title.isEmpty ? fallbackTitle : file.title)
            let sPrompt = sIn + sCache
            let sHit = sPrompt > 0 ? Double(sCache) / Double(sPrompt) : 0.0
            let sTps: Double? = sTimedDur > 0 ? Double(sTimedOut) / sTimedDur : nil

            sessionRows.append(SessionHistoryRow(
                sessionId: file.sessionId, source: file.source, projectName: meta?.projectName ?? "",
                title: title, modelShortName: primaryProf.shortName,
                activityState: actState.rawValue, activityLabel: actState.label(isEn: isEn),
                isSubagent: (meta?.nestingDepth ?? 0) > 0,
                turns: sTurns, netTokens: sIn + sOut, totalTokens: sIn + sCache + sOut,
                cacheHitRate: roundMetric(sHit, places: 1000), avgTokensPerSec: roundOptionalMetric(sTps, places: 10),
                estimatedCostUSD: roundMetric(sCost, places: 100), estimatedSavedUSD: roundMetric(sSaved, places: 100),
                updatedAt: Int(file.lastTimestamp), updatedLabel: formatRelativeUpdated(file.lastTimestamp, now: nowEpoch, isEn: isEn)
            ))
        }
    }

    let ovNet = ovIn + ovOut
    let ovTotal = ovNet + ovCache
    let ovPrompt = ovIn + ovCache
    let overview = RangeOverviewKPI(
        rangeKey: range.key, rangeLabel: range.label,
        totalTokens: ovTotal, netTokens: ovNet, inputTokens: ovIn, cacheReadTokens: ovCache, outputTokens: ovOut,
        turns: ovTurns, sessions: ovSessions.count, activeDays: ovActiveDays.count,
        cacheHitRate: roundMetric(ovPrompt > 0 ? Double(ovCache) / Double(ovPrompt) : 0.0, places: 1000),
        avgTokensPerSec: roundOptionalMetric(ovTimedDur > 0 ? Double(ovTimedOut) / ovTimedDur : nil, places: 10),
        estimatedCostUSD: roundMetric(ovCost, places: 100),
        estimatedUncachedUSD: roundMetric(ovUncached, places: 100),
        estimatedSavedUSD: roundMetric(ovSaved, places: 100)
    )

    let (heatStart, heatEnd, heatmap, thresholds, streaks) = buildHeatmapAndStreaks(dailyMap: dailyMap, now: nowDate)
    let (granularity, trends) = buildTrendSeries(dailyMap: dailyMap, rangeKey: range.key, now: nowDate)
    let hourly = (0..<24).map { HourlyRhythmPoint(hour: $0, totalTokens: hourlyTotal[$0], netTokens: hourlyNet[$0], turns: hourlyTurns[$0]) }
    let models = finalizeModelDetails(modelMap, grandTotal: ovTotal)
    let projects = projectMap.values.sorted { $0.totalTokens > $1.totalTokens }.prefix(16).map { p -> ProjectUsageDetail in
        let pp = p.inputTokens + p.cacheReadTokens
        return ProjectUsageDetail(
            projectName: p.projectName, workspacePath: p.workspacePath, sessions: p.sessions.count, turns: p.turns,
            netTokens: p.netTokens, totalTokens: p.totalTokens,
            cacheHitRate: roundMetric(pp > 0 ? Double(p.cacheReadTokens) / Double(pp) : 0.0, places: 1000),
            estimatedCostUSD: roundMetric(p.costUSD, places: 100), estimatedSavedUSD: roundMetric(p.savedUSD, places: 100),
            shareRatio: roundMetric(ovTotal > 0 ? Double(p.totalTokens) / Double(ovTotal) : 0.0, places: 1000)
        )
    }

    sessionRows.sort { $0.updatedAt > $1.updatedAt }
    let totalSessionCount = sessionRows.count
    let elapsedMs = ((CFAbsoluteTimeGetCurrent() - startWall) * 10000.0).rounded() / 10.0

    return AnalyticsPayload(
        ok: true, refreshedAt: formatShortClock(nowEpoch), scanDurationMs: elapsedMs,
        totalArchivedFiles: archive.files.count, parsedNow: parsedNow,
        rangeKey: range.key, themeStyle: themeStyle, currency: prefs.currency, usdToCnyRate: prefs.usdToCnyRate,
        overview: overview, quota: quotaSummary, heatmapStartDate: heatStart, heatmapEndDate: heatEnd,
        heatmap: heatmap, heatmapThresholds: thresholds,
        streaks: streaks, trendGranularity: granularity, trends: trends, hourlyRhythm: hourly,
        models: models, projects: projects, totalSessionRows: totalSessionCount,
        sessions: Array(sessionRows.prefix(100)),
        pricingRefs: allModelPricingReferences()
    )
}
