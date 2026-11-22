import Darwin
import Foundation

struct ScanOptions {
    let includeCliLogs: Bool
    let contextWindowOverrideK: String
    let requestedSessionId: String?
    let dataDir: String
    let isEn: Bool
}

struct ScanOutcome {
    let scannedFiles: Int
    let parsedFilesNow: Int
    let scanDurationMs: Double
    let runningCount: Int
    let completedCount: Int
    let activeSession: SessionSummary?
    let recentSessions: [SessionListItem]
    let window5h: WindowUsageStats
    let windowToday: WindowUsageStats
    let window7d: WindowUsageStats
}

func resolveSessionActivityState(
    file: CachedTranscriptFile, meta: ConversationSummaryMeta?, now: TimeInterval
) -> SessionActivityState {
    let status = file.lastEventStatus.uppercased()
    let kind = file.lastEventType.uppercased()
    let age = now - max(file.mtimeEpoch, file.lastEventTimestamp)
    if status == "ERROR" || status == "FAILED" || status == "CANCELLED" { return .error }
    if let m = meta {
        if m.isRunning { return .running }
        if m.isIdle { return .done }
    }
    if kind == "PLANNER_RESPONSE" && status == "DONE" && !file.lastEventHasToolCalls { return .done }
    if status == "RUNNING" || status == "PENDING" || status == "IN_PROGRESS" {
        return age <= PulseConstants.activeRunningGraceSeconds ? .running : .idle
    }
    return (!kind.isEmpty && age <= PulseConstants.activeRunningGraceSeconds) ? .running : .idle
}

private func discoverTranscripts(includeCliLogs: Bool) -> [DiscoveredTranscript] {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    var roots: [(String, String)] = [("\(home)/.gemini/antigravity/brain", "desktop")]
    if includeCliLogs { roots.append(("\(home)/.gemini/antigravity-cli/brain", "cli")) }

    var discovered: [DiscoveredTranscript] = []
    var seen = Set<String>()
    for (rootPath, sourceName) in roots {
        guard let entries = try? fm.contentsOfDirectory(atPath: rootPath) else { continue }
        for sessionId in entries where !sessionId.hasPrefix(".") {
            let stdPath = "\(rootPath)/\(sessionId)/.system_generated/logs/transcript.jsonl"
            let directPath = "\(rootPath)/\(sessionId)/transcript.jsonl"
            let target = fm.fileExists(atPath: stdPath) ? stdPath : (fm.fileExists(atPath: directPath) ? directPath : nil)
            guard let path = target, seen.insert(path).inserted else { continue }
            var st = stat()
            guard stat(path, &st) == 0, st.st_size > 0 else { continue }
            let mtime = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
            discovered.append(DiscoveredTranscript(path: path, sessionId: sessionId, source: sourceName, fileSize: Int64(st.st_size), mtimeEpoch: mtime))
        }
    }
    return discovered
}

private func loadIndexCache(dataDir: String) -> TranscriptIndexCache {
    guard !dataDir.isEmpty,
          let data = try? Data(contentsOf: URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("transcript-index-cache.json")),
          let decoded = try? JSONDecoder().decode(TranscriptIndexCache.self, from: data),
          decoded.schemaVersion == PulseConstants.cacheSchemaVersion
    else { return TranscriptIndexCache(schemaVersion: PulseConstants.cacheSchemaVersion, files: [:]) }
    return decoded
}

private func saveIndexCache(dataDir: String, cache: TranscriptIndexCache) {
    guard !dataDir.isEmpty else { return }
    let url = URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("transcript-index-cache.json")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
}

private struct ModelAccumulator {
    let modelName: String, shortName: String
    var totalTokens = 0, cacheReadTokens = 0, inputTokens = 0, outputTokens = 0, turns = 0, estimatedCostUSD = 0.0
}

private struct WindowAccumulator {
    let label: String, cutoffEpoch: TimeInterval
    var inputTokens = 0, cacheReadTokens = 0, outputTokens = 0, timedOutputTokens = 0
    var timedDurationSeconds = 0.0, turns = 0, estimatedCostUSD = 0.0, estimatedSavedUSD = 0.0
    var byModel: [String: ModelAccumulator] = [:]

    mutating func add(turn: CachedTurnRecord, profile: ModelProfile, cost: TurnCostEstimate) {
        guard turn.timestamp >= cutoffEpoch else { return }
        inputTokens += turn.inputTokens; cacheReadTokens += turn.cacheReadTokens; outputTokens += turn.outputTokens
        if let dur = turn.durationSeconds, dur > 0, turn.outputTokens > 0 {
            timedOutputTokens += turn.outputTokens; timedDurationSeconds += dur
        }
        turns += 1; estimatedCostUSD += cost.actualUSD; estimatedSavedUSD += cost.savedUSD
        var e = byModel[profile.displayName] ?? ModelAccumulator(modelName: profile.displayName, shortName: profile.shortName)
        e.inputTokens += turn.inputTokens; e.cacheReadTokens += turn.cacheReadTokens; e.outputTokens += turn.outputTokens
        e.totalTokens += turn.inputTokens + turn.cacheReadTokens + turn.outputTokens; e.turns += 1; e.estimatedCostUSD += cost.actualUSD
        byModel[profile.displayName] = e
    }

