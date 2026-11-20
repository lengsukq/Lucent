import Foundation
import LucentFoundation

public struct SearchAffinityItemRecord: Codable, Sendable, Equatable {
    public var key: String
    public var clickCount: Int
    public var lastClickedAtEpoch: Double

    public init(key: String, clickCount: Int = 0, lastClickedAtEpoch: Double = 0) {
        self.key = key
        self.clickCount = max(0, clickCount)
        self.lastClickedAtEpoch = max(0, lastClickedAtEpoch)
    }
}

public struct QueryAffinityEntry: Codable, Sendable, Equatable {
    public var clickCount: Int
    public var lastClickedAtEpoch: Double

    public init(clickCount: Int = 0, lastClickedAtEpoch: Double = 0) {
        self.clickCount = max(0, clickCount)
        self.lastClickedAtEpoch = max(0, lastClickedAtEpoch)
    }
}

public struct SearchAffinityState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var items: [String: SearchAffinityItemRecord]
    public var queryAffinities: [String: [String: QueryAffinityEntry]]

    public init(
        schemaVersion: Int = 1,
        items: [String: SearchAffinityItemRecord] = [:],
        queryAffinities: [String: [String: QueryAffinityEntry]] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.queryAffinities = queryAffinities
    }
}

public final class SearchAffinityStore: @unchecked Sendable {
    public static let shared = SearchAffinityStore()
    public static let fileName = "search-affinity.json"
    public static let maxTrackedItems = 600
    public static let maxTrackedQueries = 300
    public static let maxCandidatesPerQuery = 8
    public static let maxQueryLength = 48
    public static let halfLifeHours: Double = 168.0
    public static let maxGlobalBoost = 520
    public static let maxExactQueryBoost = 1_850
    public static let maxPrefixQueryBoost = 950
    public static let maxTotalBoost = 2_200

    private let lock = NSLock()
    private let ioLock = NSLock()
    private let storageURL: URL
    private let debounceNanoseconds: UInt64
    private var state: SearchAffinityState
    private var pendingSaveTask: Task<Void, Never>?
    private var isDirty = false

    public static func defaultStorageURL(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        LucentAppPaths.configFileURL(fileName, in: appSupportDirectory)
    }

    public init(
        storageURL: URL = SearchAffinityStore.defaultStorageURL(),
        debounceNanoseconds: UInt64 = 1_200_000_000
    ) {
        self.storageURL = storageURL
        self.debounceNanoseconds = debounceNanoseconds
        self.state = AtomicJSONStore.load(SearchAffinityState.self, from: storageURL, fallback: SearchAffinityState())
    }

    public var learnedItemCount: Int { lock.withLock { state.items.count } }
    public var learnedQueryCount: Int { lock.withLock { state.queryAffinities.count } }

    public static func affinityKey(for candidate: LauncherCandidate) -> String? {
        switch candidate.kind {
        case .app(let app): return "app:\(app.id)"
        case .plugin(let plugin): return "plugin:\(plugin.id)"
        case .pluginCommand(let cmd): return "plugcmd:\(cmd.id)"
        case .pluginItem(let entry): return "plugitem:\(entry.id)"
        case .script(let match): return "script:\(match.script.id)"
        case .snippet(let match): return "snippet:\(match.snippet.id.uuidString)"
        case .fileHit(let hit): return "file:\(hit.url.standardizedFileURL.path)"
        case .command(let cmd):
            let id = cmd.id
            if id.hasPrefix("web:") || id.hasPrefix("port:") || id.hasPrefix("path:") { return nil }
            return "cmd:\(id)"
        case .calculator, .devTool, .clipboard:
            return nil
        }
    }

