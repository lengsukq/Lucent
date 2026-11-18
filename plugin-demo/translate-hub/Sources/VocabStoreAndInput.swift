import Foundation
import PluginKit

let ttsVoices: [String: String] = [
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

func makeEntryID(sourceText: String, targetLang: String) -> String {
    let clean = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(DigestUtils.sha1Hex("\(targetLang):\(clean)").prefix(10))
}

func loadVocabList(at url: URL) -> [VocabEntry] {
    guard let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([VocabEntry].self, from: data) else {
        return []
    }
    return decoded
}

func saveStoreAndSyncIndex(dataDir: String, vocab: [VocabEntry], history: [VocabEntry]) {
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

func exportVocabFiles(vocab: [VocabEntry], exportDirRaw: String) -> (ankiURL: URL, csvURL: URL) {
    let raw = exportDirRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    let expanded = ((raw.isEmpty ? "~/Downloads" : raw) as NSString).expandingTildeInPath
    let outDir = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let ankiURL = outDir.appendingPathComponent("Lucent-Vocab-Anki.tsv")
    let csvURL = outDir.appendingPathComponent("Lucent-Vocab.csv")

    var tsvLines = ["#separator:tab", "#html:false", "#tags column:4"]
    for item in vocab {
        let front = item.source.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        let back = item.translation.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " / ")
        let notes = item.phonetic.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        let langTag = "lucent::\(item.targetLang.isEmpty ? "vocab" : item.targetLang)"
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

func resolveInputText(argv: [String], input: PluginInput, bridge: HostBridgeClient) -> (text: String, origin: String) {
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
        if clip.ok && !clipText.isEmpty { return (clipText, "Clipboard Fallback") }
        return ("", "Selection")
    }
    if flag == "--clipboard" {
        let clip = bridge.call(capability: "clipboard", action: "read")
        return clip.ok ? (clip.string("text").trimmingCharacters(in: .whitespacesAndNewlines), "Clipboard") : ("", "Clipboard")
    }

    let rawCtx = (input.rawJSON["context"] as? [String: Any]) ?? [:]
    var imgPath = (rawCtx["imagePath"] as? String) ?? ""
    if imgPath.isEmpty {
        let cand = (rawCtx["path"] as? String) ?? input.context?.primaryFilePath ?? ""
        if !cand.isEmpty, imageExts.contains(URL(fileURLWithPath: cand).pathExtension.lowercased()) {
            imgPath = cand
        }
    }
    if !imgPath.isEmpty {
        let ocr = bridge.call(capability: "ocr", action: "recognize", params: ["imagePath": imgPath])
        if ocr.ok { return (ocr.string("text").trimmingCharacters(in: .whitespacesAndNewlines), "Vision OCR") }
    }

    let qTrim = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !qTrim.isEmpty { return (qTrim, "Input") }
    if let ctxTxt = input.context?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !ctxTxt.isEmpty {
        let src = input.context?.source ?? ""
        return (ctxTxt, src.isEmpty ? "Context" : src)
    }
    return ("", "Idle")
}

func buildVocabOrHistoryCard(
    mode: String, entries: [VocabEntry], vocabIDs: Set<String>,
    filterQuery: String, isEn: Bool, toast: String? = nil
) -> ViewPayload {
    let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let filtered = entries.filter { q.isEmpty || $0.source.lowercased().contains(q) || $0.translation.lowercased().contains(q) }
    let isVocab = (mode == "vocab")
    var items: [ViewItem] = [
        ViewItem(
            id: "export-anki-row",
            title: isEn ? "Export Vocabulary to Anki (.tsv) & CSV →" : "一键导出生词本为 Anki 卡片 (.tsv) 与 CSV 表格 →",
            subtitle: isEn ? "\(vocabIDs.count) saved item(s)" : "当前共收藏 \(vocabIDs.count) 条生词/短语",
            icon: "square.and.arrow.up", badge: "ANKI / CSV", commandArgs: ["--export"]
        )
    ]

    for e in filtered.prefix(25) {
        let sLang = e.sourceLang ?? "en"
        let tLang = e.targetLang.isEmpty ? "en" : e.targetLang
        let saved = vocabIDs.contains(e.id)
        var actions: [ViewAction] = [
            ViewAction(id: "tts-src-\(e.id)", label: isEn ? "Speak Src" : "朗读原文", commandArgs: ["--speak", ttsVoices[sLang] ?? "en-US", e.source, "--\(mode)"]),
            ViewAction(id: "tts-\(e.id)", label: isEn ? "Speak Dst" : "朗读译文", commandArgs: ["--speak", ttsVoices[tLang] ?? "en-US", e.translation, "--\(mode)"])
        ]
        if isVocab || saved {
            actions.append(ViewAction(id: "rm-\(e.id)", label: isEn ? "Remove" : "移出生词本", style: "destructive", commandArgs: ["--remove-vocab", e.id, "--\(mode)"]))
        } else {
            actions.append(ViewAction(id: "save-\(e.id)", label: isEn ? "Save Word" : "加入生词本", commandArgs: ["--save-from-history", e.id]))
        }
        items.append(ViewItem(
            id: "row-\(e.id)", title: "\(saved ? "⭐ " : "")\(e.source)  →  \(e.translation)",
            subtitle: e.phonetic.isEmpty ? e.savedAt : e.phonetic, icon: saved ? "star.fill" : "clock",
            badge: tLang.uppercased(), copyText: e.translation, actions: actions
        ))
    }

    return ViewPayload(
        schemaVersion: 2,
        title: isEn ? (isVocab ? "Vocabulary Book" : "Translation History") : (isVocab ? "流光译站 · 生词本" : "流光译站 · 最近翻译历史"),
        subtitle: isEn ? "\(filtered.count) item(s) · Press Return to copy translation" : "共 \(filtered.count) 条 · 回车直接复制译文，支持朗读与导出 Anki",
        badge: "\(filtered.count) ITEMS",
        items: items,
        effect: PostActionEffect(toast: toast, reloadSearchIndex: true)
    )
}

func nowStamp() -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = .current
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: Date())
}
