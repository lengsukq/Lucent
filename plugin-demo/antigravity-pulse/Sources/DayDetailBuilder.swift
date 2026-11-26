import Foundation

struct SharedModelAcc {
    let modelName: String
    let shortName: String
    let family: String
    var inputTokens = 0
    var cacheReadTokens = 0
    var outputTokens = 0
    var turns = 0
    var timedOut = 0
    var timedDur = 0.0
    var costUSD = 0.0
    var savedUSD = 0.0

    var netTokens: Int { inputTokens + outputTokens }
    var totalTokens: Int { inputTokens + cacheReadTokens + outputTokens }
}

func finalizeModelDetails(_ map: [String: SharedModelAcc], grandTotal: Int) -> [ModelUsageDetail] {
    map.values.sorted { $0.totalTokens > $1.totalTokens }.map { m in
        let prompt = m.inputTokens + m.cacheReadTokens
        let hitRate = prompt > 0 ? Double(m.cacheReadTokens) / Double(prompt) : 0.0
        let tps: Double? = m.timedDur > 0 ? Double(m.timedOut) / m.timedDur : nil
        let share = grandTotal > 0 ? Double(m.totalTokens) / Double(grandTotal) : 0.0
        return ModelUsageDetail(
            modelName: m.modelName, shortName: m.shortName, family: m.family,
            inputTokens: m.inputTokens, cacheReadTokens: m.cacheReadTokens, outputTokens: m.outputTokens,
            netTokens: m.netTokens, totalTokens: m.totalTokens, turns: m.turns,
            cacheHitRate: roundMetric(hitRate, places: 1000), avgTokensPerSec: roundOptionalMetric(tps, places: 10),
            estimatedCostUSD: roundMetric(m.costUSD, places: 100), estimatedSavedUSD: roundMetric(m.savedUSD, places: 100),
            shareRatio: roundMetric(share, places: 1000)
        )
    }
}

func buildDayDetailPayload(dateKey: String, includeCliLogs: Bool, dataDir: String, isEn: Bool) -> DayDetailPayload {
    let nowEpoch = Date().timeIntervalSince1970
    let (archive, _) = loadOrUpdateUsageArchive(includeCliLogs: includeCliLogs, dataDir: dataDir)
    let dbMeta = loadConversationSummaries(includeCliLogs: includeCliLogs)

    var dIn = 0, dCache = 0, dOut = 0, dTurns = 0
    var dCost = 0.0, dSaved = 0.0
    var modelMap: [String: SharedModelAcc] = [:]
    var sessions: [SessionHistoryRow] = []

    for file in archive.files.values {
        var sIn = 0, sCache = 0, sOut = 0, sTurns = 0, sTimedOut = 0
        var sTimedDur = 0.0, sCost = 0.0, sSaved = 0.0
        var topModel = file.primaryModel
        var topTok = 0

        for b in file.buckets where b.dateKey == dateKey {
            let prof = resolveModelProfile(rawModel: b.model)
            let cost = estimateTurnCost(inputTokens: b.inputTokens, cacheReadTokens: b.cacheReadTokens, outputTokens: b.outputTokens, profile: prof)
            dIn += b.inputTokens; dCache += b.cacheReadTokens; dOut += b.outputTokens; dTurns += b.turns
            dCost += cost.actualUSD; dSaved += cost.savedUSD
            sIn += b.inputTokens; sCache += b.cacheReadTokens; sOut += b.outputTokens; sTurns += b.turns
            sTimedOut += b.timedOutputTokens; sTimedDur += b.timedDurationSeconds
            sCost += cost.actualUSD; sSaved += cost.savedUSD
            let bTok = b.inputTokens + b.cacheReadTokens + b.outputTokens
            if bTok > topTok { topTok = bTok; topModel = b.model }

            var mAcc = modelMap[prof.displayName] ?? SharedModelAcc(modelName: prof.displayName, shortName: prof.shortName, family: prof.family)
            mAcc.inputTokens += b.inputTokens; mAcc.cacheReadTokens += b.cacheReadTokens; mAcc.outputTokens += b.outputTokens
            mAcc.turns += b.turns; mAcc.timedOut += b.timedOutputTokens; mAcc.timedDur += b.timedDurationSeconds
            mAcc.costUSD += cost.actualUSD; mAcc.savedUSD += cost.savedUSD
            modelMap[prof.displayName] = mAcc
        }
        guard sTurns > 0 else { continue }
        let meta = dbMeta[file.sessionId]
        let prof = resolveModelProfile(rawModel: topModel)
        let title = (meta?.title.isEmpty == false) ? meta!.title : (file.title.isEmpty ? "Session \(String(file.sessionId.prefix(8)))" : file.title)
        let sp = sIn + sCache
        sessions.append(SessionHistoryRow(
            sessionId: file.sessionId, source: file.source, projectName: meta?.projectName ?? "",
            title: title, modelShortName: prof.shortName,
            activityState: (meta?.isRunning == true) ? "running" : "done",
            activityLabel: (meta?.isRunning == true) ? (isEn ? "Running" : "运行中") : (isEn ? "Done" : "已完成"),
            isSubagent: (meta?.nestingDepth ?? 0) > 0,
            turns: sTurns, netTokens: sIn + sOut, totalTokens: sIn + sCache + sOut,
            cacheHitRate: roundMetric(sp > 0 ? Double(sCache) / Double(sp) : 0.0, places: 1000),
            avgTokensPerSec: roundOptionalMetric(sTimedDur > 0 ? Double(sTimedOut) / sTimedDur : nil, places: 10),
            estimatedCostUSD: roundMetric(sCost, places: 100), estimatedSavedUSD: roundMetric(sSaved, places: 100),
            updatedAt: Int(file.lastTimestamp), updatedLabel: formatRelativeUpdated(file.lastTimestamp, now: nowEpoch, isEn: isEn)
        ))
    }

    sessions.sort { $0.totalTokens > $1.totalTokens }
    let dTotal = dIn + dCache + dOut
    let dPrompt = dIn + dCache
    let weekdayStr: String = {
        guard let d = parseDateKey(dateKey) else { return "" }
        let wd = Calendar.current.component(.weekday, from: d) - 1
        let labels = isEn ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return (wd >= 0 && wd < labels.count) ? labels[wd] : ""
    }()

    return DayDetailPayload(
        ok: true, date: dateKey, weekdayLabel: weekdayStr,
        totalTokens: dTotal, netTokens: dIn + dOut, inputTokens: dIn, cacheReadTokens: dCache, outputTokens: dOut,
        turns: dTurns, cacheHitRate: dPrompt > 0 ? Double(dCache) / Double(dPrompt) : 0.0,
        estimatedCostUSD: dCost, estimatedSavedUSD: dSaved,
        models: finalizeModelDetails(modelMap, grandTotal: dTotal), sessions: sessions
    )
}