    func finalize() -> WindowUsageStats {
        let net = inputTokens + outputTokens, total = net + cacheReadTokens, prompt = inputTokens + cacheReadTokens
        let hitRate = prompt > 0 ? Double(cacheReadTokens) / Double(prompt) : 0.0
        let avgTps: Double? = timedDurationSeconds > 0 ? Double(timedOutputTokens) / timedDurationSeconds : nil
        let sortedModels = byModel.values.sorted { $0.totalTokens > $1.totalTokens }.prefix(5).map { m in
            let mp = m.inputTokens + m.cacheReadTokens
            return ModelBreakdown(
                modelName: m.modelName, shortName: m.shortName, totalTokens: m.totalTokens, cacheReadTokens: m.cacheReadTokens,
                outputTokens: m.outputTokens, turns: m.turns, cacheHitRate: mp > 0 ? Double(m.cacheReadTokens) / Double(mp) : 0.0, estimatedCostUSD: m.estimatedCostUSD
            )
        }
        return WindowUsageStats(
            label: label, netTokens: net, totalTokens: total, inputTokens: inputTokens, cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens, timedOutputTokens: timedOutputTokens, timedDurationSeconds: timedDurationSeconds,
            avgTokensPerSec: avgTps, turns: turns, cacheHitRate: hitRate, estimatedCostUSD: estimatedCostUSD, estimatedSavedUSD: estimatedSavedUSD, topModels: sortedModels
        )
    }
}

