import Darwin
import Foundation
import PluginKit

/// Fast local date-key (`YYYY-MM-DD`) and local hour (`0...23`) extraction using POSIX `localtime_r`.
func localDateKeyAndHour(for epoch: TimeInterval) -> (dateKey: String, hour: Int) {
    var t = time_t(epoch)
    var tmVal = tm()
    localtime_r(&t, &tmVal)
    let year = Int(tmVal.tm_year) + 1900
    let month = Int(tmVal.tm_mon) + 1
    let day = Int(tmVal.tm_mday)
    let hour = max(0, min(23, Int(tmVal.tm_hour)))
    let key = String(format: "%04d-%02d-%02d", year, month, day)
    return (key, hour)
}

func localDateKey(for date: Date) -> String {
    localDateKeyAndHour(for: date.timeIntervalSince1970).dateKey
}

private func archiveFileURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("usage-archive-cache.json")
}

private func loadArchiveCache(dataDir: String) -> UsageArchiveCache {
    guard let url = archiveFileURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(UsageArchiveCache.self, from: data),
          decoded.schemaVersion == PulseConstants.archiveSchemaVersion else {
        return UsageArchiveCache(schemaVersion: PulseConstants.archiveSchemaVersion, files: [:])
    }
    return decoded
}

private func saveArchiveCache(dataDir: String, cache: UsageArchiveCache) {
    guard let url = archiveFileURL(dataDir: dataDir) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(cache) {
        try? data.write(to: url, options: .atomic)
    }
}

private func summarizeTranscriptToArchive(_ file: CachedTranscriptFile) -> ArchivedFileUsage {
    var bucketMap: [String: DailyModelBucket] = [:]
    var modelTokenTotals: [String: Int] = [:]
    var hourlyTotal = [Int](repeating: 0, count: 24)
    var hourlyNet = [Int](repeating: 0, count: 24)
    var hourlyTurns = [Int](repeating: 0, count: 24)

    var totalIn = 0
    var totalCache = 0
    var totalOut = 0
    var timedOut = 0
    var timedDur = 0.0
    var firstTs = file.mtimeEpoch
    var lastTs = file.mtimeEpoch

    for (idx, turn) in file.turns.enumerated() {
        if idx == 0 {
            firstTs = turn.timestamp
            lastTs = turn.timestamp
        } else {
            if turn.timestamp < firstTs { firstTs = turn.timestamp }
            if turn.timestamp > lastTs { lastTs = turn.timestamp }
        }
        let (dKey, hour) = localDateKeyAndHour(for: turn.timestamp)
        let net = turn.inputTokens + turn.outputTokens
        let tot = net + turn.cacheReadTokens
        totalIn += turn.inputTokens
        totalCache += turn.cacheReadTokens
        totalOut += turn.outputTokens
        hourlyTotal[hour] += tot
        hourlyNet[hour] += net
        hourlyTurns[hour] += 1

        var dOut = 0
        var dSec = 0.0
        if let dur = turn.durationSeconds, dur > 0, turn.outputTokens > 0 {
            dOut = turn.outputTokens
            dSec = dur
            timedOut += dOut
            timedDur += dSec
        }

        let bKey = "\(dKey)\u{1F}\(turn.model)"
        if var existing = bucketMap[bKey] {
            existing.inputTokens += turn.inputTokens
            existing.cacheReadTokens += turn.cacheReadTokens
            existing.outputTokens += turn.outputTokens
            existing.turns += 1
            existing.timedOutputTokens += dOut
            existing.timedDurationSeconds += dSec
            bucketMap[bKey] = existing
        } else {
            bucketMap[bKey] = DailyModelBucket(
                dateKey: dKey,
                model: turn.model,
                inputTokens: turn.inputTokens,
                cacheReadTokens: turn.cacheReadTokens,
                outputTokens: turn.outputTokens,
                turns: 1,
                timedOutputTokens: dOut,
                timedDurationSeconds: dSec
            )
        }
        modelTokenTotals[turn.model, default: 0] += tot
    }

    let primaryModel = modelTokenTotals.max(by: { $0.value < $1.value })?.key ?? (file.turns.last?.model ?? "")
    let sortedBuckets = bucketMap.values.sorted { lhs, rhs in
        lhs.dateKey != rhs.dateKey ? lhs.dateKey < rhs.dateKey : lhs.model < rhs.model
    }
    let effectiveLast = max(lastTs, file.lastEventTimestamp)

    return ArchivedFileUsage(
        sessionId: file.sessionId,
        source: file.source,
        title: file.title,
        fileSize: file.fileSize,
        mtimeEpoch: file.mtimeEpoch,
        firstTimestamp: firstTs,
        lastTimestamp: effectiveLast,
        primaryModel: primaryModel,
        totalInputTokens: totalIn,
        totalCacheReadTokens: totalCache,
        totalOutputTokens: totalOut,
        turnCount: file.turns.count,
        timedOutputTokens: timedOut,
        timedDurationSeconds: timedDur,
        hourlyTokens: hourlyTotal,
        hourlyNetTokens: hourlyNet,
        hourlyTurns: hourlyTurns,
        buckets: sortedBuckets
    )
}

