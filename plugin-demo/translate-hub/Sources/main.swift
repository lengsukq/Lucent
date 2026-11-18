import Foundation
import PluginKit

private let ttsVoices: [String: String] = [
    "zh-Hans": "zh-CN",
    "en": "en-US",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "fr": "fr-FR",
    "de": "de-DE",
    "es": "es-ES"
]

private let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"]

struct VocabEntry: Codable {
    var id: String
    var source: String
    var translation: String
    var sourceLang: String?
    var targetLang: String
    var phonetic: String
    var savedAt: String
}

private func makeEntryID(sourceText: String, targetLang: String) -> String {
    let clean = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(DigestUtils.sha1Hex("\(targetLang):\(clean)").prefix(10))
}

private func loadVocabList(at url: URL) -> [VocabEntry] {
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([VocabEntry].self, from: data) else {
        return []
    }
    return decoded
}

private func saveStoreAndSyncIndex(dataDir: String, vocab: [VocabEntry], history: [VocabEntry]) {
    guard !dataDir.isEmpty else { return }
    let dd = URL(fileURLWithPath: dataDir, isDirectory: true)
    try? FileManager.default.createDirectory(at: dd, withIntermediateDirectories: true)
    if let vData = try? PluginOutput.encodeJSON(Array(vocab.prefix(300)), pretty: true) {
        try? vData.write(to: dd.appendingPathComponent("vocab.json"), options: .atomic)
    }
    if let hData = try? PluginOutput.encodeJSON(Array(history.prefix(80)), pretty: true) {
        try? hData.write(to: dd.appendingPathComponent("history.json"), options: .atomic)
    }

    let idxItems: [SearchIndexItem] = vocab.prefix(120).map { v in
        SearchIndexItem(
            id: "vocab-\(v.id)",
            title: "📖 \(v.source) → \(v.translation)",
            subtitle: v.phonetic.isEmpty ? "Vocabulary · \(v.savedAt)" : v.phonetic,
            copyText: v.translation,
            icon: "character.book.closed.fill",
            tags: [v.source.lowercased(), "vocab", "生词"],
            pinned: true,
            priority: 45,
            commandArgs: ["--vocab", v.source]
        )
    }
    PluginOutput.writeSearchIndex(idxItems, to: dataDir)
    PluginOutput.writeRuntimeStatus(
        summary: "\(vocab.count) saved · \(history.count) history",
        badge: "\(vocab.count) WORDS",
        to: dataDir
    )
}

private func csvEscape(_ field: String) -> String {
    if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return field
}

private func exportVocabFiles(vocab: [VocabEntry], exportDirRaw: String) -> (ankiURL: URL, csvURL: URL) {
    let raw = exportDirRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let expanded = ((raw.isEmpty ? "~/Downloads" : raw) as NSString).expandingTildeInPath
    let outDir = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let ankiURL = outDir.appendingPathComponent("Lumakey-Vocab-Anki.tsv")
    let csvURL = outDir.appendingPathComponent("Lumakey-Vocab.csv")

    var tsvLines = ["#separator:tab", "#html:false", "#tags column:4"]
    for item in vocab {
        let front = item.source.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        let back = item.translation.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " / ")
        let notes = item.phonetic.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        let langTag = "lumakey::\(item.targetLang.isEmpty ? "vocab" : item.targetLang)"
        tsvLines.append("\(front)\t\(back)\t\(notes)\t\(langTag)")
    }
    try? (tsvLines.joined(separator: "\n") + "\n").write(to: ankiURL, atomically: true, encoding: .utf8)

    var csvLines = ["Source,Translation,Dictionary/Notes,TargetLang,SavedAt"]
    for item in vocab {
        let row = [item.source, item.translation, item.phonetic, item.targetLang, item.savedAt]
            .map(csvEscape)
            .joined(separator: ",")
        csvLines.append(row)
    }
    var bomData = Data([0xEF, 0xBB, 0xBF])
    bomData.append(Data((csvLines.joined(separator: "\r\n") + "\r\n").utf8))
    try? bomData.write(to: csvURL, options: .atomic)

    return (ankiURL, csvURL)
}

