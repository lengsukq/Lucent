import Foundation
import PluginKit

func runParallelTranslation(
    text: String,
    src: String,
    target: String,
    input: PluginInput
) -> (results: [EngineTranslation], dictInfo: WordDictionaryResult?, diagnostics: [EngineDiagnostic]) {
    let isEn = input.isEnglish
    let enableYoudao = input.cfgBool("enableYoudaoTranslate", default: true)
    let enableApple = input.cfgBool("enableAppleTranslate", default: false)
    let enableFree = input.cfgBool("enableFreeEngine", default: true)
    let enableOpenAI = input.cfgBool("enableOpenAI", default: false)
    let enableGemini = input.cfgBool("enableGemini", default: false)
    let legacyOllama = input.cfgString("llmProvider", default: "none").lowercased() == "ollama"
    let enableOllama = input.cfgBool("enableOllama", default: legacyOllama)
    let showDict = input.cfgBool("showDictionaryCard", default: true)
    let primaryEngine = input.cfgString("primaryEngine", default: "auto").lowercased()

    let openaiBase = input.cfgString("openaiBaseUrl", default: defaultOpenAIBase)
    let openaiKey = input.cfgString("openaiApiKey", default: "")
    let openaiModel = input.cfgString("openaiModel", default: "gpt-4o-mini")
    let openaiPrompt = input.cfgString("openaiPrompt", default: "")

    let geminiBase = input.cfgString("geminiBaseUrl", default: defaultGeminiBase)
    let geminiKey = input.cfgString("geminiApiKey", default: "")
    let geminiModel = input.cfgString("geminiModel", default: "gemini-2.5-flash")
    let geminiPrompt = input.cfgString("geminiPrompt", default: "")

    let ollamaBase = input.cfgString("ollamaBaseUrl", default: defaultLocalOllamaBase)
    let ollamaModel = input.cfgString("llmModel", default: "qwen2.5:7b")

    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var dictRes: WordDictionaryResult?
        var translations: [String: EngineTranslation] = [:]
        var diagnostics: [EngineDiagnostic] = []

        func record(_ res: Result<EngineTranslation, EngineDiagnostic>) {
            lock.lock()
            defer { lock.unlock() }
            switch res {
            case .success(let t): translations[t.engineID] = t
            case .failure(let err): diagnostics.append(err)
            }
        }
    }

    let box = Box()
    let group = DispatchGroup()

    if showDict && isSingleWord(text) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let d = fetchWordDictionary(text)
            box.lock.lock()
            box.dictRes = d
            box.lock.unlock()
            group.leave()
        }
    }
    if enableYoudao {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.record(translateYoudao(text: text, src: src, target: target, isEn: isEn))
            group.leave()
        }
    }
    if enableApple {
        group.enter()
        runAppleTranslateAsync(text: text, src: src, target: target, isEn: isEn) { res in
            box.record(res)
            group.leave()
        }
    }
    if enableOpenAI {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.record(translateOpenAICompatible(
                text: text, target: target, baseUrl: openaiBase,
                apiKey: openaiKey, model: openaiModel, customPrompt: openaiPrompt, isEn: isEn
            ))
            group.leave()
        }
    }
    if enableGemini {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.record(translateGemini(
                text: text, target: target, baseUrl: geminiBase,
                apiKey: geminiKey, model: geminiModel, customPrompt: geminiPrompt, isEn: isEn
            ))
            group.leave()
        }
    }
    if enableOllama {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.record(translateOllamaLocal(
                text: text, target: target, baseUrl: ollamaBase, model: ollamaModel, isEn: isEn
            ))
            group.leave()
        }
    }
    if enableFree {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.record(translateZeroConfig(text: text, src: src, target: target, isEn: isEn))
            group.leave()
        }
    }

    final class WaitState: @unchecked Sendable {
        var finished = false
    }
    let waitState = WaitState()
    group.notify(queue: .main) {
        waitState.finished = true
    }
    let deadline = Date().addingTimeInterval(16.0)
    while !waitState.finished && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }

    var order = ["youdao", "openai", "gemini", "ollama", "apple", "free"]
    if primaryEngine != "auto", let idx = order.firstIndex(of: primaryEngine) {
        order.remove(at: idx)
        order.insert(primaryEngine, at: 0)
    }

    box.lock.lock()
    let snapshotTranslations = box.translations
    let snapshotDict = box.dictRes
    let snapshotDiagnostics = box.diagnostics
    box.lock.unlock()

    var out: [EngineTranslation] = []
    for key in order {
        if let item = snapshotTranslations[key], !item.text.isEmpty {
            out.append(item)
        }
    }
    if out.isEmpty, showDict, let d = snapshotDict, !d.explain.isEmpty {
        out.append(EngineTranslation(engineID: "dictionary", provider: "Dictionary", text: d.explain))
    }
    return (out, snapshotDict, snapshotDiagnostics.sorted { $0.engineID < $1.engineID })
}
