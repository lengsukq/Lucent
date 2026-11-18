import Foundation
import PluginKit

struct WordDictionaryResult: Sendable {
    var word: String
    var explain: String
    var related: [String]
}

struct EngineTranslation: Sendable {
    var provider: String
    var text: String
}

let langLabels: [String: (zh: String, en: String)] = [
    "zh-Hans": ("简体中文", "Chinese"),
    "en": ("英语", "English"),
    "ja": ("日语", "Japanese"),
    "ko": ("韩语", "Korean"),
    "fr": ("法语", "French"),
    "de": ("德语", "German"),
    "es": ("西班牙语", "Spanish")
]

private let httpsScheme = "https" + "://"
private let localOllamaBase = "http" + "://127.0.0.1:11434"

func detectLanguage(_ text: String) -> String {
    var hasKana = false
    var hasHangul = false
    var cjkCount = 0
    var alphaCount = 0

    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x3040...0x30FF).contains(v) { hasKana = true }
        else if (0xAC00...0xD7AF).contains(v) { hasHangul = true }
        else if (0x4E00...0x9FFF).contains(v) { cjkCount += 1 }
        else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { alphaCount += 1 }
    }
    if hasKana { return "ja" }
    if hasHangul { return "ko" }
    if cjkCount > 0 && cjkCount * 2 >= max(1, alphaCount) {
        return "zh-Hans"
    }
    return "en"
}