func loadOrUpdateUsageArchive(
    includeCliLogs: Bool,
    dataDir: String,
    hotCacheFiles: [String: CachedTranscriptFile] = [:],
    input: PluginInput? = nil
) -> (cache: UsageArchiveCache, parsedNow: Int) {
    let discovered = discoverTranscripts(includeCliLogs: includeCliLogs)
    var archive = loadArchiveCache(dataDir: dataDir)
    var dirty = false
    var parsedNow = 0
    var activePaths = Set<String>()

    var pending: [DiscoveredTranscript] = []
    for item in discovered {
        activePaths.insert(item.path)
        if let existing = archive.files[item.path],
           existing.fileSize == item.fileSize,
           abs(existing.mtimeEpoch - item.mtimeEpoch) < 0.001 {
            // Upgrade timing if hot cache now has durations missing in cold archive.
            if existing.timedDurationSeconds == 0,
               let hot = hotCacheFiles[item.path],
               hot.fileSize == item.fileSize,
               hot.turns.contains(where: { ($0.durationSeconds ?? 0) > 0 }) {
                archive.files[item.path] = summarizeTranscriptToArchive(hot)
                dirty = true
            }
            continue
        }
        pending.append(item)
    }

    let bridge = input.map { HostBridgeClient(input: $0, timeoutSeconds: 1) }
    let reportProgress = pending.count >= 25 && (bridge?.isAvailable == true)
    let isEn = input?.isEnglish ?? false

    for (idx, item) in pending.enumerated() {
        if reportProgress && (idx == 0 || idx % 40 == 0) {
            let frac = Double(idx) / Double(max(1, pending.count))
            let msg = isEn
                ? "Indexing usage history (\(idx)/\(pending.count))…"
                : "正在索引历史会话用量（\(idx)/\(pending.count)）…"
            bridge?.reportProgress(message: msg, fraction: frac)
        }
        if let hot = hotCacheFiles[item.path],
           hot.fileSize == item.fileSize,
           abs(hot.mtimeEpoch - item.mtimeEpoch) < 0.001 {
            archive.files[item.path] = summarizeTranscriptToArchive(hot)
        } else {
            let parsed = parseTranscriptFile(item)
            archive.files[item.path] = summarizeTranscriptToArchive(parsed)
        }
        parsedNow += 1
        dirty = true
    }

    for key in archive.files.keys where !activePaths.contains(key) {
        archive.files.removeValue(forKey: key)
        dirty = true
    }

    if dirty {
        saveArchiveCache(dataDir: dataDir, cache: archive)
    }
    return (archive, parsedNow)
}

// MARK: - Dashboard Preferences Store

private func prefsFileURL(dataDir: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("dashboard-prefs.json")
}

func loadDashboardPrefs(dataDir: String, input: PluginInput) -> DashboardPrefs {
    let defaultCurrency = input.cfgString("currency", default: "USD").uppercased() == "CNY" ? "CNY" : "USD"
    let defaultRate = input.cfgDouble("usdToCnyRate", default: 7.25, min: 1.0, max: 20.0)
    guard let url = prefsFileURL(dataDir: dataDir),
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(DashboardPrefs.self, from: data) else {
        return DashboardPrefs(currency: defaultCurrency, usdToCnyRate: defaultRate)
    }
    let cleanCur = decoded.currency.uppercased() == "CNY" ? "CNY" : "USD"
    let cleanRate = min(20.0, max(1.0, decoded.usdToCnyRate.isFinite ? decoded.usdToCnyRate : defaultRate))
    return DashboardPrefs(currency: cleanCur, usdToCnyRate: cleanRate, exclusiveQuota: decoded.exclusiveQuota)
}

func saveDashboardPrefs(dataDir: String, prefs: DashboardPrefs) {
    guard let url = prefsFileURL(dataDir: dataDir) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(prefs) {
        try? data.write(to: url, options: .atomic)
    }
}
