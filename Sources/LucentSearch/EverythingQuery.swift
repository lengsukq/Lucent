import Foundation
import LucentFoundation

public struct QueryNeedle: Sendable {
    public let rawLowercased: String
    public let utf8Bytes: [UInt8]
    public let isPureASCII: Bool
    public let isPureASCIIAlnum: Bool

    public init(_ lowercased: String) {
        self.rawLowercased = lowercased
        let bytes = Array(lowercased.utf8)
        self.utf8Bytes = bytes
        let ascii = bytes.allSatisfy { $0 < 0x80 }
        self.isPureASCII = ascii
        self.isPureASCIIAlnum = ascii && bytes.count >= 2 && bytes.allSatisfy {
            ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39)
        }
    }

    public func matches(in haystack: String, allowPinyin: Bool = false) -> Bool {
        matchRank(in: haystack, allowPinyin: allowPinyin) > 0
    }

    public func matchRank(in haystack: String, allowPinyin: Bool = false) -> Int {
        let m = utf8Bytes.count
        guard m > 0 else { return 1 }
        var copy = haystack
        var haystackHasNonASCII = false
        let asciiResult: Int? = copy.withUTF8 { buf in
            if let offset = Self.findASCIICaseInsensitiveOffset(buf, needle: utf8Bytes) {
                if offset == 0 {
                    if buf.count == m { return 4 }
                    return buf[m] == 0x2E ? 3 : 2
                }
                return 1
            }
            for b in buf where b >= 0x80 {
                haystackHasNonASCII = true
                break
            }
            return nil
        }
        if let asciiResult { return asciiResult }

        if !isPureASCII || haystackHasNonASCII {
            if let range = haystack.localizedStandardRange(of: rawLowercased) {
                if range.lowerBound == haystack.startIndex {
                    if range.upperBound == haystack.endIndex { return 4 }
                    return haystack[range.upperBound] == "." ? 3 : 2
                }
                return 1
            }
        }

        if allowPinyin && isPureASCIIAlnum && haystackHasNonASCII {
            return PinyinHelper.matchRank(asciiNeedle: rawLowercased, in: haystack)
        }
        return 0
    }

    private static func findASCIICaseInsensitiveOffset(_ hay: UnsafeBufferPointer<UInt8>, needle: [UInt8]) -> Int? {
        let n = hay.count, m = needle.count
        guard n >= m else { return nil }
        let first = needle[0], limit = n - m
        var i = 0
        while i <= limit {
            let b = hay[i]
            let folded = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
            if folded == first {
                var matched = true
                var j = 1
                while j < m {
                    let hb = hay[i &+ j]
                    let hf = (hb >= 0x41 && hb <= 0x5A) ? (hb &+ 32) : hb
                    if hf != needle[j] { matched = false; break }
                    j &+= 1
                }
                if matched { return i }
            }
            i &+= 1
        }
        return nil
    }
}

public struct EverythingQuery: Sendable {
    public enum Predicate: Sendable {
        case text(QueryNeedle)
        case extensions(Set<String>)
        case foldersOnly, filesOnly, videosOnly, imagesOnly, audioOnly
        case pathContains(String)
    }

    public struct Term: Sendable {
        public let negated: Bool
        public let predicate: Predicate
        let pathNeedle: QueryNeedle?

        public init(negated: Bool, predicate: Predicate) {
            self.negated = negated
            self.predicate = predicate
            if case .pathContains(let sub) = predicate { self.pathNeedle = QueryNeedle(sub) }
            else { self.pathNeedle = nil }
        }
    }

    public struct Clause: Sendable {
        public let terms: [Term]
        public init(terms: [Term]) { self.terms = terms }
    }

    public let clauses: [Clause]
    public var isEmpty: Bool { clauses.isEmpty }

    var primaryPositiveTextNeedle: QueryNeedle? {
        guard clauses.count == 1 else { return nil }
        for term in clauses[0].terms where !term.negated {
            if case .text(let needle) = term.predicate { return needle }
        }
        return nil
    }

