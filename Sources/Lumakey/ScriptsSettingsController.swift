import AppKit
import Carbon
import LumakeyCore
import SwiftUI

private final class ScriptKeyMonitorBox {
    var token: Any?
    func stop() { if let token { NSEvent.removeMonitor(token); self.token = nil } }
    deinit { if let token { NSEvent.removeMonitor(token) } }
}

@MainActor
final class ScriptsSettingsController: ObservableObject {
    @Published var scripts: [ScriptRecord] = []
    @Published var filterQuery: String = ""
    @Published var editingID: String?
    @Published var draftTitle: String = ""
    @Published var draftEnglishTitle: String = ""
    @Published var draftSubtitle: String = ""
    @Published var draftKeywords: String = "!demo"
    @Published var draftCategory: String = "效率"
    @Published var draftRuntime: ScriptRuntime = .zsh
    @Published var draftExtension: String = "zsh"
    @Published var draftOutputMode: ScriptOutputMode = .inlinePreview
    @Published var draftIcon: String = "terminal.fill"
    @Published var draftAccentColor: String = "teal"
    @Published var useCustomSvgIcon: Bool = false
    @Published var draftSvgMarkup: String = ""
    @Published var draftHotKey: String = ""
    @Published var isRecordingHotKey: Bool = false
    @Published var draftPinnedInQuickBar: Bool = false
    @Published var draftShowInMenuBar: Bool = false
    @Published var draftIncludeInSearch: Bool = true
    @Published var draftPassClipboard: Bool = false
    @Published var draftScopes: Set<PluginResourceScope> = []
    @Published var draftCode: String = ScriptRuntime.zsh.defaultTemplateCode
    @Published var testQuery: String = ""
    @Published var isRunningTest: Bool = false
    @Published var latestRunSummary: String?
    @Published var latestRunOutput: String = ""
    @Published var statusMessage: String?

    let store: ScriptLibraryStore
    private let monitorBox = ScriptKeyMonitorBox()
    private var loadedSnapshotSignature: String = ""

    init(store: ScriptLibraryStore = .shared) {
        self.store = store
        reload()
    }

    var hasUnsavedEdits: Bool { currentDraftSignature != loadedSnapshotSignature }

    private var currentDraftSignature: String {
        "\(editingID ?? "new")|\(draftTitle)|\(draftEnglishTitle)|\(draftSubtitle)|\(draftKeywords)|\(draftCategory)|\(draftRuntime.rawValue)|\(draftExtension)|\(draftOutputMode.rawValue)|\(draftIcon)|\(draftAccentColor)|\(useCustomSvgIcon)|\(draftSvgMarkup)|\(draftHotKey)|\(draftPinnedInQuickBar)|\(draftShowInMenuBar)|\(draftIncludeInSearch)|\(draftPassClipboard)|\(draftScopes.map(\.rawValue).sorted().joined(separator: ","))|\(draftCode)"
    }