private func buildSessionSummary(
    file: CachedTranscriptFile, meta: ConversationSummaryMeta?, contextWindowOverrideK: String, now: TimeInterval, isEn: Bool
) -> SessionSummary? {
    guard let latest = file.turns.last else { return nil }
    let latestProfile = resolveModelProfile(rawModel: latest.model)
    let limit = resolveContextLimit(profile: latestProfile, configOverrideK: contextWindowOverrideK)
    let latestContext = latest.inputTokens + latest.cacheReadTokens
    let latestRatio = limit > 0 ? Double(latestContext) / Double(limit) : 0.0
    let latestCacheRate = latestContext > 0 ? Double(latest.cacheReadTokens) / Double(latestContext) : 0.0

    var cumInput = 0, cumCache = 0, cumOutput = 0, timedOut = 0
    var timedDur = 0.0, totalCost = 0.0, totalSaved = 0.0
    var chartPoints: [TurnPoint] = []
    let startIdx = max(0, file.turns.count - PulseConstants.maxChartPoints)

    for (idx, turn) in file.turns.enumerated() {
        cumInput += turn.inputTokens; cumCache += turn.cacheReadTokens; cumOutput += turn.outputTokens
        if let dur = turn.durationSeconds, dur > 0, turn.outputTokens > 0 { timedOut += turn.outputTokens; timedDur += dur }
        let prof = resolveModelProfile(rawModel: turn.model)
        let cost = estimateTurnCost(inputTokens: turn.inputTokens, cacheReadTokens: turn.cacheReadTokens, outputTokens: turn.outputTokens, profile: prof)
        totalCost += cost.actualUSD; totalSaved += cost.savedUSD
        if idx >= startIdx {
            let ctx = turn.inputTokens + turn.cacheReadTokens
            let tps: Double? = (turn.durationSeconds ?? 0) > 0 && turn.outputTokens > 0 ? Double(turn.outputTokens) / turn.durationSeconds! : nil
            chartPoints.append(TurnPoint(
                step: turn.stepIndex, time: formatShortClock(turn.timestamp), timestamp: turn.timestamp,
                contextTokens: ctx, inputTokens: turn.inputTokens, cacheReadTokens: turn.cacheReadTokens,
                outputTokens: turn.outputTokens, durationSeconds: turn.durationSeconds, tokensPerSec: tps,
                cacheHitRate: ctx > 0 ? Double(turn.cacheReadTokens) / Double(ctx) : 0.0, model: prof.shortName
            ))
        }
    }

    let cumPrompt = cumInput + cumCache
    let cumCacheRate = cumPrompt > 0 ? Double(cumCache) / Double(cumPrompt) : 0.0
    var cacheDropped = false
    var prevRateOut: Double? = nil
    var dropDeltaOut: Double? = nil
    if file.turns.count >= 2 {
        let prev = file.turns[file.turns.count - 2]
        let prevCtx = prev.inputTokens + prev.cacheReadTokens
        let prevRate = prevCtx > 0 ? Double(prev.cacheReadTokens) / Double(prevCtx) : 0.0
        let delta = prevRate - latestCacheRate
        let shrank = prev.cacheReadTokens >= PulseConstants.cacheDropMinPreviousReadTokens
            && Double(latest.cacheReadTokens) < Double(prev.cacheReadTokens) * PulseConstants.cacheDropReadDropRatio
        if prev.cacheReadTokens >= PulseConstants.cacheDropMinPreviousReadTokens
            && (delta >= PulseConstants.cacheDropRateDeltaThreshold || shrank) {
            cacheDropped = true; prevRateOut = prevRate; dropDeltaOut = delta
        }
    }

    let activity = resolveSessionActivityState(file: file, meta: meta, now: now)
    let updatedAt = max(max(latest.timestamp, file.mtimeEpoch), file.lastEventTimestamp)
    let fallbackTitle = isEn ? "Session \(String(file.sessionId.prefix(8)))" : "对话 \(String(file.sessionId.prefix(8)))"
    let resolvedTitle = (meta?.title.isEmpty == false ? meta!.title : (file.title.isEmpty ? fallbackTitle : file.title))
    let projectName = meta?.projectName ?? ""
    let resumeURL: String? = (file.source == "desktop") ? "file:///Applications/Antigravity.app" : nil
    let resumeCmd = "agy --conversation \(file.sessionId)"

    let avgTps: Double? = timedDur > 0 ? Double(timedOut) / timedDur : nil
    return SessionSummary(
        sessionId: file.sessionId, source: file.source, projectName: projectName, title: resolvedTitle,
        modelId: latest.model, modelName: latestProfile.displayName, modelShortName: latestProfile.shortName,
        activityState: activity.rawValue, activityLabel: activity.label(isEn: isEn), isCompleted: activity == .done,
        resumeURL: resumeURL, resumeCommand: resumeCmd, turnCount: file.turns.count, latestStep: latest.stepIndex,
        updatedAt: updatedAt, updatedLabel: formatRelativeUpdated(updatedAt, now: now, isEn: isEn),
        contextTokens: latestContext, contextLimit: limit, contextRatio: latestRatio,
        latestInputTokens: latest.inputTokens, latestCacheReadTokens: latest.cacheReadTokens,
        latestOutputTokens: latest.outputTokens, latestCacheHitRate: latestCacheRate,
        cumulativeInputTokens: cumInput, cumulativeCacheReadTokens: cumCache,
        cumulativeOutputTokens: cumOutput, cumulativeCacheHitRate: cumCacheRate,
        avgOutputTokensPerSec: avgTps, totalOutputDurationSeconds: timedDur,
        estimatedCostUSD: totalCost, estimatedSavedUSD: totalSaved,
        cacheDropped: cacheDropped, cacheDropPrevRate: prevRateOut, cacheDropDelta: dropDeltaOut, turns: chartPoints
    )
}

