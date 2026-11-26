import Foundation

private enum QuotaCalcBounds {
    static let minUsedPctForInference: Double = 5.0
    static let minUsedCostUSDForInference: Double = 0.05
    static let maxStoredSamples: Int = 36
    static let maxWindowSamplesForMedian: Int = 12
    static let weeksPerMonth: Double = 4.33
}

private struct ParsedQuotaWindow {
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAtEpoch: TimeInterval?
    let windowSeconds: TimeInterval
}

private struct FamilyParsedBuckets {
    var w5h: ParsedQuotaWindow?
    var weekly: ParsedQuotaWindow?
}

private func learningCacheURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("quota-learning-cache.json")
}

private func loadLearningCache(dataDir: String) -> QuotaLearningCache {
    guard let url = learningCacheURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(QuotaLearningCache.self, from: data) else {
        return QuotaLearningCache(samples: [])
    }
    return decoded
}

private func saveLearningCache(dataDir: String, cache: QuotaLearningCache) {
    guard let url = learningCacheURL(dataDir: dataDir),
          let data = try? JSONEncoder().encode(cache) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

private func loadQuotaSnapshotFile(path: String) -> AgyQuotaSnapshotFile? {
    guard FileManager.default.fileExists(atPath: path),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let decoded = try? JSONDecoder().decode(AgyQuotaSnapshotFile.self, from: data),
          let q = decoded.quota, !q.isEmpty else {
        return nil
    }
    return decoded
}

func loadFreshestOfficialQuota(dataDir: String) -> (snapshot: AgyQuotaSnapshotFile, sourceTag: String)? {
    let pulseSnap = loadQuotaSnapshotFile(path: pulseQuotaFilePath(dataDir: dataDir))
    let auditSnap = loadQuotaSnapshotFile(path: aiAuditQuotaFilePath())
    switch (pulseSnap, auditSnap) {
    case let (p?, a?): return p.observed_at >= a.observed_at ? (p, "pulse") : (a, "ai-audit")
    case let (p?, nil): return (p, "pulse")
    case let (nil, a?): return (a, "ai-audit")
    case (nil, nil): return nil
    }
}

private func parseBucketToWindow(_ bucket: AgyQuotaBucket, observedAtEpoch: TimeInterval, windowSeconds: TimeInterval) -> ParsedQuotaWindow? {
    guard bucket.disabled != true, let rawFrac = bucket.remaining_fraction else { return nil }
    let remPct = min(1.0, max(0.0, rawFrac)) * 100.0
    let usedPct = max(0.0, min(100.0, 100.0 - remPct))
    var resetsAt: TimeInterval? = bucket.reset_time.flatMap(parseISO8601Epoch)
    if resetsAt == nil, let sec = bucket.reset_in_seconds, sec > 0, observedAtEpoch > 0 {
        resetsAt = observedAtEpoch + TimeInterval(sec)
    }
    return ParsedQuotaWindow(usedPercent: usedPct, remainingPercent: remPct, resetsAtEpoch: resetsAt, windowSeconds: windowSeconds)
}

private func computeLocalCycleSpend(
    hotFiles: [CachedTranscriptFile],
    family: String,
    windowStart: TimeInterval,
    now: TimeInterval
) -> (costUSD: Double, savedUSD: Double, totalTokens: Int, netTokens: Int) {
    var familyCost = 0.0, familySaved = 0.0, familyTotal = 0, familyNet = 0
    var allCost = 0.0, allSaved = 0.0, allTotal = 0, allNet = 0
    let filterByFamily = (family == "gemini" || family == "claude_gpt")

    for file in hotFiles where file.mtimeEpoch >= windowStart || (file.turns.last?.timestamp ?? 0) >= windowStart {
        for turn in file.turns where turn.timestamp >= windowStart && turn.timestamp <= now + 60 {
            let prof = resolveModelProfile(rawModel: turn.model)
            let cost = estimateTurnCost(inputTokens: turn.inputTokens, cacheReadTokens: turn.cacheReadTokens, outputTokens: turn.outputTokens, profile: prof)
            let net = turn.inputTokens + turn.outputTokens
            let tot = net + turn.cacheReadTokens
            allCost += cost.actualUSD; allSaved += cost.savedUSD; allTotal += tot; allNet += net
            if filterByFamily && prof.family == family {
                familyCost += cost.actualUSD; familySaved += cost.savedUSD; familyTotal += tot; familyNet += net
            }
        }
    }
    return (filterByFamily && familyTotal > 0) ? (familyCost, familySaved, familyTotal, familyNet) : (allCost, allSaved, allTotal, allNet)
}

private func buildWindowEstimate(
    parsed: ParsedQuotaWindow,
    kind: String,
    family: String,
    planTier: String,
    hotFiles: [CachedTranscriptFile],
    exclusiveQuota: Bool,
    learning: inout QuotaLearningCache,
    learningDirty: inout Bool,
    now: TimeInterval,
    isEn: Bool
) -> OfficialQuotaWindowEstimate {
    let expired = (parsed.resetsAtEpoch ?? 0) > 0 && now > (parsed.resetsAtEpoch ?? 0)
    let effectiveUsedPct = expired ? 0.0 : parsed.usedPercent
    let effectiveRemPct = expired ? 100.0 : parsed.remainingPercent
    let cycleStart: TimeInterval = {
        if let r = parsed.resetsAtEpoch, !expired { return r - parsed.windowSeconds }
        return now - parsed.windowSeconds
    }()

    let spend = computeLocalCycleSpend(hotFiles: hotFiles, family: family, windowStart: cycleStart, now: now)
    var resolvedFull: Double? = nil
    var confidence = "shared_disabled"
    var sampleCount = 0
    var remValue: Double? = nil

    if exclusiveQuota {
        var currentInferred: Double? = nil
        if !expired && effectiveUsedPct >= QuotaCalcBounds.minUsedPctForInference && spend.costUSD >= QuotaCalcBounds.minUsedCostUSDForInference {
            let inferred = spend.costUSD / (effectiveUsedPct / 100.0)
            currentInferred = inferred
            let cycleBucket = Int(((parsed.resetsAtEpoch ?? (now + parsed.windowSeconds)) / 3600.0).rounded())
            let cycleKey = "\(planTier.lowercased())|\(family)|\(kind)|\(cycleBucket)"
            let sample = AutoQuotaSample(
                planTier: planTier, family: family, windowKind: kind, cycleKey: cycleKey,
                recordedAt: now, usedPercent: effectiveUsedPct, usedCostUSD: spend.costUSD, inferredFullUSD: inferred
            )
            if let idx = learning.samples.firstIndex(where: { $0.cycleKey == cycleKey }) {
                if effectiveUsedPct >= learning.samples[idx].usedPercent {
                    learning.samples[idx] = sample
                    learningDirty = true
                }
            } else {
                learning.samples.append(sample)
                if learning.samples.count > QuotaCalcBounds.maxStoredSamples {
                    learning.samples.sort { $0.recordedAt > $1.recordedAt }
                    learning.samples = Array(learning.samples.prefix(QuotaCalcBounds.maxStoredSamples))
                }
                learningDirty = true
            }
        }

        let learned = inferWeightedMedianFullQuota(
            samples: learning.samples, planTier: planTier, family: family, windowKind: kind,
            maxSamples: QuotaCalcBounds.maxWindowSamplesForMedian
        )
        resolvedFull = learned.value ?? currentInferred
        confidence = resolvedFull == nil ? "insufficient" : (currentInferred != nil ? "current" : "learned")
        sampleCount = max(learned.count, currentInferred != nil ? 1 : 0)
        remValue = resolvedFull.map { max(0.0, $0 * (effectiveRemPct / 100.0)) }
    }
    let label = kind == "5h" ? (isEn ? "5-Hour Window" : "5 小时窗口") : (isEn ? "Weekly Cap" : "7 天周额度")

    return OfficialQuotaWindowEstimate(
        windowKind: kind, label: label, family: family, familyLabel: quotaFamilyLabel(family, isEn: isEn),
        usedPercent: effectiveUsedPct, remainingPercent: effectiveRemPct,
        resetsAtEpoch: parsed.resetsAtEpoch, resetLabel: formatResetCountdown(resetsAt: parsed.resetsAtEpoch, now: now, isEn: isEn),
        expired: expired, usedInQuotaUSD: spend.costUSD, usedInQuotaSavedUSD: spend.savedUSD,
        usedInQuotaTotalTokens: spend.totalTokens, usedInQuotaNetTokens: spend.netTokens,
        fullQuotaUSD: resolvedFull, fullQuotaConfidence: confidence,
        sampleCount: sampleCount, remainingValueUSD: remValue
    )
}

func evaluateOfficialQuota(
    dataDir: String,
    hotFiles: [CachedTranscriptFile],
    exclusiveQuota: Bool = false,
    now: TimeInterval,
    isEn: Bool
) -> OfficialQuotaSummary {
    let hookStatus = inspectStatusLineHookStatus()
    func emptySummary(plan: String = "", obs: TimeInterval = 0) -> OfficialQuotaSummary {
        OfficialQuotaSummary(
            available: false, exclusiveQuota: exclusiveQuota, sourceLabel: "", planTier: plan, observedAt: obs,
            observedLabel: obs > 0 ? formatRelativeUpdated(obs, now: now, isEn: isEn) : "",
            activeFamily: "gemini", activeFamilyLabel: quotaFamilyLabel("gemini", isEn: isEn),
            window5h: nil, windowWeekly: nil, monthlyFullQuotaUSD: nil, otherGroups: [], hookStatus: hookStatus
        )
    }

    guard let loaded = loadFreshestOfficialQuota(dataDir: dataDir),
          let rawQuota = loaded.snapshot.quota, !rawQuota.isEmpty else {
        return emptySummary()
    }

    let snap = loaded.snapshot
    let observedEpoch = Double(snap.observed_at) / 1000.0
    var groups: [String: FamilyParsedBuckets] = [:]
    for key in rawQuota.keys.sorted() {
        guard let bucket = rawQuota[key] else { continue }
        let (fam, kind) = classifyAgyQuotaBucket(key: key, bucket: bucket)
        guard kind == "5h" || kind == "weekly" else { continue }
        let dur: TimeInterval = kind == "weekly" ? PulseConstants.sevenDaysSeconds : PulseConstants.fiveHoursSeconds
        guard let win = parseBucketToWindow(bucket, observedAtEpoch: observedEpoch, windowSeconds: dur) else { continue }
        var grp = groups[fam] ?? FamilyParsedBuckets()
        if kind == "5h" {
            if grp.w5h == nil || win.usedPercent > grp.w5h!.usedPercent { grp.w5h = win }
        } else if grp.weekly == nil || win.usedPercent > grp.weekly!.usedPercent {
            grp.weekly = win
        }
        groups[fam] = grp
    }

    guard !groups.isEmpty else { return emptySummary(plan: snap.plan_tier ?? "", obs: observedEpoch) }

    let modelHint = ((snap.model_id ?? "") + " " + (snap.model_name ?? "")).lowercased()
    let preferred = (modelHint.contains("claude") || modelHint.contains("gpt")) ? "claude_gpt" : "gemini"
    let chosenFam = groups[preferred] != nil ? preferred : (["gemini", "claude_gpt", "default"].first { groups[$0] != nil } ?? groups.keys.sorted().first!)
    let chosen = groups[chosenFam]!
    let planTier = (snap.plan_tier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    var learning = exclusiveQuota ? loadLearningCache(dataDir: dataDir) : QuotaLearningCache(samples: [])
    var learningDirty = false
    let est5h = chosen.w5h.map {
        buildWindowEstimate(parsed: $0, kind: "5h", family: chosenFam, planTier: planTier, hotFiles: hotFiles, exclusiveQuota: exclusiveQuota, learning: &learning, learningDirty: &learningDirty, now: now, isEn: isEn)
    }
    let estWeekly = chosen.weekly.map {
        buildWindowEstimate(parsed: $0, kind: "weekly", family: chosenFam, planTier: planTier, hotFiles: hotFiles, exclusiveQuota: exclusiveQuota, learning: &learning, learningDirty: &learningDirty, now: now, isEn: isEn)
    }
    if exclusiveQuota && learningDirty { saveLearningCache(dataDir: dataDir, cache: learning) }

    var others: [OfficialQuotaGroupBrief] = []
    for fam in ["gemini", "claude_gpt", "default"] where fam != chosenFam {
        if let g = groups[fam] {
            let r5 = g.w5h.map { (($0.resetsAtEpoch ?? 0) > 0 && now > ($0.resetsAtEpoch ?? 0)) ? 100.0 : $0.remainingPercent }
            let rw = g.weekly.map { (($0.resetsAtEpoch ?? 0) > 0 && now > ($0.resetsAtEpoch ?? 0)) ? 100.0 : $0.remainingPercent }
            others.append(OfficialQuotaGroupBrief(family: fam, familyLabel: quotaFamilyLabel(fam, isEn: isEn), remaining5hPct: r5, remainingWeeklyPct: rw))
        }
    }

    let modeTagZh = exclusiveQuota ? "本机独享 · 已启用满额推算" : "账号共享 · 仅统计本机消耗"
    let modeTagEn = exclusiveQuota ? "Exclusive Device · Full Quota Inferred" : "Shared Account · Local Spend Only"
    let srcLabel = loaded.sourceTag == "ai-audit"
        ? (isEn ? "Official statusLine · ai-audit (\(modeTagEn))" : "官方 statusLine · ai-audit（\(modeTagZh)）")
        : (isEn ? "Official statusLine (\(modeTagEn))" : "官方 statusLine（\(modeTagZh)）")
    let monthlyFull = exclusiveQuota ? estWeekly?.fullQuotaUSD.map { $0 * QuotaCalcBounds.weeksPerMonth } : nil

    return OfficialQuotaSummary(
        available: est5h != nil || estWeekly != nil, exclusiveQuota: exclusiveQuota, sourceLabel: srcLabel, planTier: planTier,
        observedAt: observedEpoch, observedLabel: formatRelativeUpdated(observedEpoch, now: now, isEn: isEn),
        activeFamily: chosenFam, activeFamilyLabel: quotaFamilyLabel(chosenFam, isEn: isEn),
        window5h: est5h, windowWeekly: estWeekly, monthlyFullQuotaUSD: monthlyFull,
        otherGroups: others, hookStatus: hookStatus
    )
}