    public static func parse(_ raw: String) -> EverythingQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return EverythingQuery(clauses: []) }
        let clauses: [Clause] = trimmed.split(separator: "|", omittingEmptySubsequences: true).compactMap { part in
            let terms = tokenize(part).compactMap(parseToken)
            return terms.isEmpty ? nil : Clause(terms: terms)
        }
        return EverythingQuery(clauses: clauses)
    }

    public func matches(
        name: String,
        isDirectory: Bool,
        allowPinyin: Bool = false,
        parentPathProvider: () -> String,
        fullParentPathProvider: (() -> String)? = nil
    ) -> Bool {
        if clauses.isEmpty { return true }
        var cachedExtLower: String?
        var cachedParentPath: String?
        var cachedFullParentPath: String?
        for clause in clauses {
            if matchesClause(
                clause,
                name: name,
                cachedExtLower: &cachedExtLower,
                cachedParentPath: &cachedParentPath,
                cachedFullParentPath: &cachedFullParentPath,
                isDirectory: isDirectory,
                allowPinyin: allowPinyin,
                parentPathProvider: parentPathProvider,
                fullParentPathProvider: fullParentPathProvider
            ) {
                return true
            }
        }
        return false
    }

    private func matchesClause(
        _ clause: Clause,
        name: String,
        cachedExtLower: inout String?,
        cachedParentPath: inout String?,
        cachedFullParentPath: inout String?,
        isDirectory: Bool,
        allowPinyin: Bool,
        parentPathProvider: () -> String,
        fullParentPathProvider: (() -> String)?
    ) -> Bool {
        func extLower() -> String {
            if let cachedExtLower { return cachedExtLower }
            let computed = EverythingIndex.extractExtensionLower(fromName: name)
            cachedExtLower = computed
            return computed
        }

        for term in clause.terms {
            let hit: Bool
            switch term.predicate {
            case .text(let needle):
                hit = needle.matches(in: name, allowPinyin: allowPinyin)
            case .extensions(let exts):
                hit = !isDirectory && exts.contains(extLower())
            case .foldersOnly:
                hit = isDirectory
            case .filesOnly:
                hit = !isDirectory
            case .videosOnly:
                hit = !isDirectory && MediaClassifier.videoExtensions.contains(extLower())
            case .imagesOnly:
                hit = !isDirectory && MediaClassifier.imageExtensions.contains(extLower())
            case .audioOnly:
                hit = !isDirectory && MediaClassifier.audioExtensions.contains(extLower())
            case .pathContains(let substr):
                let parent = cachedParentPath ?? {
                    let resolved = parentPathProvider()
                    cachedParentPath = resolved
                    return resolved
                }()
                let displayHit = term.pathNeedle?.matches(in: parent) ?? parent.localizedStandardContains(substr)
                if displayHit {
                    hit = true
                } else if let fullParentPathProvider {
                    let fullParent = cachedFullParentPath ?? {
                        let resolved = fullParentPathProvider()
                        cachedFullParentPath = resolved
                        return resolved
                    }()
                    hit = term.pathNeedle?.matches(in: fullParent) ?? fullParent.localizedStandardContains(substr)
                } else {
                    hit = false
                }
            }
            if term.negated ? hit : !hit { return false }
        }
        return true
    }

    public static func tokenize(_ input: Substring) -> [Substring] {
        var result: [Substring] = []
        var current = ""
        var inQuotes = false
        for ch in input {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { result.append(Substring(current)); current.removeAll(keepingCapacity: true) }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(Substring(current)) }
        return result
    }

    private static func parseToken(_ token: Substring) -> Term? {
        var raw = token
        var negated = false
        if raw.first == "!" && raw.count > 1 { negated = true; raw = raw.dropFirst() }
        let lower = raw.lowercased()
        if lower == "folder:" { return Term(negated: negated, predicate: .foldersOnly) }
        if lower == "file:" { return Term(negated: negated, predicate: .filesOnly) }
        if lower == "video:" { return Term(negated: negated, predicate: .videosOnly) }
        if lower == "pic:" || lower == "image:" { return Term(negated: negated, predicate: .imagesOnly) }
        if lower == "audio:" || lower == "music:" { return Term(negated: negated, predicate: .audioOnly) }
        if lower.hasPrefix("ext:") {
            let list = lower.dropFirst(4)
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { String($0.drop(while: { $0 == "." })) }
                .filter { !$0.isEmpty }
            return list.isEmpty ? nil : Term(negated: negated, predicate: .extensions(Set(list)))
        }
        if lower.hasPrefix("path:") {
            let sub = String(lower.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return sub.isEmpty ? nil : Term(negated: negated, predicate: .pathContains(sub))
        }
        return Term(negated: negated, predicate: .text(QueryNeedle(lower)))
    }
}
