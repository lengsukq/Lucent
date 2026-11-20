import CommonCrypto
import CryptoKit
import Foundation
import PluginKit

func fetchWordDictionary(_ word: String) -> WordDictionaryResult? {
    let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?#")
    let q = clean.addingPercentEncoding(withAllowedCharacters: allowed) ?? clean
    let ydHost = "dict." + "youdao.com"
    if let ydURL = URL(string: "\(httpsScheme)\(ydHost)/suggest?num=3&ver=3.0&doctype=json&cache=false&le=en&q=\(q)") {
        let resp = SyncHTTPClient.request(url: ydURL, headers: ["User-Agent": "LucentTranslateHub/1.1"], timeoutSeconds: 2.8)
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
            let resp = SyncHTTPClient.request(url: dictURL, headers: ["User-Agent": "LucentTranslateHub/1.1"], timeoutSeconds: 2.8)
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

func translateZeroConfig(text: String, src: String, target: String, isEn: Bool) -> Result<EngineTranslation, EngineDiagnostic> {
    let sCode = src == "zh-Hans" ? "zh-CN" : (src == "zh-Hant" ? "zh-TW" : src)
    let tCode = target == "zh-Hans" ? "zh-CN" : (target == "zh-Hant" ? "zh-TW" : target)
    let mmHost = "api.mymemory." + "translated.net"
    let baseStr = ProcessInfo.processInfo.environment["LUCENT_TRANSLATE_FREE_URL"] ?? "\(httpsScheme)\(mmHost)/get"
    guard var comps = URLComponents(string: baseStr) else {
        return .failure(EngineDiagnostic(engineID: "free", provider: "Built-in Free", message: isEn ? "Invalid free endpoint URL" : "内置通道 URL 无效"))
    }
    comps.queryItems = [
        URLQueryItem(name: "q", value: String(text.prefix(490))),
        URLQueryItem(name: "langpair", value: "\(sCode)|\(tCode)")
    ]
    guard let url = comps.url else {
        return .failure(EngineDiagnostic(engineID: "free", provider: "Built-in Free", message: isEn ? "Failed to build request URL" : "构建内置通道请求失败"))
    }
    let resp = SyncHTTPClient.request(url: url, headers: ["User-Agent": "LucentTranslateHub/1.1"], timeoutSeconds: 4.0)
    guard resp.isSuccess,
          let json = resp.jsonObject(),
          let respData = json["responseData"] as? [String: Any],
          let translated = (respData["translatedText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !translated.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "free", provider: "Built-in Free", message: extractHTTPFailureMessage(resp, isEn: isEn)))
    }
    return .success(EngineTranslation(engineID: "free", provider: "Built-in Free", text: translated))
}

private func formURLEncode(_ params: [(String, String)]) -> Data? {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encoded = params.map { key, value in
        let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(k)=\(v)"
    }.joined(separator: "&")
    return encoded.data(using: .utf8)
}

private func decryptYoudaoAES128CBC(encryptedText: String, aesKey: String, aesIv: String) -> Data? {
    var b64 = encryptedText
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let rem = b64.count % 4
    if rem != 0 {
        b64 += String(repeating: "=", count: 4 - rem)
    }
    guard let cipherData = Data(base64Encoded: b64) else { return nil }

    let keyBytes = Array(Insecure.MD5.hash(data: Data(aesKey.utf8)))
    let ivBytes = Array(Insecure.MD5.hash(data: Data(aesIv.utf8)))

    let outSize = cipherData.count + kCCBlockSizeAES128
    var outBytes = [UInt8](repeating: 0, count: outSize)
    var numBytesDecrypted = 0

    let status = cipherData.withUnsafeBytes { cipherPtr in
        CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes,
            kCCKeySizeAES128,
            ivBytes,
            cipherPtr.baseAddress,
            cipherData.count,
            &outBytes,
            outSize,
            &numBytesDecrypted
        )
    }
    guard status == kCCSuccess else { return nil }
    return Data(outBytes.prefix(numBytesDecrypted))
}

private func youdaoLangCode(_ code: String) -> String {
    switch code {
    case "zh-Hans": return "zh-CHS"
    case "zh-Hant": return "zh-CHT"
    default: return code
    }
}

func translateYoudao(text: String, src: String, target: String, isEn: Bool) -> Result<EngineTranslation, EngineDiagnostic> {
    let providerLabel = isEn ? "Youdao Translate" : "网易有道翻译"
    let ydDictHost = "dict." + "youdao.com"
    let ydFanyiHost = "fanyi." + "youdao.com"
    let commonHeaders = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Referer": "\(httpsScheme)\(ydFanyiHost)",
        "Cookie": "OUTFOX_SEARCH_USER_ID=1796239350@10.110.96.157;"
    ]

    let ts1 = String(Int(Date().timeIntervalSince1970 * 1000))
    let keySign = md5Hex("client=fanyideskweb&mysticTime=\(ts1)&product=webfanyi&key=asdjnjfenknafdfsdfsd")

    guard var keyComps = URLComponents(string: "\(httpsScheme)\(ydDictHost)/webtranslate/key") else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: "Invalid Youdao key URL"))
    }
    keyComps.queryItems = [
        URLQueryItem(name: "client", value: "fanyideskweb"),
        URLQueryItem(name: "product", value: "webfanyi"),
        URLQueryItem(name: "appVersion", value: "1.0.0"),
        URLQueryItem(name: "vendor", value: "web"),
        URLQueryItem(name: "pointParam", value: "client,mysticTime,product"),
        URLQueryItem(name: "keyfrom", value: "fanyi.web"),
        URLQueryItem(name: "keyid", value: "webfanyi-key-getter"),
        URLQueryItem(name: "sign", value: keySign),
        URLQueryItem(name: "mysticTime", value: ts1)
    ]
    guard let keyURL = keyComps.url else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: "Failed to build Youdao key URL"))
    }

    let keyResp = SyncHTTPClient.request(url: keyURL, headers: commonHeaders, timeoutSeconds: 4.0)
    guard keyResp.isSuccess,
          let keyJSON = keyResp.jsonObject(),
          let keyData = keyJSON["data"] as? [String: Any],
          let secretKey = keyData["secretKey"] as? String,
          let aesKey = keyData["aesKey"] as? String,
          let aesIv = keyData["aesIv"] as? String,
          !secretKey.isEmpty, !aesKey.isEmpty, !aesIv.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: extractHTTPFailureMessage(keyResp, isEn: isEn)))
    }

    let ts2 = String(Int(Date().timeIntervalSince1970 * 1000))
    let transSign = md5Hex("client=fanyideskweb&mysticTime=\(ts2)&product=webfanyi&key=\(secretKey)")
    let formParams: [(String, String)] = [
        ("i", text),
        ("from", youdaoLangCode(src)),
        ("to", youdaoLangCode(target)),
        ("dictResult", "false"),
        ("keyid", "webfanyi"),
        ("sign", transSign),
        ("mysticTime", ts2),
        ("client", "fanyideskweb"),
        ("product", "webfanyi"),
        ("appVersion", "1.0.0"),
        ("vendor", "web"),
        ("pointParam", "client,mysticTime,product"),
        ("keyfrom", "fanyi.web")
    ]
    guard let transURL = URL(string: "\(httpsScheme)\(ydDictHost)/webtranslate"),
          let body = formURLEncode(formParams) else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: "Failed to build Youdao translate request"))
    }

    var postHeaders = commonHeaders
    postHeaders["Content-Type"] = "application/x-www-form-urlencoded"
    let transResp = SyncHTTPClient.request(url: transURL, method: "POST", headers: postHeaders, body: body, timeoutSeconds: 5.0)
    guard transResp.isSuccess,
          let decrypted = decryptYoudaoAES128CBC(encryptedText: transResp.text, aesKey: aesKey, aesIv: aesIv),
          let resultJSON = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: extractHTTPFailureMessage(transResp, isEn: isEn)))
    }

    if let code = resultJSON["code"] as? Int, code != 0 {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: "Youdao API code \(code)"))
    }
    guard let groups = resultJSON["translateResult"] as? [[[String: Any]]] else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: isEn ? "Invalid Youdao response" : "有道返回格式异常"))
    }
    let translated = groups.map { $0.compactMap { $0["tgt"] as? String }.joined() }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !translated.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "youdao", provider: providerLabel, message: isEn ? "Empty Youdao translation" : "有道返回译文为空"))
    }
    return .success(EngineTranslation(engineID: "youdao", provider: providerLabel, text: translated))
}
