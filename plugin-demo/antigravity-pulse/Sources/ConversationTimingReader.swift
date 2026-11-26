import Darwin
import Foundation
import SQLite3

/// Reads sub-second step generation durations from Antigravity's local `conversations/<sessionId>.db` SQLite store.
private enum TimingBounds {
    static let plannerResponseStepType: Int32 = 15
    static let minValidEpochSeconds: Int64 = 1_000_000_000
    static let minDurationSeconds: Double = 0.05
    static let maxDurationSeconds: Double = 3600.0
}

private func conversationDBPath(sessionId: String, source: String) -> String {
    let home = pulseUserHomePath()
    let folder = source == "cli" ? "antigravity-cli" : "antigravity"
    return "\(home)/.gemini/\(folder)/conversations/\(sessionId).db"
}

private func fileMtimeEpoch(_ path: String) -> TimeInterval {
    var st = stat()
    guard stat(path, &st) == 0 else { return 0 }
    return TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
}

func conversationDBMtime(sessionId: String, source: String) -> TimeInterval {
    let dbPath = conversationDBPath(sessionId: sessionId, source: source)
    return max(fileMtimeEpoch(dbPath), fileMtimeEpoch(dbPath + "-wal"))
}

private func readVarint(_ bytes: UnsafeBufferPointer<UInt8>, index: inout Int) -> UInt64? {
    var value: UInt64 = 0
    var shift: UInt64 = 0
    while index < bytes.count {
        let byte = bytes[index]
        index += 1
        if shift >= 64 { return nil }
        value |= UInt64(byte & 0x7F) << shift
        if (byte & 0x80) == 0 { return value }
        shift += 7
    }
    return nil
}

private func skipProtobufField(_ bytes: UnsafeBufferPointer<UInt8>, wireType: UInt64, index: inout Int) -> Bool {
    switch wireType {
    case 0:
        return readVarint(bytes, index: &index) != nil
    case 1:
        guard index + 8 <= bytes.count else { return false }
        index += 8
        return true
    case 2:
        guard let len64 = readVarint(bytes, index: &index),
              len64 <= UInt64(bytes.count - index) else { return false }
        index += Int(len64)
        return true
    case 5:
        guard index + 4 <= bytes.count else { return false }
        index += 4
        return true
    default:
        return false
    }
}

private func readLengthSlice(_ bytes: UnsafeBufferPointer<UInt8>, index: inout Int) -> UnsafeBufferPointer<UInt8>? {
    guard let len64 = readVarint(bytes, index: &index),
          len64 <= UInt64(bytes.count - index),
          let base = bytes.baseAddress else { return nil }
    let slice = UnsafeBufferPointer(start: base + index, count: Int(len64))
    index += Int(len64)
    return slice
}

private func parseProtobufTimestamp(_ bytes: UnsafeBufferPointer<UInt8>) -> TimeInterval? {
    var idx = 0
    var seconds: Int64?
    var nanos: Int32 = 0
    while idx < bytes.count {
        guard let tag = readVarint(bytes, index: &idx) else { return nil }
        let fieldNo = tag >> 3
        let wireType = tag & 0x07
        if wireType == 0, let raw = readVarint(bytes, index: &idx) {
            if fieldNo == 1 { seconds = Int64(bitPattern: raw) }
            else if fieldNo == 2 { nanos = Int32(truncatingIfNeeded: raw) }
        } else if !skipProtobufField(bytes, wireType: wireType, index: &idx) {
            return nil
        }
    }
    guard let sec = seconds, sec >= TimingBounds.minValidEpochSeconds else { return nil }
    return TimeInterval(sec) + TimeInterval(nanos) / 1_000_000_000.0
}

private func parseModelUsageHasOutput(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    var idx = 0
    while idx < bytes.count {
        guard let tag = readVarint(bytes, index: &idx) else { return false }
        let fieldNo = tag >> 3
        let wireType = tag & 0x07
        if wireType == 0, let raw = readVarint(bytes, index: &idx) {
            if fieldNo == 3 && raw > 0 { return true }
        } else if !skipProtobufField(bytes, wireType: wireType, index: &idx) {
            return false
        }
    }
    return false
}

func parseStepMetadataDuration(_ bytes: UnsafeBufferPointer<UInt8>) -> Double? {
    var idx = 0
    var createdAt: TimeInterval?
    var fallbackEnd: TimeInterval?
    var completedAt: TimeInterval?
    var hasOutput = false

    while idx < bytes.count {
        guard let tag = readVarint(bytes, index: &idx) else { break }
        let fieldNo = tag >> 3
        let wireType = tag & 0x07
        if wireType == 2 {
            guard let sub = readLengthSlice(bytes, index: &idx) else { break }
            switch fieldNo {
            case 1: createdAt = parseProtobufTimestamp(sub)
            case 7: fallbackEnd = parseProtobufTimestamp(sub)
            case 8: completedAt = parseProtobufTimestamp(sub)
            case 9: hasOutput = parseModelUsageHasOutput(sub)
            default: break
            }
        } else if !skipProtobufField(bytes, wireType: wireType, index: &idx) {
            break
        }
    }

    guard hasOutput, let start = createdAt, let end = completedAt ?? fallbackEnd else { return nil }
    let dur = end - start
    guard dur >= TimingBounds.minDurationSeconds && dur <= TimingBounds.maxDurationSeconds else { return nil }
    return dur
}