    public static func normalizeQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= maxQueryLength else { return nil }
        return trimmed
    }

    public func recordSelection(candidate: LauncherCandidate, query: String, now: Date = Date()) {
        guard let key = Self.affinityKey(for: candidate) else { return }
        recordSelection(key: key, query: query, now: now)
    }

    public func recordSelection(key: String, query: String, now: Date = Date()) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let epoch = now.timeIntervalSince1970
        let normalizedQuery = Self.normalizeQuery(query)

        lock.withLock {
            var item = state.items[trimmedKey] ?? SearchAffinityItemRecord(key: trimmedKey)
            item.clickCount += 1
            item.lastClickedAtEpoch = max(item.lastClickedAtEpoch, epoch)
            state.items[trimmedKey] = item

            if let q = normalizedQuery {
                var bucket = state.queryAffinities[q] ?? [:]
                var entry = bucket[trimmedKey] ?? QueryAffinityEntry()
                entry.clickCount += 1
                entry.lastClickedAtEpoch = max(entry.lastClickedAtEpoch, epoch)
                bucket[trimmedKey] = entry
                if bucket.count > Self.maxCandidatesPerQuery {
                    let keep = bucket.sorted { lhs, rhs in
                        lhs.value.clickCount != rhs.value.clickCount
                            ? lhs.value.clickCount > rhs.value.clickCount
                            : lhs.value.lastClickedAtEpoch > rhs.value.lastClickedAtEpoch
                    }.prefix(Self.maxCandidatesPerQuery)
                    bucket = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
                }
                state.queryAffinities[q] = bucket
            }
            pruneCapsLocked()
            scheduleSaveLocked()
        }
    }

    public func clickCount(for candidate: LauncherCandidate) -> Int {
        guard let key = Self.affinityKey(for: candidate) else { return 0 }
        return lock.withLock { state.items[key]?.clickCount ?? 0 }
    }

    public func boosts(forQuery rawQuery: String, now: Date = Date()) -> [String: Int] {
        let nowEpoch = now.timeIntervalSince1970
        let needle = Self.normalizeQuery(rawQuery)

        return lock.withLock {
            var out: [String: Int] = [:]
            out.reserveCapacity(state.items.count)
            for (key, rec) in state.items where rec.clickCount > 0 {
                let g = Self.globalScore(clicks: rec.clickCount, lastEpoch: rec.lastClickedAtEpoch, nowEpoch: nowEpoch)
                if g > 0 { out[key] = g }
            }
            guard let needle else { return out }

            var queryBonus: [String: Int] = [:]
            if let exactBucket = state.queryAffinities[needle] {
                for (key, entry) in exactBucket where entry.clickCount > 0 {
                    let score = Self.exactQueryScore(clicks: entry.clickCount, lastEpoch: entry.lastClickedAtEpoch, nowEpoch: nowEpoch)
                    if score > 0 { queryBonus[key] = score }
                }
            }
            for (histQuery, bucket) in state.queryAffinities where histQuery != needle && histQuery.hasPrefix(needle) {
                let prefixScale = 0.65 * (Double(needle.count) / Double(max(1, histQuery.count)))
                for (key, entry) in bucket where entry.clickCount > 0 {
                    let exactEquiv = Self.exactQueryScore(clicks: entry.clickCount, lastEpoch: entry.lastClickedAtEpoch, nowEpoch: nowEpoch)
                    let scaled = min(Self.maxPrefixQueryBoost, Int((Double(exactEquiv) * prefixScale).rounded()))
                    if scaled > (queryBonus[key] ?? 0) { queryBonus[key] = scaled }
                }
            }
            for (key, qBoost) in queryBonus {
                let combined = min(Self.maxTotalBoost, (out[key] ?? 0) + qBoost)
                if combined > 0 { out[key] = combined }
            }
            return out
        }
    }

    public static func applyBoosts(_ boosts: [String: Int], to candidates: [LauncherCandidate]) -> [LauncherCandidate] {
        guard !boosts.isEmpty else { return candidates }
        return candidates.map { candidate in
            guard let key = affinityKey(for: candidate), let delta = boosts[key], delta > 0 else { return candidate }
            return LauncherCandidate(id: candidate.id, score: candidate.score + delta, kind: candidate.kind)
        }
    }

    public func resetItem(for candidate: LauncherCandidate) {
        guard let key = Self.affinityKey(for: candidate) else { return }
        resetItem(key: key)
    }

    public func resetItem(key: String) {
        lock.withLock {
            state.items.removeValue(forKey: key)
            for q in Array(state.queryAffinities.keys) {
                state.queryAffinities[q]?.removeValue(forKey: key)
                if state.queryAffinities[q]?.isEmpty == true { state.queryAffinities.removeValue(forKey: q) }
            }
            scheduleSaveLocked()
        }
    }

    public func clearAll() {
        lock.withLock {
            state = SearchAffinityState()
            scheduleSaveLocked()
        }
    }

    public func flush() {
        ioLock.withLock {
            let snapshot: SearchAffinityState? = lock.withLock {
                pendingSaveTask?.cancel(); pendingSaveTask = nil
                guard isDirty else { return nil }
                isDirty = false
                return state
            }
            if let snapshot { _ = AtomicJSONStore.save(snapshot, to: storageURL) }
        }
    }

    public func discardPendingAndReloadFromDisk() {
        ioLock.withLock {
            lock.withLock {
                pendingSaveTask?.cancel(); pendingSaveTask = nil
                isDirty = false
                state = AtomicJSONStore.load(SearchAffinityState.self, from: storageURL, fallback: SearchAffinityState())
            }
        }
    }

    private func pruneCapsLocked() {
        if state.items.count > Self.maxTrackedItems {
            let keep = state.items.sorted { $0.value.lastClickedAtEpoch > $1.value.lastClickedAtEpoch }
                .prefix(Self.maxTrackedItems)
            state.items = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if state.queryAffinities.count > Self.maxTrackedQueries {
            let ranked = state.queryAffinities.sorted { lhs, rhs in
                (lhs.value.values.map(\.lastClickedAtEpoch).max() ?? 0) > (rhs.value.values.map(\.lastClickedAtEpoch).max() ?? 0)
            }.prefix(Self.maxTrackedQueries)
            state.queryAffinities = Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, $0.value) })
        }
    }

    private func scheduleSaveLocked() {
        isDirty = true
        pendingSaveTask?.cancel()
        let delay = debounceNanoseconds
        pendingSaveTask = Task.detached(priority: .utility) { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled, let self else { return }
            self.flush()
        }
    }

    private static func recencyFactor(lastEpoch: Double, nowEpoch: Double) -> Double {
        1.0 / (1.0 + max(0.0, (nowEpoch - lastEpoch) / 3600.0) / halfLifeHours)
    }

    private static func globalScore(clicks: Int, lastEpoch: Double, nowEpoch: Double) -> Int {
        let raw = log2(Double(clicks) + 1.0) * 110.0 + 95.0 * recencyFactor(lastEpoch: lastEpoch, nowEpoch: nowEpoch)
        return min(maxGlobalBoost, max(0, Int(raw.rounded())))
    }

    private static func exactQueryScore(clicks: Int, lastEpoch: Double, nowEpoch: Double) -> Int {
        let raw = log2(Double(clicks) + 1.0) * 560.0 + 380.0 * recencyFactor(lastEpoch: lastEpoch, nowEpoch: nowEpoch)
        return min(maxExactQueryBoost, max(0, Int(raw.rounded())))
    }
}
