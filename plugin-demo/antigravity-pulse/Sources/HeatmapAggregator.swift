import Foundation

struct DailyAggregateBucket {
    var inputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var outputTokens: Int = 0
    var turns: Int = 0
    var sessions: Set<String> = []
    var costUSD: Double = 0.0
    var savedUSD: Double = 0.0
    var timedOut: Int = 0
    var timedDur: Double = 0.0

    var netTokens: Int { inputTokens + outputTokens }
    var totalTokens: Int { inputTokens + cacheReadTokens + outputTokens }
}

private func quartileCutoffs(positiveValues: [Double]) -> [Double] {
    guard !positiveValues.isEmpty else { return [1, 2, 3, 4] }
    let sorted = positiveValues.sorted()
    func pct(_ p: Double) -> Double {
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[idx]
    }
    let q1 = max(0.0001, pct(0.25))
    let q2 = max(q1 * 1.01, pct(0.50))
    let q3 = max(q2 * 1.01, pct(0.75))
    let q4 = max(q3 * 1.01, pct(0.90))
    return [roundMetric(q1, places: 100), roundMetric(q2, places: 100), roundMetric(q3, places: 100), roundMetric(q4, places: 100)]
}

private func levelForValue(_ value: Double, cutoffs: [Double]) -> Int {
    guard value > 0, cutoffs.count == 4 else { return 0 }
    if value < cutoffs[0] { return 1 }
    if value < cutoffs[1] { return 2 }
    if value < cutoffs[2] { return 3 }
    return 4
}

func buildHeatmapAndStreaks(
    dailyMap: [String: DailyAggregateBucket],
    now: Date
) -> (startDate: String, endDate: String, days: [HeatmapDayPoint], thresholds: HeatmapThresholds, streaks: StreakStats) {
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: now)
    let todayKey = localDateKey(for: todayStart)
    let todayWeekday = cal.component(.weekday, from: todayStart) - 1 // 0=Sun ... 6=Sat
    let daysBackToGridStart = 52 * 7 + todayWeekday
    guard let gridStart = cal.date(byAdding: .day, value: -daysBackToGridStart, to: todayStart) else {
        return (todayKey, todayKey, [], HeatmapThresholds(total: [1, 2, 3, 4], net: [1, 2, 3, 4], cost: [1, 2, 3, 4], turns: [1, 2, 3, 4]),
                StreakStats(currentStreakDays: 0, longestStreakDays: 0, activeDaysYear: 0, totalTokensYear: 0, netTokensYear: 0, avgDailyTotalTokens: 0, avgDailyNetTokens: 0, peakDate: nil, peakTotalTokens: 0, peakNetTokens: 0))
    }

    let startKey = localDateKey(for: gridStart)
    let totalDays = daysBackToGridStart + 1
    var keysAndDays: [(key: String, agg: DailyAggregateBucket)] = []
    keysAndDays.reserveCapacity(totalDays)

    var posTotal: [Double] = []
    var posNet: [Double] = []
    var posCost: [Double] = []
    var posTurns: [Double] = []

    for offset in 0..<totalDays {
        guard let d = cal.date(byAdding: .day, value: offset, to: gridStart) else { continue }
        let key = localDateKey(for: d)
        let agg = dailyMap[key] ?? DailyAggregateBucket()
        keysAndDays.append((key, agg))
        if agg.totalTokens > 0 {
            posTotal.append(Double(agg.totalTokens))
            posNet.append(Double(agg.netTokens))
            posCost.append(agg.costUSD)
            posTurns.append(Double(agg.turns))
        }
    }

    let cutTotal = quartileCutoffs(positiveValues: posTotal)
    let cutNet = quartileCutoffs(positiveValues: posNet)
    let cutCost = quartileCutoffs(positiveValues: posCost)
    let cutTurns = quartileCutoffs(positiveValues: posTurns)

    var activePoints: [HeatmapDayPoint] = []
    var activeDaysYear = 0
    var totalTokensYear = 0
    var netTokensYear = 0
    var peakDate: String? = nil
    var peakTotal = 0
    var peakNet = 0
    var longestStreak = 0
    var runningStreak = 0

    for item in keysAndDays {
        let a = item.agg
        if a.totalTokens > 0 {
            activeDaysYear += 1
            totalTokensYear += a.totalTokens
            netTokensYear += a.netTokens
            runningStreak += 1
            if runningStreak > longestStreak { longestStreak = runningStreak }
            if a.totalTokens > peakTotal {
                peakTotal = a.totalTokens
                peakNet = a.netTokens
                peakDate = item.key
            }

            let prompt = a.inputTokens + a.cacheReadTokens
            let hitRate = prompt > 0 ? Double(a.cacheReadTokens) / Double(prompt) : 0.0
            let avgTps: Double? = a.timedDur > 0 ? Double(a.timedOut) / a.timedDur : nil
            activePoints.append(HeatmapDayPoint(
                d: item.key,
                t: a.totalTokens,
                n: a.netTokens,
                i: a.inputTokens,
                c: a.cacheReadTokens,
                o: a.outputTokens,
                r: a.turns,
                s: a.sessions.count,
                u: roundMetric(a.costUSD, places: 100),
                v: roundMetric(a.savedUSD, places: 100),
                h: roundMetric(hitRate, places: 1000),
                p: roundOptionalMetric(avgTps, places: 10),
                lv: [
                    levelForValue(Double(a.totalTokens), cutoffs: cutTotal),
                    levelForValue(Double(a.netTokens), cutoffs: cutNet),
                    levelForValue(a.costUSD, cutoffs: cutCost),
                    levelForValue(Double(a.turns), cutoffs: cutTurns)
                ]
            ))
        } else {
            runningStreak = 0
        }
    }

    var currentStreak = 0
    var idx = keysAndDays.count - 1
    if idx >= 0 && keysAndDays[idx].agg.totalTokens == 0 {
        idx -= 1
    }
    while idx >= 0 && keysAndDays[idx].agg.totalTokens > 0 {
        currentStreak += 1
        idx -= 1
    }

    let denom = max(1, activeDaysYear)
    let streaks = StreakStats(
        currentStreakDays: currentStreak,
        longestStreakDays: longestStreak,
        activeDaysYear: activeDaysYear,
        totalTokensYear: totalTokensYear,
        netTokensYear: netTokensYear,
        avgDailyTotalTokens: activeDaysYear > 0 ? totalTokensYear / denom : 0,
        avgDailyNetTokens: activeDaysYear > 0 ? netTokensYear / denom : 0,
        peakDate: peakDate,
        peakTotalTokens: peakTotal,
        peakNetTokens: peakNet
    )
    return (startKey, todayKey, activePoints, HeatmapThresholds(total: cutTotal, net: cutNet, cost: cutCost, turns: cutTurns), streaks)
}

