import Foundation
import PluginKit

let input = PluginInput.read()
let isEn = input.isEnglish
let dataDir = input.dataDir
let bridge = HostBridgeClient(input: input, timeoutSeconds: 4)

var vocab = dataDir.isEmpty ? [] : loadVocabList(at: URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("vocab.json"))
var history = dataDir.isEmpty ? [] : loadVocabList(at: URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent("history.json"))
var vocabIDs = Set(vocab.map(\.id))

var argv = input.arguments
var flag = argv.first ?? ""
var toast: String? = nil

if flag == "--speak", argv.count >= 3 {
    _ = bridge.call(capability: "audio", action: "speak", params: ["language": argv[1], "text": argv[2]])
    toast = isEn ? "Speaking aloud…" : "正在朗读…"
    let tail = argv.count >= 4 ? argv[3] : ""
    if tail == "--vocab" || tail == "--history" {
        let mode = String(tail.dropFirst(2))
        PluginOutput.emit(buildVocabOrHistoryCard(
            mode: mode, entries: tail == "--vocab" ? vocab : history,
            vocabIDs: vocabIDs, filterQuery: input.query, isEn: isEn, toast: toast
        ))
        exit(0)
    }
    argv = ["--translate-direct", argv[2]]
    flag = argv[0]
}

if flag == "--remove-vocab", argv.count >= 2 {
    let rid = argv[1]
    vocab.removeAll { $0.id == rid }
    vocabIDs.remove(rid)
    saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)
    PluginOutput.emit(buildVocabOrHistoryCard(
        mode: "vocab", entries: vocab, vocabIDs: vocabIDs,
        filterQuery: input.query, isEn: isEn, toast: isEn ? "Removed from Vocabulary" : "已移出生词本"
    ))
    exit(0)
}

if flag == "--save-from-history", argv.count >= 2 {
    let hid = argv[1]
    if let h = history.first(where: { $0.id == hid }), !vocabIDs.contains(hid) {
        vocab.insert(h, at: 0)
        vocabIDs.insert(hid)
    }
    saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)
    PluginOutput.emit(buildVocabOrHistoryCard(
        mode: "history", entries: history, vocabIDs: vocabIDs,
        filterQuery: input.query, isEn: isEn, toast: isEn ? "Saved to Vocabulary Book" : "已收藏至生词本"
    ))
    exit(0)
}

if flag == "--save-inline", argv.count >= 5 {
    let eid = argv[1], srcTxt = argv[2], dstTxt = argv[3], tLang = argv[4]
    let phon = argv.count >= 6 ? argv[5] : ""
    if !vocabIDs.contains(eid) {
        vocab.insert(VocabEntry(
            id: eid, source: srcTxt, translation: dstTxt,
            sourceLang: detectLanguage(srcTxt), targetLang: tLang,
            phonetic: phon, savedAt: nowStamp()
        ), at: 0)
        vocabIDs.insert(eid)
        saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)
    }
    PluginOutput.emit(buildVocabOrHistoryCard(
        mode: "vocab", entries: vocab, vocabIDs: vocabIDs,
        filterQuery: "", isEn: isEn, toast: isEn ? "Saved to Vocabulary Book" : "已加入生词本并同步免前缀索引"
    ))
    exit(0)
}

if flag == "--vocab" {
    let filt = argv.count >= 2 ? argv[1] : input.query
    PluginOutput.emit(buildVocabOrHistoryCard(mode: "vocab", entries: vocab, vocabIDs: vocabIDs, filterQuery: filt, isEn: isEn))
    exit(0)
}

if flag == "--history" {
    PluginOutput.emit(buildVocabOrHistoryCard(mode: "history", entries: history, vocabIDs: vocabIDs, filterQuery: input.query, isEn: isEn))
    exit(0)
}

if flag == "--export" {
    let (ankiP, csvP) = exportVocabFiles(vocab: vocab, exportDirRaw: input.cfgString("exportDir", default: "~/Downloads"))
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Vocabulary Exported" : "生词本已导出（Anki TSV + CSV）",
        subtitle: isEn ? "\(vocab.count) word(s) exported" : "共导出 \(vocab.count) 条词条，可直接导入 Anki 或 Excel",
        badge: "EXPORTED",
        items: [
            ViewItem(id: "anki-file", title: "Anki Flashcards: \(ankiP.lastPathComponent)", subtitle: ankiP.path, icon: "rectangle.stack.badge.plus", badge: "TSV", copyText: ankiP.path),
            ViewItem(id: "csv-file", title: "Spreadsheet Table: \(csvP.lastPathComponent)", subtitle: csvP.path, icon: "tablecells.fill", badge: "CSV", copyText: csvP.path)
        ],
        effect: PostActionEffect(toast: isEn ? "Exported Anki TSV & CSV" : "已导出 Anki TSV 与 CSV 文件")
    ))
    exit(0)
}

