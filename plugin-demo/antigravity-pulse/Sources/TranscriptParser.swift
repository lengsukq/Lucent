import Darwin
import Foundation

struct DiscoveredTranscript {
    let path: String
    let sessionId: String
    let source: String
    let fileSize: Int64
    let mtimeEpoch: TimeInterval
}

private struct RawPlannerLine: Decodable {
    let type: String?
    let step_index: Int?
    let created_at: String?
    let model: String?
    let input_tokens: Int?
    let cache_read_tokens: Int?
    let output_tokens: Int?
}

private struct RawUserInputLine: Decodable {
    let type: String?
    let content: String?
}

private struct RawTailEventLine: Decodable {
    let type: String?
    let status: String?
    let created_at: String?
    let tool_calls: [EmptyDecodable]?
}

private struct EmptyDecodable: Decodable {}

private func parseAsciiInt(_ bytes: UnsafeBufferPointer<UInt8>, start: Int, count: Int) -> Int? {
    guard start >= 0, start + count <= bytes.count else { return nil }
    var val = 0
    for i in start..<(start + count) {
        let ch = bytes[i]
        guard ch >= 48 && ch <= 57 else { return nil }
        val = val * 10 + Int(ch - 48)
    }
    return val
}

private func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
    let y = Int64(year - (month <= 2 ? 1 : 0))
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let m = Int64(month)
    let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + Int64(day) - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}

func parseISO8601Epoch(_ raw: String) -> TimeInterval? {
    let utf8 = Array(raw.utf8)
    guard utf8.count >= 20 else { return nil }
    return utf8.withUnsafeBufferPointer { buf in
        guard let year = parseAsciiInt(buf, start: 0, count: 4),
              buf[4] == 45,
              let month = parseAsciiInt(buf, start: 5, count: 2),
              buf[7] == 45,
              let day = parseAsciiInt(buf, start: 8, count: 2),
              (buf[10] == 84 || buf[10] == 32),
              let hour = parseAsciiInt(buf, start: 11, count: 2),
              buf[13] == 58,
              let minute = parseAsciiInt(buf, start: 14, count: 2),
              buf[16] == 58,
              let second = parseAsciiInt(buf, start: 17, count: 2) else { return nil }

        var idx = 19
        var fracSeconds = 0.0
        if idx < buf.count && buf[idx] == 46 {
            idx += 1
            var scale = 0.1
            while idx < buf.count && buf[idx] >= 48 && buf[idx] <= 57 {
                fracSeconds += Double(buf[idx] - 48) * scale
                scale *= 0.1
                idx += 1
            }
        }

        var tzOffsetSec = 0
        if idx < buf.count {
            let marker = buf[idx]
            if marker == 90 || marker == 122 {
                tzOffsetSec = 0
            } else if (marker == 43 || marker == 45), idx + 6 <= buf.count, buf[idx + 3] == 58,
                      let tzH = parseAsciiInt(buf, start: idx + 1, count: 2),
                      let tzM = parseAsciiInt(buf, start: idx + 4, count: 2) {
                tzOffsetSec = (marker == 43 ? 1 : -1) * (tzH * 3600 + tzM * 60)
            }
        }

        let days = daysFromCivil(year: year, month: month, day: day)
        return TimeInterval(days * 86_400 + Int64(hour * 3600 + minute * 60 + second - tzOffsetSec)) + fracSeconds
    }
}

private func sanitizeSessionTitle(_ raw: String) -> String {
    var text = raw
    if let s = text.range(of: "<USER_REQUEST>"), let e = text.range(of: "</USER_REQUEST>"), s.upperBound <= e.lowerBound {
        text = String(text[s.upperBound..<e.lowerBound])
    }
    text = text.replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
    if text.isEmpty { return "" }
    return text.count <= 36 ? text : String(text.prefix(35)) + "…"
}

private func containsNeedle(haystack: UnsafeRawPointer, hayLen: Int, needle: [UInt8]) -> Bool {
    guard hayLen >= needle.count else { return false }
    return needle.withUnsafeBytes { buf in
        guard let base = buf.baseAddress else { return false }
        return memmem(haystack, hayLen, base, needle.count) != nil
    }
}

