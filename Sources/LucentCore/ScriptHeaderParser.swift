import LucentFoundation
import CryptoKit
import Foundation

public struct ParsedScriptHeader: Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var englishTitle: String?
    public var subtitle: String?
    public var englishSubtitle: String?
    public var keywords: [String]?
    public var category: String?
    public var outputMode: ScriptOutputMode?
    public var icon: String?
    public var accentColor: String?
    public var scopes: Set<PluginResourceScope>?
    public var passClipboard: Bool?
    public var runtime: ScriptRuntime

    public init(runtime: ScriptRuntime) {
        self.runtime = runtime
    }
}

public enum ScriptHeaderParser {
    public static let recognizedExtensions: Set<String> = [
        "sh", "zsh", "bash", "py", "applescript", "swift", "js", "mjs", "cjs", "ts", "rb", "pl", "lua", "php"
    ]

    public static func contentSHA256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isSafeScriptID(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= 64 else { return false }
        let chars = Array(raw)
        guard let first = chars.first,
              (first >= "a" && first <= "z") || (first >= "0" && first <= "9") else {
            return false
        }
        return chars.allSatisfy {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" || $0 == "_"
        }
    }

    public static func sanitizeSlug(_ raw: String, fallback: String = "quick-script") -> String {
        let lower = raw.lowercased()
        var out = ""
        var prevHyphen = false
        for ch in lower {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "_" {
                out.append(ch)
                prevHyphen = false
            } else if !out.isEmpty && !prevHyphen {
                out.append("-")
                prevHyphen = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.isEmpty { return fallback }
        if out.count > 56 { out = String(out.prefix(56)) }
        while out.hasSuffix("-") { out.removeLast() }
        return isSafeScriptID(out) ? out : fallback
    }

    public static func validateSafeSVG(_ rawSVG: String) throws -> String {
        let trimmed = rawSVG.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LucentError.pluginInvalid("SVG 图标内容不能为空")
        }
        guard trimmed.utf8.count <= 65_536 else {
            throw LucentError.pluginInvalid("SVG 图标大小不能超过 64 KB")
        }
        let lower = trimmed.lowercased()
        guard lower.contains("<svg"), lower.contains("</svg>") else {
            throw LucentError.pluginInvalid("SVG 图标必须包含完整的 <svg>...</svg> 根节点")
        }
        let forbiddenTokens = ["<script", "javascript:", "onload=", "onerror=", "<foreignobject", "<iframe"]
        for bad in forbiddenTokens where lower.contains(bad) {
            throw LucentError.pluginInvalid("SVG 图标包含不安全标签或脚本属性：\(bad)")
        }
        return trimmed
    }

    /// 当设置页或 MCP 更新脚本元数据时，原位同步脚本头部已有的 `@lucent.*` 注释行，保持文件与索引一致。
    public static func syncExistingDirectives(in code: String, with record: ScriptRecord) -> String {
        var lines = code.components(separatedBy: "\n")
        let scanCount = min(lines.count, 30)
        var outLines: [String] = []
        outLines.reserveCapacity(lines.count)

        for idx in 0..<lines.count {
            guard idx < scanCount else {
                outLines.append(lines[idx])
                continue
            }
            let rawLine = lines[idx]
            let hasCR = rawLine.hasSuffix("\r")
            let line = hasCR ? String(rawLine.dropLast()) : rawLine
            guard let (prefix, key) = extractDirectivePrefixAndKey(from: line) else {
                outLines.append(rawLine)
                continue
            }
            let replacementValue: String? = switch key {
            case "@lucent.id": record.id
            case "@lucent.title", "@lucent.name": record.title
            case "@lucent.title.en", "@lucent.name.en": record.englishTitle ?? ""
            case "@lucent.subtitle", "@lucent.description": record.subtitle
            case "@lucent.subtitle.en", "@lucent.description.en": record.englishSubtitle ?? ""
            case "@lucent.keywords", "@lucent.keyword": record.keywords.joined(separator: ", ")
            case "@lucent.category": record.category
            case "@lucent.output": record.outputMode.rawValue
            case "@lucent.icon": record.icon
            case "@lucent.color", "@lucent.accent": record.accentColor
            case "@lucent.scopes":
                record.allowedScopes.isEmpty ? "none" : record.allowedScopes.map(\.rawValue).sorted().joined(separator: ", ")
            case "@lucent.clipboard":
                record.passClipboard ? "true" : "false"
            default:
                nil
            }
            if let val = replacementValue {
                if val.isEmpty {
                    continue
                }
                outLines.append("\(prefix)\(key): \(val)" + (hasCR ? "\r" : ""))
            } else {
                outLines.append(rawLine)
            }
        }
        lines = outLines
        return lines.joined(separator: "\n")
    }

    private static func extractDirectivePrefixAndKey(from line: String) -> (prefix: String, key: String)? {
        let leadingSpaces = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = String(line.dropFirst(leadingSpaces.count))
        let marker: String
        let afterMarker: String
        if trimmed.hasPrefix("#") && !trimmed.hasPrefix("#!") {
            marker = "# "
            afterMarker = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("//") {
            marker = "// "
            afterMarker = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.hasPrefix("--") {
            marker = "-- "
            afterMarker = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        guard afterMarker.lowercased().hasPrefix("@lucent."),
              let sepIdx = afterMarker.firstIndex(where: { $0 == ":" || $0 == "=" || $0.isWhitespace }) else {
            return nil
        }
        return (leadingSpaces + marker, String(afterMarker[..<sepIdx]).lowercased())
    }

    public static func parse(code: String, fileExtension: String) -> ParsedScriptHeader {
        let lines = code.components(separatedBy: .newlines)
        let firstLine = lines.first ?? ""
        var parsed = ParsedScriptHeader(runtime: ScriptRuntime.infer(fileExtension: fileExtension, firstLine: firstLine))

        for line in lines.prefix(30) {
            guard let (_, key) = extractDirectivePrefixAndKey(from: line) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let atRange = trimmed.range(of: "@lucent.", options: [.caseInsensitive]) else { continue }
            let comment = String(trimmed[atRange.lowerBound...])
            guard let sepIdx = comment.firstIndex(where: { $0 == ":" || $0 == "=" || $0.isWhitespace }) else { continue }
            var val = String(comment[sepIdx...]).trimmingCharacters(in: .whitespaces)
            if val.hasPrefix(":") || val.hasPrefix("=") {
                val = String(val.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !val.isEmpty else { continue }

            switch key {
            case "@lucent.id":
                if isSafeScriptID(val) { parsed.id = val }
            case "@lucent.title", "@lucent.name":
                parsed.title = String(val.prefix(64))
            case "@lucent.title.en", "@lucent.name.en":
                parsed.englishTitle = String(val.prefix(64))
            case "@lucent.subtitle", "@lucent.description":
                parsed.subtitle = String(val.prefix(120))
            case "@lucent.subtitle.en", "@lucent.description.en":
                parsed.englishSubtitle = String(val.prefix(120))
            case "@lucent.keywords", "@lucent.keyword":
                let kws = val.split(whereSeparator: { $0 == "," || $0 == ";" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !kws.isEmpty { parsed.keywords = kws }
            case "@lucent.category":
                parsed.category = String(val.prefix(24))
            case "@lucent.output":
                if let mode = ScriptOutputMode(rawValue: val) { parsed.outputMode = mode }
            case "@lucent.icon":
                parsed.icon = String(val.prefix(80))
            case "@lucent.color", "@lucent.accent":
                parsed.accentColor = String(val.prefix(24))
            case "@lucent.scopes":
                if val == "none" || val == "[]" {
                    parsed.scopes = []
                } else {
                    var set = Set<PluginResourceScope>()
                    for token in val.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
                        if let sc = PluginResourceScope(rawValue: String(token)) { set.insert(sc) }
                    }
                    parsed.scopes = set
                }
            case "@lucent.clipboard":
                parsed.passClipboard = (val.lowercased() == "true" || val == "1" || val.lowercased() == "yes")
            default:
                break
            }
        }
        return parsed
    }
}