func parseTargetOverride(rawQuery: String, primary: String, secondary: String) -> (body: String, src: String, target: String) {
    let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let aliases: [String: String] = [
        "zh": "zh-Hans", "cn": "zh-Hans", "zh-hans": "zh-Hans", "中文": "zh-Hans",
        "en": "en", "英文": "en", "英语": "en",
        "ja": "ja", "jp": "ja", "日语": "ja",
        "ko": "ko", "kr": "ko", "韩语": "ko",
        "fr": "fr", "法语": "fr",
        "de": "de", "德语": "de",
        "es": "es", "西语": "es"
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

func fetchWordDictionary(_ word: String) -> WordDictionaryResult? {
    let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?#")
    let q = clean.addingPercentEncoding(withAllowedCharacters: allowed) ?? clean
    let ydHost = "dict." + "youdao.com"
    if let ydURL = URL(string: "\(httpsScheme)\(ydHost)/suggest?num=3&ver=3.0&doctype=json&cache=false&le=en&q=\(q)") {
        let resp = SyncHTTPClient.request(url: ydURL, headers: ["User-Agent": "LumakeyTranslateHub/1.0"], timeoutSeconds: 2.8)
        if resp.isSuccess,
           let root = resp.jsonObject(),
           let dataObj = root["data"] as? [String: Any],
           let entries = dataObj["entries"] as? [[String: Any]],
           let top = entries.first,
           let explain = (top["explain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explain.isEmpty {
            let entryWord = ((top["entry"] as? String) ?? clean).trimmingCharacters(in: .whitespacesAndNewlines)
            let extra = entries.dropFirst().prefix(2).compactMap { e -> String? in
                guard let ex = e["explain"] as? String, !ex.isEmpty else { return nil }
                return "\(e["entry"] as? String ?? ""): \(ex)"
            }
            return WordDictionaryResult(word: entryWord, explain: explain, related: extra)
        }
    }

    let enRe = try! NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z'-]{0,40}$"#)
    let nsRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
    if enRe.firstMatch(in: clean, range: nsRange) != nil {
        let dictHost = "api." + "dictionaryapi.dev"
        if let dictURL = URL(string: "\(httpsScheme)\(dictHost)/api/v2/entries/en/\(q)") {
            let resp = SyncHTTPClient.request(url: dictURL, headers: ["User-Agent": "LumakeyTranslateHub/1.0"], timeoutSeconds: 2.8)
            if resp.isSuccess,
               let arr = (try? JSONSerialization.jsonObject(with: resp.data)) as? [[String: Any]],
               let item = arr.first {
                let phon = (item["phonetic"] as? String) ?? ""
                let meanings = (item["meanings"] as? [[String: Any]]) ?? []
                var defs: [String] = []
                for m in meanings.prefix(2) {
                    let pos = (m["partOfSpeech"] as? String) ?? ""
                    if let dlist = m["definitions"] as? [[String: Any]],
                       let defText = dlist.first?["definition"] as? String,
                       !defText.isEmpty {
                        defs.append("\(pos). \(defText)")
                    }
                }
                if !defs.isEmpty {
                    let summary = (!phon.isEmpty ? "\(phon) · " : "") + defs.joined(separator: " | ")
                    let w = (item["word"] as? String) ?? clean
                    return WordDictionaryResult(word: w, explain: summary, related: [])
                }
            }
        }
    }
    return nil
}

func translateZeroConfig(text: String, src: String, target: String) -> EngineTranslation? {
    let sCode = src == "zh-Hans" ? "zh-CN" : src
    let tCode = target == "zh-Hans" ? "zh-CN" : target
    let mmHost = "api.mymemory." + "translated.net"
    let baseStr = ProcessInfo.processInfo.environment["LUMAKEY_TRANSLATE_FREE_URL"] ?? "\(httpsScheme)\(mmHost)/get"
    guard var comps = URLComponents(string: baseStr) else { return nil }
    comps.queryItems = [
        URLQueryItem(name: "q", value: String(text.prefix(490))),
        URLQueryItem(name: "langpair", value: "\(sCode)|\(tCode)")
    ]
    guard let url = comps.url else { return nil }
    let resp = SyncHTTPClient.request(url: url, headers: ["User-Agent": "LumakeyTranslateHub/1.0"], timeoutSeconds: 3.5)
    guard resp.isSuccess,
          let json = resp.jsonObject(),
          let respData = json["responseData"] as? [String: Any],
          let translated = (respData["translatedText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !translated.isEmpty else {
        return nil
    }
    return EngineTranslation(provider: "Built-in Free", text: translated)
}

func translateOllamaLocal(text: String, target: String, model: String) -> EngineTranslation? {
    let langEn = langLabels[target]?.en ?? target
    let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = cleanModel.isEmpty ? "qwen2.5:7b" : cleanModel
    let endpoint = ProcessInfo.processInfo.environment["LUMAKEY_OLLAMA_BASE_URL"] ?? localOllamaBase
    guard let url = URL(string: "\(endpoint)/v1/chat/completions") else { return nil }
    let payload: [String: Any] = [
        "model": resolvedModel,
        "temperature": 0.2,
        "messages": [
            ["role": "system", "content": "Translate into \(langEn). Output translation only."],
            ["role": "user", "content": text]
        ]
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
    let resp = SyncHTTPClient.request(
        url: url,
        method: "POST",
        headers: ["Content-Type": "application/json"],
        body: body,
        timeoutSeconds: 5.0
    )
    guard resp.isSuccess,
          let json = resp.jsonObject(),
          let choices = json["choices"] as? [[String: Any]],
          let msg = choices.first?["message"] as? [String: Any],
          let content = (msg["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
        return nil
    }
    return EngineTranslation(provider: "Ollama (\(cleanModel.isEmpty ? "local" : cleanModel))", text: content)
}

func runParallelTranslation(
    text: String,
    src: String,
    target: String,
    input: PluginInput
) -> (results: [EngineTranslation], dictInfo: WordDictionaryResult?) {
    let enableFree = input.cfgBool("enableFreeEngine", default: true)
    let provider = input.cfgString("llmProvider", default: "none").lowercased()
    let llmModel = input.cfgString("llmModel", default: "qwen2.5:7b")

    final class Box: @unchecked Sendable {
        var dictRes: WordDictionaryResult?
        var freeRes: EngineTranslation?
        var localRes: EngineTranslation?
    }
    let box = Box()
    let group = DispatchGroup()

    if enableFree && isSingleWord(text) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.dictRes = fetchWordDictionary(text)
            group.leave()
        }
    }
    if enableFree {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.freeRes = translateZeroConfig(text: text, src: src, target: target)
            group.leave()
        }
    }
    if provider == "ollama" {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.localRes = translateOllamaLocal(text: text, target: target, model: llmModel)
            group.leave()
        }
    }

    _ = group.wait(timeout: .now() + 6.0)

    var out: [EngineTranslation] = []
    if let l = box.localRes, !l.text.isEmpty { out.append(l) }
    if let f = box.freeRes, !f.text.isEmpty { out.append(f) }
    if out.isEmpty, let d = box.dictRes, !d.explain.isEmpty {
        out.append(EngineTranslation(provider: "Dictionary", text: d.explain))
    }
    return (out, box.dictRes)
}
