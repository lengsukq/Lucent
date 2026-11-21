import LucentFoundation
import LucentSearch
import Foundation

public enum LauncherEngine {
    private enum ScoreTier {
        static let calculator = 10_000
        static let devTool = 9_950
        static let unitConversion = 9_900
        static let scopedPluginFallback = 9_800
        static let pluginKeywordExact = 9_550
        static let appExact = 9_450
        static let fileDedicated = 9_400
        static let pluginExact = 9_400
        static let clipboardDedicated = 9_300
        static let appPrefix = 9_150
        static let fileExplicitPrefix = 9_100
        static let pluginPrefix = 9_050
        static let pluginKeywordPrefix = 8_950
        static let appPinyinInitials = 8_900
        static let appFullPinyinPrefix = 8_550
        static let snippetMinInline = 8_400
        static let pluginContains = 8_300
        static let appContains = 8_150
        static let appPinyinContains = 7_800
        static let pluginDescContains = 7_750
        static let fileExactName = 7_300
        static let scopedPluginDefault = 7_100
        static let fileNamePrefix = 6_700
        static let clipboardInline = 6_200
        static let pluginBrowse = 6_200
        static let fileInlineFallback = 5_600
        static let scopedCommandBoost = 1_200
        static let appIdleBase = 200
    }