private func resolveInputText(argv: [String], input: PluginInput, bridge: HostBridgeClient) -> (text: String, origin: String) {
    let flag = argv.first ?? ""
    if flag == "--selection" {
        let sel = bridge.call(capability: "selection", action: "read")
        let selText = sel.string("text").trimmingCharacters(in: .whitespacesAndNewlines)
        if sel.ok && !selText.isEmpty {
            let app = sel.string("sourceApp")
            return (selText, app.isEmpty ? "Selection" : app)
        }
        let clip = bridge.call(capability: "clipboard", action: "read")
        let clipText = clip.string("text").trimmingCharacters(in: .whitespacesAndNewlines)
        if clip.ok && !clipText.isEmpty {
            return (clipText, "Clipboard Fallback")
        }
        return ("", "Selection")
    }

    if flag == "--clipboard" {
        let clip = bridge.call(capability: "clipboard", action: "read")
        if clip.ok {
            return (clip.string("text").trimmingCharacters(in: .whitespacesAndNewlines), "Clipboard")
        }
        return ("", "Clipboard")
    }

    let rawCtx = (input.rawJSON["context"] as? [String: Any]) ?? [:]
    var imgPath = (rawCtx["imagePath"] as? String) ?? ""
    if imgPath.isEmpty {
        let cand = (rawCtx["path"] as? String) ?? input.context?.primaryFilePath ?? ""
        if !cand.isEmpty {
            let ext = URL(fileURLWithPath: cand).pathExtension.lowercased()
            if imageExts.contains(ext) {
                imgPath = cand
            }
        }
    }
    if !imgPath.isEmpty {
        let ocr = bridge.call(capability: "ocr", action: "recognize", params: ["imagePath": imgPath])
        if ocr.ok {
            return (ocr.string("text").trimmingCharacters(in: .whitespacesAndNewlines), "Vision OCR")
        }
    }

    let qTrim = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !qTrim.isEmpty {
        return (qTrim, "Input")
    }
    if let ctxTxt = input.context?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !ctxTxt.isEmpty {
        let src = input.context?.source ?? ""
        return (ctxTxt, src.isEmpty ? "Context" : src)
    }
    return ("", "Idle")
}

private func buildVocabOrHistoryCard(
    mode: String,
    entries: [VocabEntry],
    vocabIDs: Set<String>,
    filterQuery: String,
    isEn: Bool,
    toast: String? = nil
) -> ViewPayload {
    let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let filtered = entries.filter { e in
        q.isEmpty || e.source.lowercased().contains(q) || e.translation.lowercased().contains(q)
    }
    let isVocab = (mode == "vocab")
    var items: [ViewItem] = [
        ViewItem(
            id: "export-anki-row",
            title: isEn ? "Export Vocabulary to Anki (.tsv) & CSV →" : "一键导出生词本为 Anki 卡片 (.tsv) 与 CSV 表格 →",
            subtitle: isEn ? "\(vocabIDs.count) saved item(s)" : "当前共收藏 \(vocabIDs.count) 条生词/短语",
            icon: "square.and.arrow.up",
            badge: "ANKI / CSV",
            commandArgs: ["--export"]
        )
    ]

    for e in filtered.prefix(25) {
        let sLang = e.sourceLang ?? "en"
        let tLang = e.targetLang.isEmpty ? "en" : e.targetLang
        let saved = vocabIDs.contains(e.id)
        var actions: [ViewAction] = [
            ViewAction(
                id: "tts-src-\(e.id)",
                label: isEn ? "Speak Src" : "朗读原文",
                commandArgs: ["--speak", ttsVoices[sLang] ?? "en-US", e.source, "--\(mode)"]
            ),
            ViewAction(
                id: "tts-\(e.id)",
                label: isEn ? "Speak Dst" : "朗读译文",
                commandArgs: ["--speak", ttsVoices[tLang] ?? "en-US", e.translation, "--\(mode)"]
            )
        ]
        if isVocab || saved {
            actions.append(ViewAction(
                id: "rm-\(e.id)",
                label: isEn ? "Remove" : "移出生词本",
                style: "destructive",
                commandArgs: ["--remove-vocab", e.id, "--\(mode)"]
            ))
        } else {
            actions.append(ViewAction(
                id: "save-\(e.id)",
                label: isEn ? "Save Word" : "加入生词本",
                commandArgs: ["--save-from-history", e.id]
            ))
        }
        items.append(ViewItem(
            id: "row-\(e.id)",
            title: "\(saved ? "⭐ " : "")\(e.source)  →  \(e.translation)",
            subtitle: e.phonetic.isEmpty ? e.savedAt : e.phonetic,
            icon: saved ? "star.fill" : "clock",
            badge: tLang.uppercased(),
            copyText: e.translation,
            actions: actions
        ))
    }

    return ViewPayload(
        schemaVersion: 2,
        title: isEn
            ? (isVocab ? "Vocabulary Book" : "Translation History")
            : (isVocab ? "流光译站 · 生词本" : "流光译站 · 最近翻译历史"),
        subtitle: isEn
            ? "\(filtered.count) item(s) · Press Return to copy translation"
            : "共 \(filtered.count) 条 · 回车直接复制译文，支持朗读与导出 Anki",
        badge: "\(filtered.count) ITEMS",
        items: items,
        effect: PostActionEffect(toast: toast, reloadSearchIndex: true)
    )
}