let primary = input.cfgString("primaryLang", default: "zh-Hans")
let secondary = input.cfgString("secondaryLang", default: "en")
let (rawText, srcOrigin): (String, String) = if flag == "--translate-direct", argv.count >= 2 {
    (argv[1], "Speak")
} else {
    resolveInputText(argv: argv, input: input, bridge: bridge)
}

if rawText.isEmpty {
    var activeEngines: [String] = []
    if input.cfgBool("enableYoudaoTranslate", default: true) { activeEngines.append(isEn ? "Youdao" : "网易有道") }
    if input.cfgBool("enableAppleTranslate", default: false) { activeEngines.append("Apple") }
    if input.cfgBool("enableOpenAI", default: false) { activeEngines.append("OpenAI") }
    if input.cfgBool("enableGemini", default: false) { activeEngines.append("Gemini") }
    let legacyOllama = input.cfgString("llmProvider", default: "none").lowercased() == "ollama"
    if input.cfgBool("enableOllama", default: legacyOllama) { activeEngines.append("Ollama") }
    if input.cfgBool("enableFreeEngine", default: false) { activeEngines.append("Free") }
    let enginesLabel = activeEngines.isEmpty ? (isEn ? "None" : "未启用") : activeEngines.joined(separator: " · ")

    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Translate Hub · Ready" : "流光译站 · 多源划词与大模型翻译",
        subtitle: isEn
            ? "Type any word/sentence above, use '>ja text' to pick target language, or trigger Selection/OCR"
            : "直接在搜索框输入单词/长句互译（可用 '>ja 文本' 指定目标语言），或使用下方快捷入口",
        badge: "\(vocab.count) SAVED",
        metrics: [
            KeyValue(key: isEn ? "Lang Pair" : "默认互译", value: "\(primary) ⇄ \(secondary)"),
            KeyValue(key: isEn ? "Engines" : "已启引擎", value: enginesLabel),
            KeyValue(key: isEn ? "Vocabulary" : "生词本", value: String(vocab.count))
        ],
        items: [
            ViewItem(id: "act-sel", title: isEn ? "Translate Frontmost Selection" : "翻译当前前台选中文本（划词即译）", subtitle: isEn ? "Reads active app selection via Accessibility (or clipboard fallback)" : "读取前台应用选中文字（无选区时自动回退剪贴板）", icon: "text.cursor", badge: "SELECTION", commandArgs: ["--selection"]),
            ViewItem(id: "act-clip", title: isEn ? "Translate Current Clipboard" : "翻译当前剪贴板文本", subtitle: isEn ? "Auto-detects language and translates immediately" : "自动识别语种并在第一/第二语言间互译", icon: "doc.on.clipboard", badge: "CLIPBOARD", commandArgs: ["--clipboard"]),
            ViewItem(id: "act-vocab", title: isEn ? "Open Vocabulary Book (\(vocab.count)) →" : "打开生词本与 Anki 导出 (\(vocab.count) 条) →", subtitle: isEn ? "Review saved words, listen to pronunciation, or export Anki TSV" : "管理收藏词条、语音朗读或导出 Anki 背单词卡片", icon: "star.square.on.square.fill", badge: "VOCAB", commandArgs: ["--vocab"]),
            ViewItem(id: "act-hist", title: isEn ? "Recent Translation History (\(history.count)) →" : "查看最近翻译历史 (\(history.count) 条) →", subtitle: isEn ? "Re-copy or star recent translations" : "回看最近查词与句子翻译记录", icon: "clock.arrow.circlepath", badge: "HISTORY", commandArgs: ["--history"])
        ]
    ))
    exit(0)
}

let (cleanText, srcLang, targetLang) = parseTargetOverride(rawQuery: rawText, primary: primary, secondary: secondary)
let (results, dictInfo, diagnostics) = runParallelTranslation(text: cleanText, src: srcLang, target: targetLang, input: input)

let showDictCard = input.cfgBool("showDictionaryCard", default: true)
let showMarkdownQuote = input.cfgBool("showMarkdownQuote", default: true)
let showEngineErrors = input.cfgBool("showEngineErrors", default: true)
let showTranslateActions = input.cfgBool("showTranslateActions", default: true)

let primaryTrans = results.first?.text ?? (isEn ? "(No translation returned — check engine settings)" : "（未获取到译文，请检查已启用引擎配置或离线语言包）")
let phoneticNote = dictInfo?.explain ?? ""
let eid = makeEntryID(sourceText: cleanText, targetLang: targetLang)