    public static func shouldWakeEverythingIndex(
        for query: String,
        filter: OmniFilter,
        scopedPluginID: String?
    ) -> Bool {
        if filter == .files { return true }
        guard scopedPluginID == nil else { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if stripFilePrefix(trimmed).isExplicit { return true }
        if trimmed.contains(where: { $0 == ":" || $0 == "|" || $0 == "!" }) { return true }
        if SafeMathEvaluator.evaluate(trimmed) != nil { return false }
        return trimmed.count >= 2 || trimmed.unicodeScalars.contains(where: { !$0.isASCII })
    }

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
        scopedPluginID: String? = nil,
        snippetMatcher: ((String, String?) -> [SnippetMatch])? = nil
    ) -> [LauncherCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let effectiveClip = clipboardText ?? clipboardItems.first(where: { $0.textValue != nil })?.textValue
        let resolvedCommands = pluginCommands ?? PluginCommandRegistry.registeredCommands(for: plugins)

        if let scopedID = scopedPluginID,
           let scopedPlugin = plugins.first(where: { $0.id == scopedID && $0.isValid && ($0.isBuiltin || $0.isEnabled) }) {
            return rankScopedPluginCandidates(
                plugin: scopedPlugin, query: trimmed,
                commands: resolvedCommands.filter { $0.pluginID == scopedID },
                entries: pluginSearchEntries, affinityBoosts: affinityBoosts
            )
        }

        var results: [LauncherCandidate] = []
        results.reserveCapacity(64)

        if filter == .all {
            if let math = SafeMathEvaluator.evaluate(trimmed) {
                results.append(LauncherCandidate(id: "calc:\(trimmed)", score: ScoreTier.calculator, kind: .calculator(expression: trimmed, resultText: math, badgeLabel: L10n.pick("计算", "Math"))))
            }
            if !trimmed.isEmpty {
                for (idx, tool) in DevToolkitEngine.evaluate(trimmed, clipboardText: effectiveClip).enumerated() {
                    results.append(LauncherCandidate(id: tool.id, score: ScoreTier.devTool - idx, kind: .devTool(tool)))
                }
                let matchedSnippets = snippetMatcher?(trimmed, effectiveClip) ?? SnippetStore.shared.match(query: trimmed, clipboardText: effectiveClip)
                for (idx, snip) in matchedSnippets.enumerated()
                    where trimmed.count >= 2 || trimmed.hasPrefix(";") || snip.score >= ScoreTier.snippetMinInline {
                    results.append(LauncherCandidate(id: "snippet:\(snip.id.uuidString)", score: snip.score - idx, kind: .snippet(snip)))
                }
            }
            if let conv = UnitAndCommandEngine.evaluate(trimmed) {
                results.append(LauncherCandidate(id: "conv:\(trimmed)", score: ScoreTier.unitConversion, kind: .calculator(expression: conv.expression, resultText: conv.resultText, badgeLabel: conv.badgeLabel)))
            }
            for cmd in UnitAndCommandEngine.matchCommands(query: trimmed, volumes: volumes) {
                results.append(LauncherCandidate(id: cmd.id, score: cmd.score, kind: .command(cmd)))
            }
        }

        if (filter == .all || filter == .plugins) && !scripts.isEmpty {
            let scriptHits = ScriptLibraryStore.match(
                scripts: scripts, query: trimmed,
                requireGlobalSearch: filter == .all, allowEmptyQuery: filter == .plugins
            )
            for (idx, scHit) in scriptHits.prefix(filter == .plugins ? 24 : 12).enumerated() {
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
                let baseScore = filter == .clipboard ? ScoreTier.clipboardDedicated : ScoreTier.clipboardInline
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
                resolvedCommands, query: trimmed,
                requireSearchEnabled: filter == .all, allowEmptyQuery: filter == .plugins,
                limit: filter == .plugins ? 30 : 15
            )
            for hit in cmdMatches {
                results.append(LauncherCandidate(id: "plugcmd:\(hit.command.id)", score: hit.score, kind: .pluginCommand(hit.command)))
            }
            if !needle.isEmpty {
                let pool = filter == .all ? pluginSearchEntries.filter(\.includeInGlobalSearch) : pluginSearchEntries
                for hit in PluginSearchIndex.match(entries: pool, query: trimmed, limit: filter == .plugins ? 25 : 12) {
                    results.append(LauncherCandidate(id: "plugitem:\(hit.entry.id)", score: hit.score, kind: .pluginItem(hit.entry)))
                }
            }
        }

        if filter == .all {
            for app in apps {
                let boost = usageBoosts[app.id] ?? min(launchCounts[app.id, default: 0] * 25, 450)
                if needle.isEmpty {
                    results.append(LauncherCandidate(id: app.id, score: ScoreTier.appIdleBase + boost, kind: .app(app)))
                    continue
                }
                let score = appMatchScore(app, needle: needle)
                if score > 0 { results.append(LauncherCandidate(id: app.id, score: score + boost, kind: .app(app))) }
            }
        }

        let boosted = SearchAffinityStore.applyBoosts(affinityBoosts, to: results)
        return boosted.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func appMatchScore(_ app: InstalledAppItem, needle: String) -> Int {
        let lowerName = app.nameLowercased; let lowerEng = app.englishNameLowercased
        if lowerName == needle || lowerEng == needle { return ScoreTier.appExact }
        if lowerName.hasPrefix(needle) || lowerEng.hasPrefix(needle) { return ScoreTier.appPrefix }
        if app.pinyinInitials.hasPrefix(needle) { return ScoreTier.appPinyinInitials }
        if app.fullPinyin.hasPrefix(needle) { return ScoreTier.appFullPinyinPrefix }
        if lowerName.contains(needle) || lowerEng.contains(needle) { return ScoreTier.appContains }
        if app.fullPinyin.contains(needle) || app.pinyinInitials.contains(needle)
            || (!app.altPinyinPool.isEmpty && app.altPinyinPool.contains(needle)) { return ScoreTier.appPinyinContains }
        return 0
    }

    private static func rankScopedPluginCandidates(
        plugin: PluginDescriptor, query: String,
        commands: [PluginRegisteredCommand], entries: [PluginSearchEntry],
        affinityBoosts: [String: Int] = [:]
    ) -> [LauncherCandidate] {
        var out: [LauncherCandidate] = []
        for hit in PluginCommandRegistry.matchCommands(commands, query: query, requireSearchEnabled: false, allowEmptyQuery: true, limit: 20) {
            out.append(LauncherCandidate(id: "plugcmd:\(hit.command.id)", score: hit.score + ScoreTier.scopedCommandBoost, kind: .pluginCommand(hit.command)))
        }
        for hit in PluginSearchIndex.scopedEntries(from: entries, pluginID: plugin.id, query: query, limit: 45) {
            out.append(LauncherCandidate(id: "plugitem:\(hit.entry.id)", score: hit.score, kind: .pluginItem(hit.entry)))
        }
        let runScore = out.isEmpty ? ScoreTier.scopedPluginFallback : ScoreTier.scopedPluginDefault
        out.append(LauncherCandidate(id: "plugin:\(plugin.id)", score: runScore, kind: .plugin(plugin)))
        let boosted = SearchAffinityStore.applyBoosts(affinityBoosts, to: out)
        return boosted.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func fileScore(hit: EverythingSearchHit, needle: String, filter: OmniFilter, isExplicit: Bool) -> Int {
        if filter == .files { return ScoreTier.fileDedicated }
        if isExplicit { return ScoreTier.fileExplicitPrefix }
        guard !needle.isEmpty else { return ScoreTier.fileInlineFallback }
        let nameLower = hit.name.lowercased()
        if nameLower == needle || stemLowercased(of: nameLower) == needle { return ScoreTier.fileExactName }
        if nameLower.hasPrefix(needle) { return ScoreTier.fileNamePrefix }
        return ScoreTier.fileInlineFallback
    }

    static func stemLowercased(of lowercasedFileName: String) -> String {
        guard let dot = lowercasedFileName.lastIndex(of: "."), dot > lowercasedFileName.startIndex else {
            return lowercasedFileName
        }
        return String(lowercasedFileName[..<dot])
    }

    private static func pluginScore(_ plugin: PluginDescriptor, needle: String, filter: OmniFilter) -> Int? {
        if needle.isEmpty { return filter == .plugins ? ScoreTier.pluginBrowse + plugin.effectiveRankingBoost : nil }
        let kws = plugin.effectiveKeywordsLowercased
        let name = plugin.nameLowercased
        let base: Int
        if kws.contains(where: { $0 == needle || needle.hasPrefix($0 + " ") }) { base = ScoreTier.pluginKeywordExact }
        else if name == needle { base = ScoreTier.pluginExact }
        else if name.hasPrefix(needle) { base = ScoreTier.pluginPrefix }
        else if kws.contains(where: { $0.hasPrefix(needle) }) { base = ScoreTier.pluginKeywordPrefix }
        else if name.contains(needle) { base = ScoreTier.pluginContains }
        else if plugin.descriptionLowercased.contains(needle) || plugin.localizedSearchPoolLowercased.contains(needle) { base = ScoreTier.pluginDescContains }
        else if filter == .plugins { base = ScoreTier.pluginBrowse }
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