func scanTranscripts(options: ScanOptions) -> ScanOutcome {
    let startWall = CFAbsoluteTimeGetCurrent()
    let now = Date().timeIntervalSince1970
    let discovered = discoverTranscripts(includeCliLogs: options.includeCliLogs)
    let retentionCutoff = now - PulseConstants.scanRetentionSeconds
    let sortedDiscovered = discovered.sorted { $0.mtimeEpoch > $1.mtimeEpoch }
    let relevant = sortedDiscovered.enumerated().compactMap { idx, item -> DiscoveredTranscript? in
        let isPinned = (options.requestedSessionId != nil && item.sessionId == options.requestedSessionId)
        return (idx < PulseConstants.maxCachedRecentSessions || item.mtimeEpoch >= retentionCutoff || isPinned) ? item : nil
    }

    var cache = loadIndexCache(dataDir: options.dataDir)
    var cacheDirty = false
    var parsedNow = 0
    var activePaths = Set<String>()
    var validFiles: [CachedTranscriptFile] = []

    for item in relevant {
        activePaths.insert(item.path)
        if let cached = cache.files[item.path], cached.fileSize == item.fileSize, abs(cached.mtimeEpoch - item.mtimeEpoch) < 0.001 {
            let refreshed = refreshTimingIfNeeded(cached)
            if refreshed.updated { cache.files[item.path] = refreshed.file; cacheDirty = true }
            if !refreshed.file.turns.isEmpty { validFiles.append(refreshed.file) }
            continue
        }
        let parsed = enrichTurnsWithDurations(parseTranscriptFile(item))
        cache.files[item.path] = parsed
        cacheDirty = true; parsedNow += 1
        if !parsed.turns.isEmpty { validFiles.append(parsed) }
    }

    for key in cache.files.keys where !activePaths.contains(key) {
        cache.files.removeValue(forKey: key); cacheDirty = true
    }
    if cacheDirty { saveIndexCache(dataDir: options.dataDir, cache: cache) }

    let startOfToday = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: now)).timeIntervalSince1970
    var acc5h = WindowAccumulator(label: options.isEn ? "5 Hours" : "5 小时", cutoffEpoch: now - PulseConstants.fiveHoursSeconds)
    var accToday = WindowAccumulator(label: options.isEn ? "Today" : "今日", cutoffEpoch: startOfToday)
    var acc7d = WindowAccumulator(label: options.isEn ? "7 Days" : "7 天", cutoffEpoch: now - PulseConstants.sevenDaysSeconds)

    let cutoff7d = now - PulseConstants.sevenDaysSeconds
    for file in validFiles where file.mtimeEpoch >= cutoff7d || (file.turns.last?.timestamp ?? 0) >= cutoff7d {
        for turn in file.turns where turn.timestamp >= cutoff7d {
            let prof = resolveModelProfile(rawModel: turn.model)
            let cost = estimateTurnCost(inputTokens: turn.inputTokens, cacheReadTokens: turn.cacheReadTokens, outputTokens: turn.outputTokens, profile: prof)
            acc7d.add(turn: turn, profile: prof, cost: cost)
            accToday.add(turn: turn, profile: prof, cost: cost)
            acc5h.add(turn: turn, profile: prof, cost: cost)
        }
    }

    let dbMeta = loadConversationSummaries(includeCliLogs: options.includeCliLogs)
    let topLevelFiles = validFiles.filter { (dbMeta[$0.sessionId]?.nestingDepth ?? 0) == 0 }
    let candidateFiles = topLevelFiles.isEmpty ? validFiles : topLevelFiles
    let sortedFiles = candidateFiles.sorted { lhs, rhs in
        let lRun = resolveSessionActivityState(file: lhs, meta: dbMeta[lhs.sessionId], now: now) == .running
        let rRun = resolveSessionActivityState(file: rhs, meta: dbMeta[rhs.sessionId], now: now) == .running
        if lRun != rRun { return lRun }
        return max(lhs.mtimeEpoch, lhs.lastEventTimestamp) > max(rhs.mtimeEpoch, rhs.lastEventTimestamp)
    }
    let selectedFile = options.requestedSessionId.flatMap { req in
        let clean = req.trimmingCharacters(in: .whitespacesAndNewlines)
        return sortedFiles.first { $0.sessionId == clean } ?? validFiles.first { $0.sessionId == clean }
    } ?? sortedFiles.first

    let activeSummary = selectedFile.flatMap {
        buildSessionSummary(file: $0, meta: dbMeta[$0.sessionId], contextWindowOverrideK: options.contextWindowOverrideK, now: now, isEn: options.isEn)
    }
    let recentList: [SessionListItem] = sortedFiles.prefix(PulseConstants.maxRecentSessions).compactMap { file in
        guard let s = buildSessionSummary(file: file, meta: dbMeta[file.sessionId], contextWindowOverrideK: options.contextWindowOverrideK, now: now, isEn: options.isEn) else { return nil }
        return SessionListItem(
            sessionId: s.sessionId, source: s.source, projectName: s.projectName, title: s.title,
            modelShortName: s.modelShortName, activityState: s.activityState, activityLabel: s.activityLabel,
            isCompleted: s.isCompleted, resumeURL: s.resumeURL, resumeCommand: s.resumeCommand,
            contextTokens: s.contextTokens, contextLimit: s.contextLimit, contextRatio: s.contextRatio,
            cumulativeCacheHitRate: s.cumulativeCacheHitRate, avgOutputTokensPerSec: s.avgOutputTokensPerSec,
            turnCount: s.turnCount, updatedAt: s.updatedAt, updatedLabel: s.updatedLabel,
            isActive: s.sessionId == activeSummary?.sessionId
        )
    }

    let runningCount = recentList.filter { $0.activityState == SessionActivityState.running.rawValue }.count
    let completedCount = recentList.filter { $0.isCompleted }.count
    let elapsedMs = ((CFAbsoluteTimeGetCurrent() - startWall) * 10000.0).rounded() / 10.0

    return ScanOutcome(
        scannedFiles: discovered.count, parsedFilesNow: parsedNow, scanDurationMs: elapsedMs,
        runningCount: runningCount, completedCount: completedCount,
        activeSession: activeSummary, recentSessions: recentList,
        window5h: acc5h.finalize(), windowToday: accToday.finalize(), window7d: acc7d.finalize()
    )
}
