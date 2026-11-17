import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
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
    public static func discoverInstalledApps() -> [InstalledAppItem] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seenPaths = Set<String>()
        var apps: [InstalledAppItem] = []

        func appendApp(at url: URL) {
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), seenPaths.insert(path).inserted else { return }
            let eng = url.deletingPathExtension().lastPathComponent
            let locName = localizedName(forAppAt: url) ?? eng
            apps.append(InstalledAppItem(name: locName, englishName: eng, url: url))
        }

        appendApp(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension.lowercased() == "app" { appendApp(at: url) }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func localizedName(forAppAt url: URL) -> String? {
        let loctable = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard let data = try? Data(contentsOf: loctable),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let zh = (dict["zh_CN"] as? [String: Any]) ?? (dict["zh-Hans"] as? [String: Any])
        else { return nil }
        return (zh["CFBundleDisplayName"] as? String) ?? (zh["CFBundleName"] as? String)
    }

    public static func rankCandidates(
        query: String,
        filter: OmniFilter = .all,
        apps: [InstalledAppItem],
        plugins: [PluginDescriptor],
        pluginCommands: [PluginRegisteredCommand]? = nil,
        pluginSearchEntries: [PluginSearchEntry] = [],
        clipboardItems: [ClipboardEntry] = [],
        volumes: [VolumeSummary] = [],
        everythingIndex: EverythingIndex? = nil,
        launchCounts: [String: Int] = [:],
        usageBoosts: [String: Int] = [:],
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
                entries: pluginSearchEntries
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

        if let everythingIndex, filter == .all || filter == .files {
            let fileQuery = stripFilePrefix(trimmed)
            if filter == .files || !fileQuery.isEmpty {
                let limit = filter == .files ? 40 : 12
                for (idx, hit) in everythingIndex.search(queryText: fileQuery, limit: limit).enumerated() {
                    let bonus = filter == .files ? 9_400 : 8_100
                    results.append(LauncherCandidate(id: "file:\(hit.id)", score: bonus - idx, kind: .fileHit(hit)))
                }
            }
        }

        if filter == .all || filter == .clipboard {
            let filteredClips = ClipboardService.filter(clipboardItems, query: trimmed, category: .all)
            let limit = filter == .clipboard ? 40 : (needle.isEmpty ? 0 : 6)
            for (idx, clip) in filteredClips.prefix(limit).enumerated() {
                let baseScore = filter == .clipboard ? 9_300 : 7_500
                results.append(LauncherCandidate(id: "clip:\(clip.id.uuidString)", score: baseScore - idx, kind: .clipboard(clip)))
            }
        }

        if filter == .all || filter == .plugins {
            for plugin in plugins where plugin.isValid && (plugin.isBuiltin || plugin.isEnabled) {
                if filter == .all && (!plugin.isEnabled || !plugin.includeInGlobalSearch) { continue }
                if filter == .plugins && !plugin.isBuiltin && !plugin.isEnabled { continue }
                let kws = plugin.effectiveKeywordsLowercased
                let kwHit = !needle.isEmpty && kws.contains {
                    $0 == needle || needle.hasPrefix($0 + " ") || $0.hasPrefix(needle)
                }
                let nameHit = !needle.isEmpty && (plugin.nameLowercased.contains(needle)
                    || plugin.descriptionLowercased.contains(needle)
                    || plugin.localizedSearchPoolLowercased.contains(needle))
                if filter == .plugins || kwHit || nameHit {
                    let base = kwHit ? 9_500 : (nameHit ? 7_800 : 6_200)
                    results.append(LauncherCandidate(id: "plugin:\(plugin.id)", score: base + plugin.effectiveRankingBoost, kind: .plugin(plugin)))
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
                if lowerName == needle || lowerEng == needle { score = 9_000 }
                else if lowerName.hasPrefix(needle) || lowerEng.hasPrefix(needle) { score = 8_500 }
                else if app.pinyinInitials.hasPrefix(needle) { score = 8_200 }
                else if app.fullPinyin.hasPrefix(needle) { score = 7_600 }
                else if lowerName.contains(needle) || lowerEng.contains(needle) { score = 5_800 }
                else if app.fullPinyin.contains(needle) || app.pinyinInitials.contains(needle)
                    || (!app.altPinyinPool.isEmpty && app.altPinyinPool.contains(needle)) { score = 4_800 }
                if score > 0 { results.append(LauncherCandidate(id: app.id, score: score + boost, kind: .app(app))) }
            }
        }

        return results.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func rankScopedPluginCandidates(
        plugin: PluginDescriptor,
        query: String,
        commands: [PluginRegisteredCommand],
        entries: [PluginSearchEntry]
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
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
    }

    private static func stripFilePrefix(_ raw: String) -> String {
        let lower = raw.lowercased()
        for p in ["open ", "find ", "f "] where lower.hasPrefix(p) {
            return String(raw.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }
}