    var filteredScripts: [ScriptRecord] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return scripts }
        return scripts.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.englishTitle ?? "").localizedCaseInsensitiveContains(q)
                || $0.subtitle.localizedCaseInsensitiveContains(q)
                || $0.category.localizedCaseInsensitiveContains(q)
                || $0.keywords.contains(where: { $0.localizedCaseInsensitiveContains(q) })
        }
    }

    func reload(preferredID: String? = nil) {
        scripts = store.syncWithDisk()
        let targetID = preferredID ?? editingID
        if let id = targetID, let found = scripts.first(where: { $0.id == id }) { select(found) }
        else if let first = scripts.first { select(first) }
        else { startNew() }
    }

    func refreshFromExternalChange() {
        let latest = store.allScripts(includeDisabled: true)
        guard latest != scripts else { return }
        let dirty = hasUnsavedEdits
        scripts = latest
        guard !dirty else { return }
        if let id = editingID, let updated = latest.first(where: { $0.id == id }) { select(updated) }
        else if editingID == nil, let first = latest.first { select(first) }
    }

    func select(_ item: ScriptRecord) {
        stopHotKeyRecording()
        editingID = item.id
        draftTitle = item.title; draftEnglishTitle = item.englishTitle ?? ""; draftSubtitle = item.subtitle
        draftKeywords = item.keywords.joined(separator: ", "); draftCategory = item.category
        draftRuntime = item.runtime; draftExtension = URL(fileURLWithPath: item.fileName).pathExtension
        draftOutputMode = item.outputMode; draftIcon = item.symbolIconName; draftAccentColor = item.accentColor
        if let svg = store.readCustomIconSVG(for: item) { useCustomSvgIcon = true; draftSvgMarkup = svg }
        else { useCustomSvgIcon = false; draftSvgMarkup = "" }
        draftHotKey = item.hotKey ?? ""; draftPinnedInQuickBar = item.pinnedInQuickBar
        draftShowInMenuBar = item.showInMenuBar; draftIncludeInSearch = item.includeInGlobalSearch
        draftPassClipboard = item.passClipboard; draftScopes = item.allowedScopes
        draftCode = store.readCode(for: item)
        loadedSnapshotSignature = currentDraftSignature
    }

    func startNew(runtime: ScriptRuntime = .zsh) {
        stopHotKeyRecording()
        editingID = nil
        draftTitle = L10n.pick("新建快捷脚本", "New Quick Script"); draftEnglishTitle = ""
        draftSubtitle = L10n.pick("一键运行自定义快捷动作", "Run custom quick action")
        draftKeywords = "!quick"; draftCategory = "效率"
        draftRuntime = runtime; draftExtension = runtime == .customShebang ? "mjs" : runtime.defaultFileExtension
        draftOutputMode = .inlinePreview; draftIcon = "bolt.horizontal.fill"; draftAccentColor = "teal"
        useCustomSvgIcon = false; draftSvgMarkup = ""; draftHotKey = ""
        draftPinnedInQuickBar = false; draftShowInMenuBar = false; draftIncludeInSearch = true; draftPassClipboard = false
        draftScopes = runtime == .customShebang ? [.subprocess] : []
        draftCode = runtime.defaultTemplateCode
        loadedSnapshotSignature = currentDraftSignature
    }

    func applyRuntimeSelection(_ next: ScriptRuntime) {
        let prevTemplate = draftRuntime.defaultTemplateCode
        draftRuntime = next
        draftExtension = next == .customShebang ? "mjs" : next.defaultFileExtension
        if next == .customShebang { draftScopes.insert(.subprocess) }
        if draftCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftCode == prevTemplate {
            draftCode = next.defaultTemplateCode
        }
    }

    func fillSampleSvgIcon() {
        useCustomSvgIcon = true
        guard draftSvgMarkup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draftSvgMarkup = """
        <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
          <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#14B8A6"/><stop offset="100%" stop-color="#6366F1"/></linearGradient></defs>
          <rect x="4" y="4" width="56" height="56" rx="15" fill="url(#bg)"/>
          <path d="M22 22 L32 32 L22 42 M34 42 L44 42" fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        """
    }

    @discardableResult
    func save(notify viewModel: AppViewModel?) -> ScriptRecord? {
        stopHotKeyRecording()
        let slugSeed = editingID ?? (draftEnglishTitle.isEmpty ? draftTitle : draftEnglishTitle)
        let resolvedID = editingID ?? ScriptHeaderParser.sanitizeSlug(slugSeed)
        let kws = draftKeywords.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ext = draftExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? draftRuntime.defaultFileExtension : draftExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = scripts.first(where: { $0.id == resolvedID })

        let draft = ScriptRecord(
            id: resolvedID, title: draftTitle,
            englishTitle: draftEnglishTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draftEnglishTitle,
            subtitle: draftSubtitle, englishSubtitle: existing?.englishSubtitle,
            keywords: kws, category: draftCategory, fileName: "\(resolvedID).\(ext)",
            runtime: draftRuntime, outputMode: draftOutputMode, icon: draftIcon, accentColor: draftAccentColor,
            isEnabled: existing?.isEnabled ?? true, includeInGlobalSearch: draftIncludeInSearch,
            pinnedInQuickBar: draftPinnedInQuickBar, showInMenuBar: draftShowInMenuBar,
            hotKey: draftHotKey.isEmpty ? nil : draftHotKey, allowedScopes: draftScopes,
            passClipboard: draftPassClipboard, timeoutSeconds: existing?.timeoutSeconds ?? 10.0
        )

        do {
            let saved = try store.upsert(draft, code: draftCode, iconSvg: useCustomSvgIcon ? draftSvgMarkup : nil, clearCustomIconSvg: !useCustomSvgIcon)
            scripts = store.allScripts(); select(saved)
            viewModel?.reloadScriptsAndHotKeys()
            let msg = L10n.pick("✓ 已保存脚本：\(saved.displayTitle)", "✓ Saved script: \(saved.displayTitle)")
            statusMessage = msg; viewModel?.serviceMessage = msg
            return saved
        } catch {
            statusMessage = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
            return nil
        }
    }

    func toggleEnabled(_ item: ScriptRecord, enabled: Bool, notify viewModel: AppViewModel?) {
        var next = item; next.isEnabled = enabled
        _ = try? store.upsert(next, code: store.readCode(for: item))
        scripts = store.allScripts(); viewModel?.reloadScriptsAndHotKeys()
    }

    func delete(_ item: ScriptRecord, notify viewModel: AppViewModel?) {
        try? store.delete(id: item.id)
        if editingID == item.id { editingID = nil }
        reload(); viewModel?.reloadScriptsAndHotKeys()
        let msg = L10n.pick("已删除脚本：\(item.displayTitle)", "Deleted script: \(item.displayTitle)")
        statusMessage = msg; viewModel?.serviceMessage = msg
    }

    func runTest(notify viewModel: AppViewModel?) {
        guard let saved = save(notify: viewModel) else { return }
        isRunningTest = true
        let q = testQuery; let clip = NSPasteboard.general.string(forType: .string) ?? ""
        Task { [weak self] in
            defer { self?.isRunningTest = false }
            do {
                let res = try await ScriptRunner.runAsync(saved, query: q, clipboardText: clip, store: self?.store ?? .shared)
                guard let self else { return }
                self.latestRunSummary = "Exit \(res.exitCode) · \(res.durationMs) ms"
                let text = res.combinedOutput
                self.latestRunOutput = text.isEmpty ? L10n.pick("(无输出)", "(Empty output)") : text
            } catch {
                self?.latestRunSummary = L10n.pick("运行失败", "Failed")
                self?.latestRunOutput = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
            }
        }
    }

    func toggleHotKeyRecording() {
        if isRecordingHotKey { stopHotKeyRecording(); return }
        monitorBox.stop(); isRecordingHotKey = true
        monitorBox.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isRecordingHotKey else { return false }
                if HotKeyChord(keyCode: code, carbonModifiers: 0).isPureModifierKey { return true }
                if code == kVK_Escape && flags.isEmpty { self.stopHotKeyRecording(); return true }
                if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.isEmpty { self.draftHotKey = ""; self.stopHotKeyRecording(); return true }
                let chord = HotKeyChord(keyCode: code, modifierFlags: flags)
                if let err = chord.validationError { self.statusMessage = err; return true }
                self.draftHotKey = chord.displayString; self.stopHotKeyRecording(); return true
            }
            return consumed ? nil : event
        }
    }

    func stopHotKeyRecording() { monitorBox.stop(); isRecordingHotKey = false }
}