private func nowStamp() -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: Date())
}

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
            mode: mode,
            entries: tail == "--vocab" ? vocab : history,
            vocabIDs: vocabIDs,
            filterQuery: input.query,
            isEn: isEn,
            toast: toast
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
        mode: "vocab",
        entries: vocab,
        vocabIDs: vocabIDs,
        filterQuery: input.query,
        isEn: isEn,
        toast: isEn ? "Removed from Vocabulary" : "已移出生词本"
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
        mode: "history",
        entries: history,
        vocabIDs: vocabIDs,
        filterQuery: input.query,
        isEn: isEn,
        toast: isEn ? "Saved to Vocabulary Book" : "已收藏至生词本"
    ))
    exit(0)
}

if flag == "--save-inline", argv.count >= 5 {
    let eid = argv[1], srcTxt = argv[2], dstTxt = argv[3], tLang = argv[4]
    let phon = argv.count >= 6 ? argv[5] : ""
    if !vocabIDs.contains(eid) {
        vocab.insert(VocabEntry(
            id: eid,
            source: srcTxt,
            translation: dstTxt,
            sourceLang: detectLanguage(srcTxt),
            targetLang: tLang,
            phonetic: phon,
            savedAt: nowStamp()
        ), at: 0)
        vocabIDs.insert(eid)
        saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)
    }
    PluginOutput.emit(buildVocabOrHistoryCard(
        mode: "vocab",
        entries: vocab,
        vocabIDs: vocabIDs,
        filterQuery: "",
        isEn: isEn,
        toast: isEn ? "Saved to Vocabulary Book" : "已加入生词本并同步免前缀索引"
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
            ViewItem(
                id: "anki-file",
                title: "Anki Flashcards: \(ankiP.lastPathComponent)",
                subtitle: ankiP.path,
                icon: "rectangle.stack.badge.plus",
                badge: "TSV",
                copyText: ankiP.path
            ),
            ViewItem(
                id: "csv-file",
                title: "Spreadsheet Table: \(csvP.lastPathComponent)",
                subtitle: csvP.path,
                icon: "tablecells.fill",
                badge: "CSV",
                copyText: csvP.path
            )
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
    PluginOutput.emit(ViewPayload(
        schemaVersion: 2,
        title: isEn ? "Translate Hub · Ready" : "流光译站 · 多源划词与截图翻译",
        subtitle: isEn
            ? "Type any word/sentence above, use '>ja text' to pick target language, or trigger Selection/OCR"
            : "直接在搜索框输入单词/长句互译（可用 '>ja 文本' 指定目标语言），或使用下方快捷入口",
        badge: "\(vocab.count) SAVED",
        metrics: [
            KeyValue(key: isEn ? "Lang Pair" : "默认互译", value: "\(primary) ⇄ \(secondary)"),
            KeyValue(key: isEn ? "Vocabulary" : "生词本", value: String(vocab.count)),
            KeyValue(key: isEn ? "History" : "最近历史", value: String(history.count))
        ],
        items: [
            ViewItem(
                id: "act-sel",
                title: isEn ? "Translate Frontmost Selection" : "翻译当前前台选中文本（划词即译）",
                subtitle: isEn ? "Reads active app selection via Accessibility (or clipboard fallback)" : "读取前台应用选中文字（无选区时自动回退剪贴板）",
                icon: "text.cursor",
                badge: "SELECTION",
                commandArgs: ["--selection"]
            ),
            ViewItem(
                id: "act-clip",
                title: isEn ? "Translate Current Clipboard" : "翻译当前剪贴板文本",
                subtitle: isEn ? "Auto-detects language and translates immediately" : "自动识别语种并在第一/第二语言间互译",
                icon: "doc.on.clipboard",
                badge: "CLIPBOARD",
                commandArgs: ["--clipboard"]
            ),
            ViewItem(
                id: "act-vocab",
                title: isEn ? "Open Vocabulary Book (\(vocab.count)) →" : "打开生词本与 Anki 导出 (\(vocab.count) 条) →",
                subtitle: isEn ? "Review saved words, listen to pronunciation, or export Anki TSV" : "管理收藏词条、语音朗读或导出 Anki 背单词卡片",
                icon: "star.square.on.square.fill",
                badge: "VOCAB",
                commandArgs: ["--vocab"]
            ),
            ViewItem(
                id: "act-hist",
                title: isEn ? "Recent Translation History (\(history.count)) →" : "查看最近翻译历史 (\(history.count) 条) →",
                subtitle: isEn ? "Re-copy or star recent translations" : "回看最近查词与句子翻译记录",
                icon: "clock.arrow.circlepath",
                badge: "HISTORY",
                commandArgs: ["--history"]
            )
        ]
    ))
    exit(0)
}

let (cleanText, srcLang, targetLang) = parseTargetOverride(rawQuery: rawText, primary: primary, secondary: secondary)
let (results, dictInfo) = runParallelTranslation(text: cleanText, src: srcLang, target: targetLang, input: input)

let primaryTrans = results.first?.text ?? (isEn ? "(Network unavailable or blocked)" : "（当前离线或未开启网络域，请检查插件权限）")
let phoneticNote = dictInfo?.explain ?? ""
let eid = makeEntryID(sourceText: cleanText, targetLang: targetLang)

if !results.isEmpty {
    let record = VocabEntry(
        id: eid,
        source: cleanText,
        translation: primaryTrans,
        sourceLang: srcLang,
        targetLang: targetLang,
        phonetic: phoneticNote,
        savedAt: nowStamp()
    )
    history.removeAll { $0.id == eid }
    history.insert(record, at: 0)
    saveStoreAndSyncIndex(dataDir: dataDir, vocab: vocab, history: history)

    if input.cfgBool("autoCopyResult", default: false) {
        _ = bridge.call(capability: "clipboard", action: "write", params: ["text": primaryTrans])
        toast = isEn ? "Translated & copied" : "已翻译并自动复制译文"
    }
}

var items: [ViewItem] = []
for (idx, res) in results.enumerated() {
    let prov = res.provider
    let txt = res.text
    items.append(ViewItem(
        id: "res-\(idx)",
        title: txt,
        subtitle: "\(prov) · \(srcLang) → \(targetLang)" + (isEn ? " · Return to Copy" : " · 回车复制译文"),
        icon: prov.contains("LLM") || prov.contains("Ollama") ? "sparkles" : "globe",
        badge: String(prov.uppercased().prefix(12)),
        copyText: txt,
        actions: [
            ViewAction(
                id: "speak-src-\(idx)",
                label: isEn ? "Speak Src" : "朗读原文",
                commandArgs: ["--speak", ttsVoices[srcLang] ?? "en-US", cleanText]
            ),
            ViewAction(
                id: "speak-dst-\(idx)",
                label: isEn ? "Speak Dst" : "朗读译文",
                commandArgs: ["--speak", ttsVoices[targetLang] ?? "en-US", txt]
            ),
            ViewAction(
                id: "save-voc-\(idx)",
                label: vocabIDs.contains(eid) ? "Saved ⭐" : (isEn ? "Save Word" : "加入生词本"),
                commandArgs: vocabIDs.contains(eid)
                    ? ["--vocab"]
                    : ["--save-inline", eid, String(cleanText.prefix(200)), String(txt.prefix(300)), targetLang, String(phoneticNote.prefix(160))]
            )
        ]
    ))
}

if let dictInfo, !dictInfo.explain.isEmpty {
    let rel = dictInfo.related.joined(separator: " · ")
    items.append(ViewItem(
        id: "dict-card",
        title: "📖 \(dictInfo.word) — \(dictInfo.explain)",
        subtitle: rel.isEmpty ? (isEn ? "Dictionary Definition" : "词典词性与核心释义") : rel,
        icon: "character.book.closed.fill",
        badge: "DICT",
        copyText: dictInfo.explain,
        actions: [
            ViewAction(
                id: "speak-src",
                label: isEn ? "Pronounce" : "原词发音",
                commandArgs: ["--speak", ttsVoices[srcLang] ?? "en-US", cleanText]
            )
        ]
    ))
}

var mdLines = ["> \(cleanText)"]
if let dictInfo, !dictInfo.explain.isEmpty {
    mdLines.append("\n**\(isEn ? "Dictionary" : "词典释义")**：\(dictInfo.explain)")
}

PluginOutput.emit(ViewPayload(
    schemaVersion: 2,
    title: String(primaryTrans.prefix(96)),
    subtitle: "[\(srcOrigin)] \(srcLang) → \(targetLang) · \(results.count) engine(s)",
    badge: "\(srcLang.uppercased())→\(targetLang.uppercased())",
    markdown: mdLines.joined(separator: "\n"),
    items: items,
    effect: PostActionEffect(
        toast: toast,
        reloadSearchIndex: true,
        statusSummary: "\(vocab.count) saved · \(history.count) history",
        statusBadge: "\(vocab.count) WORDS"
    )
))
