import Foundation
import PluginKit
#if canImport(Translation) && compiler(>=6.2)
import Translation
#endif

func runAppleTranslateAsync(
    text: String,
    src: String,
    target: String,
    isEn: Bool,
    completion: @escaping @Sendable (Result<EngineTranslation, EngineDiagnostic>) -> Void
) {
    let label = isEn ? "Apple Translate" : "苹果自带翻译"
    #if canImport(Translation) && compiler(>=6.2)
    if #available(macOS 26.0, *) {
        Task.detached(priority: .userInitiated) {
            let srcLang = Locale.Language(identifier: src)
            let dstLang = Locale.Language(identifier: target)
            let status = await LanguageAvailability().status(from: srcLang, to: dstLang)
            switch status {
            case .installed:
                let session = TranslationSession(installedSource: srcLang, target: dstLang)
                do {
                    let response = try await session.translate(text)
                    let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if out.isEmpty {
                        completion(.failure(EngineDiagnostic(
                            engineID: "apple",
                            provider: label,
                            message: isEn ? "Empty result from Apple Translate" : "苹果翻译返回为空"
                        )))
                    } else {
                        completion(.success(EngineTranslation(engineID: "apple", provider: label, text: out)))
                    }
                } catch {
                    completion(.failure(EngineDiagnostic(engineID: "apple", provider: label, message: error.localizedDescription)))
                }
            case .supported:
                completion(.failure(EngineDiagnostic(
                    engineID: "apple",
                    provider: label,
                    message: isEn
                        ? "Offline pack (\(src) → \(target)) not downloaded. Open System Settings → General → Language & Region → Translation Languages."
                        : "未下载离线翻译语言包（\(src) → \(target)），请在「系统设置 → 通用 → 语言与地区 → 翻译语言」中下载"
                )))
            case .unsupported:
                completion(.failure(EngineDiagnostic(
                    engineID: "apple",
                    provider: label,
                    message: isEn ? "Language pair \(src) → \(target) is not supported by Apple Translate." : "苹果自带翻译暂不支持 \(src) → \(target)"
                )))
            @unknown default:
                completion(.failure(EngineDiagnostic(engineID: "apple", provider: label, message: isEn ? "Unknown Apple Translate status" : "苹果翻译状态未知")))
            }
        }
        return
    }
    #endif
    completion(.failure(EngineDiagnostic(
        engineID: "apple",
        provider: label,
        message: isEn ? "Apple Translate requires macOS 26+" : "苹果自带翻译需要 macOS 26 及以上系统"
    )))
}

private func resolveOpenAIEndpoint(_ rawBase: String) -> URL? {
    var base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty { base = defaultOpenAIBase }
    while base.hasSuffix("/") { base.removeLast() }
    if base.hasSuffix("/chat/completions") { return URL(string: base) }
    guard let parsed = URL(string: base), parsed.scheme != nil else { return nil }
    let path = parsed.path
    if path.isEmpty || path == "/" {
        return URL(string: "\(base)/v1/chat/completions")
    }
    return URL(string: "\(base)/chat/completions")
}

private func isLocalhostURL(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "127.0.0.1" || host == "localhost" || host == "::1"
}

func translateOpenAICompatible(
    text: String,
    target: String,
    baseUrl: String,
    apiKey: String,
    model: String,
    customPrompt: String,
    isEn: Bool
) -> Result<EngineTranslation, EngineDiagnostic> {
    let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = cleanModel.isEmpty ? "gpt-4o-mini" : cleanModel
    let providerLabel = "OpenAI · \(resolvedModel)"
    guard let url = resolveOpenAIEndpoint(baseUrl) else {
        return .failure(EngineDiagnostic(engineID: "openai", provider: providerLabel, message: isEn ? "Invalid OpenAI Base URL" : "OpenAI Base URL 格式无效"))
    }

    let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanKey.isEmpty && !isLocalhostURL(url) {
        return .failure(EngineDiagnostic(engineID: "openai", provider: providerLabel, message: isEn ? "OpenAI API Key is empty" : "未填写 OpenAI API Key，请在插件设置中配置"))
    }

    let payload: [String: Any] = [
        "model": resolvedModel,
        "temperature": 0.2,
        "messages": [
            ["role": "system", "content": buildTranslatorPrompt(customPrompt: customPrompt, target: target)],
            ["role": "user", "content": text]
        ]
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
        return .failure(EngineDiagnostic(engineID: "openai", provider: providerLabel, message: "JSON encode failed"))
    }

    var headers = ["Content-Type": "application/json"]
    if !cleanKey.isEmpty { headers["Authorization"] = "Bearer \(cleanKey)" }

    let resp = SyncHTTPClient.request(url: url, method: "POST", headers: headers, body: body, timeoutSeconds: 14.0)
    guard resp.isSuccess, let json = resp.jsonObject(),
          let choices = json["choices"] as? [[String: Any]],
          let msg = choices.first?["message"] as? [String: Any] else {
        return .failure(EngineDiagnostic(engineID: "openai", provider: providerLabel, message: extractHTTPFailureMessage(resp, isEn: isEn)))
    }

    var extracted = ""
    if let s = msg["content"] as? String {
        extracted = s.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let parts = msg["content"] as? [[String: Any]] {
        extracted = parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard !extracted.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "openai", provider: providerLabel, message: isEn ? "Empty response content" : "模型返回内容为空"))
    }
    return .success(EngineTranslation(engineID: "openai", provider: providerLabel, text: extracted))
}