private func queryDurations(openPath: String, openFlags: Int32) -> [Int: Double]? {
    var db: OpaquePointer?
    guard sqlite3_open_v2(openPath, &db, openFlags, nil) == SQLITE_OK, let handle = db else {
        if db != nil { sqlite3_close(db) }
        return nil
    }
    defer { sqlite3_close(handle) }
    sqlite3_busy_timeout(handle, 50)

    let sql = "SELECT idx, metadata FROM steps WHERE step_type = \(TimingBounds.plannerResponseStepType) AND metadata IS NOT NULL"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let query = stmt else {
        return nil
    }
    defer { sqlite3_finalize(query) }

    var durations: [Int: Double] = [:]
    while sqlite3_step(query) == SQLITE_ROW {
        let stepIdx = Int(sqlite3_column_int(query, 0))
        guard let blobPtr = sqlite3_column_blob(query, 1) else { continue }
        let byteCount = Int(sqlite3_column_bytes(query, 1))
        guard byteCount > 0 else { continue }
        let buf = UnsafeBufferPointer(start: blobPtr.assumingMemoryBound(to: UInt8.self), count: byteCount)
        if let dur = parseStepMetadataDuration(buf) {
            durations[stepIdx] = dur
        }
    }
    return durations
}

private func queryDurationsViaStagedCopy(dbPath: String) -> [Int: Double] {
    let fm = FileManager.default
    let scratch = fm.temporaryDirectory.appendingPathComponent("agp-db-\(UUID().uuidString)", isDirectory: true)
    guard (try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else { return [:] }
    defer { try? fm.removeItem(at: scratch) }

    let staged = scratch.appendingPathComponent("conv.db")
    guard (try? fm.copyItem(atPath: dbPath, toPath: staged.path)) != nil else { return [:] }
    for suffix in ["-wal", "-shm"] {
        if fm.fileExists(atPath: dbPath + suffix) {
            try? fm.copyItem(atPath: dbPath + suffix, toPath: staged.path + suffix)
        }
    }
    return queryDurations(openPath: staged.path, openFlags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX) ?? [:]
}

private func loadStepDurations(sessionId: String, source: String) -> (durations: [Int: Double], dbMtime: TimeInterval) {
    guard !sessionId.isEmpty, !sessionId.contains("/") else { return ([:], 0) }
    let dbPath = conversationDBPath(sessionId: sessionId, source: source)
    let dbMtime = conversationDBMtime(sessionId: sessionId, source: source)
    guard dbMtime > 0 else { return ([:], 0) }

    let fm = FileManager.default
    let hasWal = fm.fileExists(atPath: dbPath + "-wal")
    if !hasWal {
        let uri = URL(fileURLWithPath: dbPath).absoluteString + "?immutable=1"
        if let res = queryDurations(openPath: uri, openFlags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX) {
            return (res, dbMtime)
        }
    }
    if fm.fileExists(atPath: dbPath + "-shm"),
       let res = queryDurations(openPath: dbPath, openFlags: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX) {
        return (res, dbMtime)
    }
    return (queryDurationsViaStagedCopy(dbPath: dbPath), dbMtime)
}

func enrichTurnsWithDurations(_ file: CachedTranscriptFile) -> CachedTranscriptFile {
    let (durations, dbMtime) = loadStepDurations(sessionId: file.sessionId, source: file.source)
    guard dbMtime > 0 else { return file }
    let updatedTurns = file.turns.map { turn in
        let resolved = durations[turn.stepIndex] ?? turn.durationSeconds
        return CachedTurnRecord(
            stepIndex: turn.stepIndex,
            timestamp: turn.timestamp,
            model: turn.model,
            inputTokens: turn.inputTokens,
            cacheReadTokens: turn.cacheReadTokens,
            outputTokens: turn.outputTokens,
            durationSeconds: resolved
        )
    }
    return CachedTranscriptFile(
        sessionId: file.sessionId, source: file.source, title: file.title,
        fileSize: file.fileSize, mtimeEpoch: file.mtimeEpoch, dbMtimeEpoch: dbMtime,
        lastEventType: file.lastEventType, lastEventStatus: file.lastEventStatus,
        lastEventHasToolCalls: file.lastEventHasToolCalls,
        lastEventTimestamp: file.lastEventTimestamp, turns: updatedTurns
    )
}

func refreshTimingIfNeeded(_ cached: CachedTranscriptFile) -> (file: CachedTranscriptFile, updated: Bool) {
    let needsRefresh = cached.turns.contains { $0.outputTokens > 0 && $0.durationSeconds == nil }
    guard needsRefresh else { return (cached, false) }
    let currentMtime = conversationDBMtime(sessionId: cached.sessionId, source: cached.source)
    guard currentMtime > cached.dbMtimeEpoch + 0.001 else { return (cached, false) }
    return (enrichTurnsWithDurations(cached), true)
}
