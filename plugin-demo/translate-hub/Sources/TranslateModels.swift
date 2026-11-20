import CryptoKit
import Foundation
import PluginKit

struct WordDictionaryResult: Sendable {
    var word: String
    var explain: String
    var related: [String]
}

struct EngineTranslation: Sendable {
    var engineID: String
    var provider: String
    var text: String
}

struct EngineDiagnostic: Error, Sendable {
    var engineID: String
    var provider: String
    var message: String
}

let httpsScheme = "https" + "://"
let defaultLocalOllamaBase = "http" + "://127.0.0.1:11434"
let defaultOpenAIBase = httpsScheme + "api.openai.com/v1"
let defaultGeminiBase = httpsScheme + "generativelanguage.googleapis.com"

let langLabels: [String: (zh: String, en: String)] = [
    "zh-Hans": ("简体中文", "Simplified Chinese"),
    "zh-Hant": ("繁体中文", "Traditional Chinese"),
    "en": ("英语", "English"),
    "ja": ("日语", "Japanese"),
    "ko": ("韩语", "Korean"),
    "fr": ("法语", "French"),
    "de": ("德语", "German"),
    "es": ("西班牙语", "Spanish"),
    "ru": ("俄语", "Russian"),
    "pt": ("葡萄牙语", "Portuguese"),
    "it": ("意大利语", "Italian"),
    "vi": ("越南语", "Vietnamese")
]

func detectLanguage(_ text: String) -> String {
    var hasKana = false
    var hasHangul = false
    var hasCyrillic = false
    var cjkCount = 0
    var alphaCount = 0

    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x3040...0x30FF).contains(v) { hasKana = true }
        else if (0xAC00...0xD7AF).contains(v) { hasHangul = true }
        else if (0x0400...0x04FF).contains(v) { hasCyrillic = true }
        else if (0x4E00...0x9FFF).contains(v) { cjkCount += 1 }
        else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { alphaCount += 1 }
    }
    if hasKana { return "ja" }
    if hasHangul { return "ko" }
    if hasCyrillic { return "ru" }
    if cjkCount > 0 && cjkCount * 2 >= max(1, alphaCount) {
        return "zh-Hans"
    }
    return "en"
}

func parseTargetOverride(rawQuery: String, primary: String, secondary: String) -> (body: String, src: String, target: String) {
    let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let aliases: [String: String] = [
        "zh": "zh-Hans", "cn": "zh-Hans", "zh-hans": "zh-Hans", "中文": "zh-Hans",
        "tw": "zh-Hant", "zh-hant": "zh-Hant", "繁体": "zh-Hant",
        "en": "en", "英文": "en", "英语": "en",
        "ja": "ja", "jp": "ja", "日语": "ja",
        "ko": "ko", "kr": "ko", "韩语": "ko",
        "fr": "fr", "法语": "fr",
        "de": "de", "德语": "de",
        "es": "es", "西语": "es",
        "ru": "ru", "俄语": "ru",
        "pt": "pt", "葡语": "pt",
        "it": "it", "意语": "it",
        "vi": "vi", "越语": "vi"
    ]
    if trimmed.hasPrefix(">"),
       let wsIdx = trimmed.firstIndex(where: \.isWhitespace) {
        let tag = String(trimmed[trimmed.index(after: trimmed.startIndex)..<wsIdx]).lowercased()
        let body = String(trimmed[wsIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty, let targetAlias = aliases[tag] {
            let src = detectLanguage(body)
            return (body, src, targetAlias)
        }
    }
    let src = detectLanguage(trimmed)
    var target = (src == primary) ? secondary : primary
    if target == src {
        target = (src == "zh-Hans") ? "en" : "zh-Hans"
    }
    return (trimmed, src, target)
}

func isSingleWord(_ text: String) -> Bool {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty || s.count > 42 || s.contains("\n") { return false }
    let enRe = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z'-]{0,40}$"#)
    let zhRe = try! NSRegularExpression(pattern: #"^[\u4e00-\u9fff]{1,6}$"#)
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    return enRe.firstMatch(in: s, range: range) != nil || zhRe.firstMatch(in: s, range: range) != nil
}

func md5Hex(_ input: String) -> String {
    Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
}

func extractHTTPFailureMessage(_ resp: SyncHTTPResponse, isEn: Bool) -> String {
    if let json = resp.jsonObject() {
        if let errObj = json["error"] as? [String: Any],
           let msg = errObj["message"] as? String, !msg.isEmpty {
            return "HTTP \(resp.statusCode): \(msg)"
        }
        if let msg = json["message"] as? String, !msg.isEmpty {
            return "HTTP \(resp.statusCode): \(msg)"
        }
    }
    if resp.statusCode > 0 {
        let snippet = resp.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        return snippet.isEmpty ? "HTTP \(resp.statusCode)" : "HTTP \(resp.statusCode): \(snippet)"
    }
    return resp.errorDescription ?? (isEn ? "Request failed" : "请求失败")
}

func buildTranslatorPrompt(customPrompt: String, target: String) -> String {
    let langEn = langLabels[target]?.en ?? target
    let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        return trimmed
            .replacingOccurrences(of: "{{target}}", with: langEn)
            .replacingOccurrences(of: "{{targetCode}}", with: target)
    }
    return "You are a professional translator. Translate the user's text into \(langEn) (\(target)). Preserve formatting, code identifiers, and tone. Output ONLY the translated text without explanations or surrounding quotes."
}