if !results.isEmpty {
    let record = VocabEntry(
        id: eid, source: cleanText, translation: primaryTrans,
        sourceLang: srcLang, targetLang: targetLang, phonetic: phoneticNote, savedAt: nowStamp()
    )
    history.removeAll { $0.id == eid }
    history.insert(record, at: 0)
    saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)

    if input.cfgBool("autoCopyResult", default: false) {
        _ = bridge.call(capability: "clipboard", action: "write", params: ["text": primaryTrans])
        toast = isEn ? "Translated & copied" : "已翻译并自动复制译文"
    }
}

func iconForEngine(_ engineID: String) -> String {
    switch engineID {
    case "youdao": return "y.circle.fill"
    case "apple": return "apple.logo"
    case "openai", "gemini", "ollama": return "sparkles"
    case "dictionary": return "character.book.closed.fill"
    default: return "globe"
    }
}

var items: [ViewItem] = []
for (idx, res) in results.enumerated() {
    let prov = res.provider
    let txt = res.text
    let rowActions: [ViewAction]? = showTranslateActions ? [
        ViewAction(id: "speak-src-\(idx)", label: isEn ? "Speak Src" : "朗读原文", commandArgs: ["--speak", ttsVoices[srcLang] ?? "en-US", cleanText]),
        ViewAction(id: "speak-dst-\(idx)", label: isEn ? "Speak Dst" : "朗读译文", commandArgs: ["--speak", ttsVoices[targetLang] ?? "en-US", txt]),
        ViewAction(
            id: "save-voc-\(idx)",
            label: vocabIDs.contains(eid) ? "Saved ⭐" : (isEn ? "Save Word" : "加入生词本"),
            commandArgs: vocabIDs.contains(eid)
                ? ["--vocab"]
                : ["--save-inline", eid, String(cleanText.prefix(200)), String(txt.prefix(300)), targetLang, String(phoneticNote.prefix(160))]
        )
    ] : nil

    items.append(ViewItem(
        id: "res-\(res.engineID)-\(idx)",
        title: txt,
        subtitle: "\(prov) · \(srcLang) → \(targetLang)" + (isEn ? " · Return to Copy" : " · 回车复制译文"),
        icon: iconForEngine(res.engineID),
        badge: String(res.engineID.uppercased().prefix(12)),
        copyText: txt,
        actions: rowActions
    ))
}

if showDictCard, let dictInfo, !dictInfo.explain.isEmpty {
    let rel = dictInfo.related.joined(separator: " · ")
    let dictActions: [ViewAction]? = showTranslateActions ? [
        ViewAction(id: "speak-src", label: isEn ? "Pronounce" : "原词发音", commandArgs: ["--speak", ttsVoices[srcLang] ?? "en-US", cleanText])
    ] : nil
    items.append(ViewItem(
        id: "dict-card",
        title: "📖 \(dictInfo.word) — \(dictInfo.explain)",
        subtitle: rel.isEmpty ? (isEn ? "Dictionary Definition" : "词典词性与核心释义") : rel,
        icon: "character.book.closed.fill",
        badge: "DICT",
        copyText: dictInfo.explain,
        actions: dictActions
    ))
}

if (showEngineErrors || results.isEmpty) && !diagnostics.isEmpty {
    for diag in diagnostics {
        items.append(ViewItem(
            id: "diag-\(diag.engineID)",
            title: "\(diag.provider)：\(diag.message)",
            subtitle: isEn ? "Engine diagnostic (toggleable in plugin settings)" : "引擎状态提示（可在插件设置中关闭错误提示）",
            icon: "exclamationmark.triangle.fill",
            tintColor: "orange",
            badge: "NOTICE",
            copyText: diag.message
        ))
    }
}

var markdownText: String? = nil
if showMarkdownQuote {
    var mdLines = ["> \(cleanText)"]
    if showDictCard, let dictInfo, !dictInfo.explain.isEmpty {
        mdLines.append("\n**\(isEn ? "Dictionary" : "词典释义")**：\(dictInfo.explain)")
    }
    markdownText = mdLines.joined(separator: "\n")
}

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: String(primaryTrans.prefix(96)),
    subtitle: "[\(srcOrigin)] \(srcLang) → \(targetLang) · \(results.count) engine(s)",
    badge: "\(srcLang.uppercased())→\(targetLang.uppercased())",
    markdown: markdownText,
    items: items,
    effect: PostActionEffect(
        toast: toast, reloadSearchIndex: true,
        statusSummary: "\(vocab.count) saved · \(history.count) history",
        statusBadge: "\(vocab.count) WORDS"
    )
))