func parseTranscriptFile(_ item: DiscoveredTranscript) -> CachedTranscriptFile {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: item.path), options: [.mappedIfSafe]) else {
        return CachedTranscriptFile(
            sessionId: item.sessionId, source: item.source, title: "", fileSize: item.fileSize,
            mtimeEpoch: item.mtimeEpoch, lastEventType: "", lastEventStatus: "",
            lastEventHasToolCalls: false, lastEventTimestamp: item.mtimeEpoch, turns: []
        )
    }

    let plannerNeedle = Array("\"PLANNER_RESPONSE\"".utf8)
    let userNeedle = Array("\"USER_INPUT\"".utf8)
    let decoder = JSONDecoder()

    var title = ""
    var turnsByStep: [Int: CachedTurnRecord] = [:]
    var fallbackSeq = 0
    var lastLineStart = -1
    var lastLineLen = 0

    data.withUnsafeBytes { rawBuf in
        guard let basePtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        let totalLen = rawBuf.count
        var lineStart = 0

        while lineStart < totalLen {
            let lineEnd: Int
            if let nlPtr = memchr(basePtr + lineStart, 0x0A, totalLen - lineStart) {
                lineEnd = UnsafePointer<UInt8>(nlPtr.assumingMemoryBound(to: UInt8.self)) - basePtr
            } else {
                lineEnd = totalLen
            }

            let lineLen = lineEnd - lineStart
            if lineLen > 16 {
                lastLineStart = lineStart
                lastLineLen = lineLen
                let linePtr = UnsafeRawPointer(basePtr + lineStart)

                if title.isEmpty && containsNeedle(haystack: linePtr, hayLen: lineLen, needle: userNeedle) {
                    let slice = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: linePtr), count: lineLen, deallocator: .none)
                    if let u = try? decoder.decode(RawUserInputLine.self, from: slice), u.type == "USER_INPUT", let c = u.content {
                        let cleaned = sanitizeSessionTitle(c)
                        if !cleaned.isEmpty { title = cleaned }
                    }
                } else if containsNeedle(haystack: linePtr, hayLen: lineLen, needle: plannerNeedle) {
                    let slice = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: linePtr), count: lineLen, deallocator: .none)
                    if let p = try? decoder.decode(RawPlannerLine.self, from: slice), p.type == "PLANNER_RESPONSE" {
                        let inp = max(0, p.input_tokens ?? 0)
                        let cache = max(0, p.cache_read_tokens ?? 0)
                        let outp = max(0, p.output_tokens ?? 0)
                        if inp + cache + outp > 0 {
                            let step = p.step_index ?? fallbackSeq
                            fallbackSeq += 1
                            let ts = p.created_at.flatMap(parseISO8601Epoch) ?? item.mtimeEpoch
                            let rec = CachedTurnRecord(
                                stepIndex: step, timestamp: ts, model: p.model ?? "",
                                inputTokens: inp, cacheReadTokens: cache, outputTokens: outp
                            )
                            if let existing = turnsByStep[step] {
                                let oldTot = existing.inputTokens + existing.cacheReadTokens + existing.outputTokens
                                if inp + cache + outp >= oldTot { turnsByStep[step] = rec }
                            } else {
                                turnsByStep[step] = rec
                            }
                        }
                    }
                }
            }
            lineStart = lineEnd + 1
        }
    }

    var lastType = ""
    var lastStatus = ""
    var lastHasTools = false
    var lastTs = item.mtimeEpoch

    if lastLineStart >= 0 && lastLineLen > 2 {
        data.withUnsafeBytes { rawBuf in
            guard let basePtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let slice = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: basePtr + lastLineStart), count: lastLineLen, deallocator: .none)
            if let tail = try? decoder.decode(RawTailEventLine.self, from: slice) {
                lastType = tail.type ?? ""
                lastStatus = tail.status ?? ""
                lastHasTools = !(tail.tool_calls ?? []).isEmpty
                lastTs = tail.created_at.flatMap(parseISO8601Epoch) ?? item.mtimeEpoch
            }
        }
    }

    let sortedTurns = turnsByStep.values.sorted { lhs, rhs in
        lhs.stepIndex != rhs.stepIndex ? lhs.stepIndex < rhs.stepIndex : lhs.timestamp < rhs.timestamp
    }
    return CachedTranscriptFile(
        sessionId: item.sessionId, source: item.source, title: title, fileSize: item.fileSize,
        mtimeEpoch: item.mtimeEpoch, lastEventType: lastType, lastEventStatus: lastStatus,
        lastEventHasToolCalls: lastHasTools, lastEventTimestamp: lastTs, turns: sortedTurns
    )
}
