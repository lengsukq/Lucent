import LucentFoundation
import LucentSearch
import Foundation

public struct InstalledAppItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let englishName: String
    public let nameLowercased: String
    public let englishNameLowercased: String
    public let url: URL
    public let fullPinyin: String
    public let pinyinInitials: String
    public let altPinyinPool: String

    public init(name: String, englishName: String? = nil, url: URL) {
        self.id = url.standardizedFileURL.path
        self.name = name
        let resolvedEnglish = englishName ?? url.deletingPathExtension().lastPathComponent
        self.englishName = resolvedEnglish
        self.nameLowercased = name.lowercased()
        self.englishNameLowercased = resolvedEnglish.lowercased()
        self.url = url
        let (full, initials) = PinyinHelper.convert(name)
        self.fullPinyin = full
        self.pinyinInitials = initials
        self.altPinyinPool = PinyinHelper.alternatePool(name)
    }

    public var displayName: String {
        L10n.isEnglish ? englishName : name
    }
}

public enum OmniFilter: String, CaseIterable, Identifiable, Sendable {
    case all, files, clipboard, plugins
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: L10n.pick("全部", "All")
        case .files: L10n.pick("文件", "Files")
        case .clipboard: L10n.pick("剪贴板", "Clipboard")
        case .plugins: L10n.pick("插件", "Plugins")
        }
    }
    public var next: OmniFilter {
        let all = OmniFilter.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

public enum LauncherCandidateKind: Sendable, Hashable {
    case app(InstalledAppItem)
    case calculator(expression: String, resultText: String, badgeLabel: String)
    case devTool(DevToolResult)
    case snippet(SnippetMatch)
    case script(ScriptMatch)
    case fileHit(EverythingSearchHit)
    case clipboard(ClipboardEntry)
    case plugin(PluginDescriptor)
    case pluginCommand(PluginRegisteredCommand)
    case pluginItem(PluginSearchEntry)
    case command(CommandSuggestion)
}

public struct LauncherCandidate: Identifiable, Sendable, Hashable {
    public let id: String
    public let score: Int
    public let kind: LauncherCandidateKind

    public init(id: String, score: Int, kind: LauncherCandidateKind) {
        self.id = id
        self.score = score
        self.kind = VerticalScoreClamp.clamp(kind)
    }
}

private enum VerticalScoreClamp {
    static func clamp(_ kind: LauncherCandidateKind) -> LauncherCandidateKind { kind }
}

public enum LauncherEngine {
    public static func rankCandidates(
        query: String,
        filter: OmniFilter = .all,
        apps: [InstalledAppItem],
        plugins: [PluginDescriptor],
        pluginCommands: [PluginRegisteredCommand]? = nil,
        pluginSearchEntries: [PluginSearchEntry] = [],
        scripts: [ScriptRecord] = [],
        clipboardItems: [ClipboardEntry] = [],
        volumes: [VolumeSummary] = [],
        everythingIndex: EverythingIndex? = nil,
        launchCounts: [String: Int] = [:],
        usageBoosts: [String: Int] = [:],
        affinityBoosts: [String: Int] = [:],
        clipboardText: String? = nil,
        scopedPluginID: String? = nil
    ) -> [LauncherCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let effectiveClip = clipboardText ?? clipboardItems.first(where: { $0.textValue != nil })?.textValue
        let resolvedCommands = pluginCommands ?? PluginCommandRegistry.registeredCommands(for: plugins)

        if let scopedID = scopedPluginID,
           let scopedPlugin = plugins.first(where: { $0.id == scopedID && $0.isValid && ($0.isBuiltin || $0.isEnabled) }) {
            return rankScopedPluginCandidates(
                plugin: scopedPlugin,
                query: trimmed,
                commands: resolvedCommands.filter { $0.pluginID == scopedID },
                entries: pluginSearchEntries,
                affinityBoosts: affinityBoosts
            )
        }

        var results: [LauncherCandidate] = []
        results.reserveCapacity(64)

        if filter == .all {
            if let math = SafeMathEvaluator.evaluate(trimmed) {
                results.append(LauncherCandidate(id: "calc:\(trimmed)", score: 10_000, kind: .calculator(expression: trimmed, resultText: math, badgeLabel: L10n.pick("计算", "Math"))))
            }
            if !trimmed.isEmpty {
                for (idx, tool) in DevToolkitEngine.evaluate(trimmed, clipboardText: effectiveClip).enumerated() {
                    results.append(LauncherCandidate(id: tool.id, score: 9_950 - idx, kind: .devTool(tool)))
                }
                for (idx, snip) in SnippetStore.shared.match(query: trimmed, clipboardText: effectiveClip).enumerated()
                    where trimmed.count >= 2 || trimmed.hasPrefix(";") || snip.score >= 8_400 {
                    results.append(LauncherCandidate(id: "snippet:\(snip.id.uuidString)", score: snip.score - idx, kind: .snippet(snip)))
                }
            }
            if let conv = UnitAndCommandEngine.evaluate(trimmed) {
                results.append(LauncherCandidate(id: "conv:\(trimmed)", score: 9_900, kind: .calculator(expression: conv.expression, resultText: conv.resultText, badgeLabel: conv.badgeLabel)))
            }
            for cmd in UnitAndCommandEngine.matchCommands(query: trimmed, volumes: volumes) {
                results.append(LauncherCandidate(id: cmd.id, score: cmd.score, kind: .command(cmd)))
            }
        }

        if (filter == .all || filter == .plugins) && !scripts.isEmpty {
            let scriptHits = ScriptLibraryStore.match(
                scripts: scripts,
                query: trimmed,
                requireGlobalSearch: filter == .all,
                allowEmptyQuery: filter == .plugins
            )
            let limit = filter == .plugins ? 24 : 12
            for (idx, scHit) in scriptHits.prefix(limit).enumerated() {
                results.append(LauncherCandidate(id: "script:\(scHit.id)", score: scHit.score - idx, kind: .script(scHit)))
            }
        }

        if let everythingIndex, filter == .all || filter == .files {
            let fileSpec = stripFilePrefix(trimmed)
            if filter == .files || !fileSpec.query.isEmpty {
                let limit = filter == .files ? 40 : (affinityBoosts.isEmpty ? 12 : 24)
                for (idx, hit) in everythingIndex.search(queryText: fileSpec.query, limit: limit).enumerated() {
                    let baseScore = fileScore(hit: hit, needle: needle, filter: filter, isExplicit: fileSpec.isExplicit)
                    results.append(LauncherCandidate(id: "file:\(hit.id)", score: baseScore - idx, kind: .fileHit(hit)))
                }
            }
        }

        if filter == .all || filter == .clipboard {
            let filteredClips = ClipboardService.filter(clipboardItems, query: trimmed, category: .all)
            let limit = filter == .clipboard ? 40 : (needle.isEmpty ? 0 : 6)
            for (idx, clip) in filteredClips.prefix(limit).enumerated() {
                let baseScore = filter == .clipboard ? 9_300 : 6_200
                results.append(LauncherCandidate(id: "clip:\(clip.id.uuidString)", score: baseScore - idx, kind: .clipboard(clip)))
            }
        }

        if filter == .all || filter == .plugins {
            for plugin in plugins where plugin.isValid && (plugin.isBuiltin || plugin.isEnabled) {
                if filter == .all && (!plugin.isEnabled || !plugin.includeInGlobalSearch) { continue }
                if filter == .plugins && !plugin.isBuiltin && !plugin.isEnabled { continue }
                if let score = pluginScore(plugin, needle: needle, filter: filter) {
                    results.append(LauncherCandidate(id: "plugin:\(plugin.id)", score: score, kind: .plugin(plugin)))
                }
            }

            let cmdMatches = PluginCommandRegistry.matchCommands(
                resolvedCommands,
                query: trimmed,
                requireSearchEnabled: filter == .all,
                allowEmptyQuery: filter == .plugins,
                limit: filter == .plugins ? 30 : 15
            )
            for hit in cmdMatches {
                results.append(LauncherCandidate(id: "plugcmd:\(hit.command.id)", score: hit.score, kind: .pluginCommand(hit.command)))
            }

            if !needle.isEmpty {
                let pool = filter == .all ? pluginSearchEntries.filter(\.includeInGlobalSearch) : pluginSearchEntries
                let itemLimit = filter == .plugins ? 25 : 12
                for hit in PluginSearchIndex.match(entries: pool, query: trimmed, limit: itemLimit) {
                    results.append(LauncherCandidate(id: "plugitem:\(hit.entry.id)", score: hit.score, kind: .pluginItem(hit.entry)))
                }
            }
        }

        if filter == .all {
            for app in apps {
                let boost = usageBoosts[app.id] ?? min(launchCounts[app.id, default: 0] * 25, 450)
                if needle.isEmpty {
                    results.append(LauncherCandidate(id: app.id, score: 200 + boost, kind: .app(app)))
                    continue
                }
                let lowerName = app.nameLowercased; let lowerEng = app.englishNameLowercased
                var score = 0
                if lowerName == needle || lowerEng == needle { score = 9_450 }
                else if lowerName.hasPrefix(needle) || lowerEng.hasPrefix(needle) { score = 9_150 }
                else if app.pinyinInitials.hasPrefix(needle) { score = 8_900 }
                else if app.fullPinyin.hasPrefix(needle) { score = 8_550 }
                else if lowerName.contains(needle) || lowerEng.contains(needle) { score = 8_150 }
                else if app.fullPinyin.contains(needle) || app.pinyinInitials.contains(needle)
                    || (!app.altPinyinPool.isEmpty && app.altPinyinPool.contains(needle)) { score = 7_800 }
                if score > 0 { results.append(LauncherCandidate(id: app.id, score: score + boost, kind: .app(app))) }
            }
        }

        let boosted = SearchAffinityStore.applyBoosts(affinityBoosts, to: results)
        return boosted.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func rankScopedPluginCandidates(
        plugin: PluginDescriptor,
        query: String,
        commands: [PluginRegisteredCommand],
        entries: [PluginSearchEntry],
        affinityBoosts: [String: Int] = [:]
    ) -> [LauncherCandidate] {
        var out: [LauncherCandidate] = []
        let cmdHits = PluginCommandRegistry.matchCommands(
            commands, query: query, requireSearchEnabled: false, allowEmptyQuery: true, limit: 20
        )
        for hit in cmdHits {
            out.append(LauncherCandidate(id: "plugcmd:\(hit.command.id)", score: hit.score + 1_200, kind: .pluginCommand(hit.command)))
        }
        let itemHits = PluginSearchIndex.scopedEntries(from: entries, pluginID: plugin.id, query: query, limit: 45)
        for hit in itemHits {
            out.append(LauncherCandidate(id: "plugitem:\(hit.entry.id)", score: hit.score, kind: .pluginItem(hit.entry)))
        }
        let runScore = out.isEmpty ? 9_800 : 7_100
        out.append(LauncherCandidate(id: "plugin:\(plugin.id)", score: runScore, kind: .plugin(plugin)))
        let boosted = SearchAffinityStore.applyBoosts(affinityBoosts, to: out)
        return boosted.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func fileScore(
        hit: EverythingSearchHit,
        needle: String,
        filter: OmniFilter,
        isExplicit: Bool
    ) -> Int {
        if filter == .files { return 9_400 }
        if isExplicit { return 9_100 }
        guard !needle.isEmpty else { return 5_600 }
        let nameLower = hit.name.lowercased()
        let stemLower = URL(fileURLWithPath: hit.name).deletingPathExtension().lastPathComponent.lowercased()
        if nameLower == needle || stemLower == needle { return 7_300 }
        if nameLower.hasPrefix(needle) { return 6_700 }
        return 5_600
    }

    private static func pluginScore(_ plugin: PluginDescriptor, needle: String, filter: OmniFilter) -> Int? {
        if needle.isEmpty { return filter == .plugins ? 6_200 + plugin.effectiveRankingBoost : nil }
        let kws = plugin.effectiveKeywordsLowercased
        let name = plugin.nameLowercased
        let base: Int
        if kws.contains(where: { $0 == needle || needle.hasPrefix($0 + " ") }) { base = 9_550 }
        else if name == needle { base = 9_400 }
        else if name.hasPrefix(needle) { base = 9_050 }
        else if kws.contains(where: { $0.hasPrefix(needle) }) { base = 8_950 }
        else if name.contains(needle) { base = 8_300 }
        else if plugin.descriptionLowercased.contains(needle) || plugin.localizedSearchPoolLowercased.contains(needle) { base = 7_750 }
        else if filter == .plugins { base = 6_200 }
        else { return nil }
        return base + plugin.effectiveRankingBoost
    }

    private static func stripFilePrefix(_ raw: String) -> (query: String, isExplicit: Bool) {
        let lower = raw.lowercased()
        for p in ["open ", "find ", "f "] where lower.hasPrefix(p) {
            let query = String(raw.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            return (query, !query.isEmpty)
        }
        return (raw, false)
    }
}