private func resolveGeminiEndpoint(baseUrl: String, model: String) -> URL? {
    var base = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty { base = defaultGeminiBase }
    while base.hasSuffix("/") { base.removeLast() }
    if base.contains(":generateContent") { return URL(string: base) }
    let cleanModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
    let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanModel
    if base.hasSuffix("/v1beta") || base.hasSuffix("/v1") {
        return URL(string: "\(base)/models/\(encodedModel):generateContent")
    }
    return URL(string: "\(base)/v1beta/models/\(encodedModel):generateContent")
}

func translateGemini(
    text: String,
    target: String,
    baseUrl: String,
    apiKey: String,
    model: String,
    customPrompt: String,
    isEn: Bool
) -> Result<EngineTranslation, EngineDiagnostic> {
    let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = cleanModel.isEmpty ? "gemini-2.5-flash" : cleanModel
    let providerLabel = "Gemini · \(resolvedModel)"
    guard let url = resolveGeminiEndpoint(baseUrl: baseUrl, model: resolvedModel) else {
        return .failure(EngineDiagnostic(engineID: "gemini", provider: providerLabel, message: isEn ? "Invalid Gemini Base URL" : "Gemini Base URL 格式无效"))
    }

    let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanKey.isEmpty {
        return .failure(EngineDiagnostic(engineID: "gemini", provider: providerLabel, message: isEn ? "Gemini API Key is empty" : "未填写 Google Gemini API Key，请在插件设置中配置"))
    }

    let payload: [String: Any] = [
        "systemInstruction": ["parts": [["text": buildTranslatorPrompt(customPrompt: customPrompt, target: target)]]],
        "contents": [["role": "user", "parts": [["text": text]]]],
        "generationConfig": ["temperature": 0.2]
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
        return .failure(EngineDiagnostic(engineID: "gemini", provider: providerLabel, message: "JSON encode failed"))
    }

    let headers = ["Content-Type": "application/json", "x-goog-api-key": cleanKey]
    let resp = SyncHTTPClient.request(url: url, method: "POST", headers: headers, body: body, timeoutSeconds: 14.0)
    guard resp.isSuccess, let json = resp.jsonObject(),
          let candidates = json["candidates"] as? [[String: Any]],
          let content = candidates.first?["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]] else {
        return .failure(EngineDiagnostic(engineID: "gemini", provider: providerLabel, message: extractHTTPFailureMessage(resp, isEn: isEn)))
    }

    let extracted = parts.compactMap { part -> String? in
        if let isThought = part["thought"] as? Bool, isThought { return nil }
        return part["text"] as? String
    }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

    guard !extracted.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "gemini", provider: providerLabel, message: isEn ? "Empty response from Gemini" : "Gemini 返回内容为空"))
    }
    return .success(EngineTranslation(engineID: "gemini", provider: providerLabel, text: extracted))
}

func translateOllamaLocal(text: String, target: String, baseUrl: String, model: String, isEn: Bool) -> Result<EngineTranslation, EngineDiagnostic> {
    let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = cleanModel.isEmpty ? "qwen2.5:7b" : cleanModel
    let providerLabel = "Ollama · \(resolvedModel)"
    let envBase = ProcessInfo.processInfo.environment["LUCENT_OLLAMA_BASE_URL"]
    let rawBase = (envBase?.isEmpty == false ? envBase! : baseUrl).trimmingCharacters(in: .whitespacesAndNewlines)
    var base = rawBase.isEmpty ? defaultLocalOllamaBase : rawBase
    while base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base.hasSuffix("/v1/chat/completions") ? base : "\(base)/v1/chat/completions") else {
        return .failure(EngineDiagnostic(engineID: "ollama", provider: providerLabel, message: isEn ? "Invalid Ollama URL" : "Ollama 地址无效"))
    }

    let langEn = langLabels[target]?.en ?? target
    let payload: [String: Any] = [
        "model": resolvedModel,
        "temperature": 0.2,
        "messages": [
            ["role": "system", "content": "Translate into \(langEn). Output translation only."],
            ["role": "user", "content": text]
        ]
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
        return .failure(EngineDiagnostic(engineID: "ollama", provider: providerLabel, message: "JSON encode failed"))
    }

    let resp = SyncHTTPClient.request(url: url, method: "POST", headers: ["Content-Type": "application/json"], body: body, timeoutSeconds: 12.0)
    guard resp.isSuccess,
          let json = resp.jsonObject(),
          let choices = json["choices"] as? [[String: Any]],
          let msg = choices.first?["message"] as? [String: Any],
          let content = (msg["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
        return .failure(EngineDiagnostic(engineID: "ollama", provider: providerLabel, message: extractHTTPFailureMessage(resp, isEn: isEn)))
    }
    return .success(EngineTranslation(engineID: "ollama", provider: providerLabel, text: content))
}