func buildTrendSeries(
    dailyMap: [String: DailyAggregateBucket],
    rangeKey: String,
    now: Date
) -> (granularity: String, points: [DailyTrendPoint]) {
    let cal = Calendar.current
    let todayStart = cal.startOfDay(for: now)

    let spanDays: Int
    switch rangeKey {
    case "today": spanDays = 1
    case "7d": spanDays = 7
    case "30d": spanDays = 30
    case "90d": spanDays = 90
    default: spanDays = 365
    }

    if spanDays <= 90 {
        var pts: [DailyTrendPoint] = []
        pts.reserveCapacity(spanDays)
        for offset in stride(from: -(spanDays - 1), through: 0, by: 1) {
            guard let d = cal.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let key = localDateKey(for: d)
            let a = dailyMap[key] ?? DailyAggregateBucket()
            let comps = cal.dateComponents([.month, .day], from: d)
            let label = String(format: "%02d/%02d", comps.month ?? 1, comps.day ?? 1)
            let tps: Double? = a.timedDur > 0 ? Double(a.timedOut) / a.timedDur : nil
            pts.append(DailyTrendPoint(
                key: key, label: label, inputTokens: a.inputTokens, cacheReadTokens: a.cacheReadTokens,
                outputTokens: a.outputTokens, netTokens: a.netTokens, totalTokens: a.totalTokens,
                estimatedCostUSD: roundMetric(a.costUSD, places: 100),
                estimatedSavedUSD: roundMetric(a.savedUSD, places: 100),
                turns: a.turns, avgTokensPerSec: roundOptionalMetric(tps, places: 10)
            ))
        }
        return ("day", pts)
    }

    var weekOrder: [String] = []
    var weekBuckets: [String: (label: String, agg: DailyAggregateBucket)] = [:]
    let allSortedKeys = dailyMap.keys.sorted()
    let startDate: Date = {
        if rangeKey == "all", let firstKey = allSortedKeys.first, let parsed = parseDateKey(firstKey) {
            return parsed
        }
        return cal.date(byAdding: .day, value: -364, to: todayStart) ?? todayStart
    }()

    var cursor = startDate
    while cursor <= todayStart {
        let wd = cal.component(.weekday, from: cursor)
        let deltaToMon = wd == 1 ? -6 : (2 - wd)
        let weekStart = cal.date(byAdding: .day, value: deltaToMon, to: cursor) ?? cursor
        let wkKey = localDateKey(for: weekStart)
        let dayKey = localDateKey(for: cursor)

        if weekBuckets[wkKey] == nil {
            let comps = cal.dateComponents([.month, .day], from: weekStart)
            let lbl = String(format: "%02d/%02d", comps.month ?? 1, comps.day ?? 1)
            weekBuckets[wkKey] = (lbl, DailyAggregateBucket())
            weekOrder.append(wkKey)
        }
        if let a = dailyMap[dayKey], var cur = weekBuckets[wkKey] {
            cur.agg.inputTokens += a.inputTokens
            cur.agg.cacheReadTokens += a.cacheReadTokens
            cur.agg.outputTokens += a.outputTokens
            cur.agg.turns += a.turns
            cur.agg.costUSD += a.costUSD
            cur.agg.savedUSD += a.savedUSD
            cur.agg.timedOut += a.timedOut
            cur.agg.timedDur += a.timedDur
            weekBuckets[wkKey] = cur
        }
        guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }

    let pts = weekOrder.compactMap { wkKey -> DailyTrendPoint? in
        guard let item = weekBuckets[wkKey] else { return nil }
        let a = item.agg
        let tps: Double? = a.timedDur > 0 ? Double(a.timedOut) / a.timedDur : nil
        return DailyTrendPoint(
            key: wkKey, label: item.label, inputTokens: a.inputTokens, cacheReadTokens: a.cacheReadTokens,
            outputTokens: a.outputTokens, netTokens: a.netTokens, totalTokens: a.totalTokens,
            estimatedCostUSD: roundMetric(a.costUSD, places: 100),
            estimatedSavedUSD: roundMetric(a.savedUSD, places: 100),
            turns: a.turns, avgTokensPerSec: roundOptionalMetric(tps, places: 10)
        )
    }
    return ("week", pts)
}

func parseDateKey(_ key: String) -> Date? {
    let parts = key.split(separator: "-")
    guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    var comps = DateComponents()
    comps.year = y; comps.month = m; comps.day = d
    return Calendar.current.date(from: comps)
}
