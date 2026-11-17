import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public struct PluginCommandSpec: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let keywords: [String]
    public let icon: String?
    public let hotkey: String?
    public let arguments: [String]
    public let passQuery: Bool?
    public let silentWhenHotKeyTriggered: Bool?
    public let includeInGlobalSearch: Bool?

    public init(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String] = [],
        icon: String? = nil,
        hotkey: String? = nil,
        arguments: [String] = [],
        passQuery: Bool? = nil,
        silentWhenHotKeyTriggered: Bool? = nil,
        includeInGlobalSearch: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.icon = icon
        self.hotkey = hotkey
        self.arguments = arguments
        self.passQuery = passQuery
        self.silentWhenHotKeyTriggered = silentWhenHotKeyTriggered
        self.includeInGlobalSearch = includeInGlobalSearch
    }
}

public struct PluginRegisteredCommand: Identifiable, Sendable, Hashable {
    public let id: String
    public let pluginID: String
    public let pluginName: String
    public let pluginIcon: String?
    public let pluginAccentColor: String?
    public let pluginCustomIconURL: URL?
    public let isBuiltin: Bool
    public let isPluginEnabled: Bool
    public let command: PluginCommandSpec
    public let localizedTitle: String
    public let localizedSubtitle: String
    public let effectiveHotKey: String?
    public let isSearchEnabled: Bool
    public let isQuickButtonEnabled: Bool
    public let rankingBoost: Int
    public let titleLowercased: String
    public let localizedTitleLowercased: String
    public let subtitleLowercased: String
    public let keywordsLowercased: [String]
    public let fullPinyin: String
    public let pinyinInitials: String

    public var symbolName: String {
        if let icon = command.icon, !icon.isEmpty, !PluginIconResolver.looksLikeRelativeFilePath(icon) { return icon }
        if let pluginIcon, !pluginIcon.isEmpty, !PluginIconResolver.looksLikeRelativeFilePath(pluginIcon) { return pluginIcon }
        return isBuiltin ? "sparkles" : "puzzlepiece.extension.fill"
    }

    public init(plugin: PluginDescriptor, command: PluginCommandSpec) {
        self.id = "\(plugin.id)::\(command.id)"
        self.pluginID = plugin.id
        self.pluginName = plugin.displayName
        self.pluginIcon = plugin.manifest.icon
        self.pluginAccentColor = plugin.manifest.accentColor
        self.pluginCustomIconURL = PluginIconResolver.resolveBundleIconURL(rawIcon: command.icon, in: plugin.directoryURL)
            ?? plugin.customIconURL
        self.isBuiltin = plugin.isBuiltin
        self.isPluginEnabled = plugin.isEnabled
        self.command = command
        let locTitle = plugin.manifest.localizedCommandTitle(command)
        let locSub = plugin.manifest.localizedCommandSubtitle(command)
        self.localizedTitle = locTitle
        self.localizedSubtitle = locSub
        self.effectiveHotKey = plugin.effectiveCommandHotKey(for: command.id)
        self.isSearchEnabled = plugin.isCommandSearchEnabled(command)
        self.isQuickButtonEnabled = plugin.overrides.quickButtonCommandIDs.contains(command.id)
        self.rankingBoost = plugin.effectiveRankingBoost
        self.titleLowercased = command.title.lowercased()
        self.localizedTitleLowercased = locTitle.lowercased()
        self.subtitleLowercased = "\(command.subtitle) \(locSub)".lowercased()
        self.keywordsLowercased = command.keywords.map { $0.lowercased() }
        let combined = "\(command.title) \(locTitle) \(command.keywords.joined(separator: " "))"
        let (full, initials) = PinyinHelper.convert(combined)
        self.fullPinyin = full
        self.pinyinInitials = initials
    }
}

public enum PluginQuickButtonTarget: Sendable, Hashable, Equatable {
    case plugin(pluginID: String)
    case command(pluginID: String, commandID: String)
}

public struct PluginQuickButtonItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let shortTitle: String
    public let subtitle: String
    public let symbolName: String
    public let customIconURL: URL?
    public let accentColor: String?
    public let pluginID: String
    public let pluginName: String
    public let isBuiltin: Bool
    public let target: PluginQuickButtonTarget

    public init(
        id: String,
        title: String,
        shortTitle: String,
        subtitle: String,
        symbolName: String,
        customIconURL: URL? = nil,
        accentColor: String? = nil,
        pluginID: String,
        pluginName: String,
        isBuiltin: Bool,
        target: PluginQuickButtonTarget
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.customIconURL = customIconURL
        self.accentColor = accentColor
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.isBuiltin = isBuiltin
        self.target = target
    }
}

public enum PluginCommandRegistry {
    public static func isSafeCommandID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" || $0 == "_" }
    }

    public static func registeredCommands(
        for plugins: [PluginDescriptor],
        includeDisabledPlugins: Bool = false
    ) -> [PluginRegisteredCommand] {
        var out: [PluginRegisteredCommand] = []
        for plugin in plugins where plugin.isValid {
            let active = plugin.isBuiltin || includeDisabledPlugins || plugin.isEnabled
            guard active else { continue }
            for spec in plugin.declaredCommands {
                out.append(PluginRegisteredCommand(plugin: plugin, command: spec))
            }
        }
        return out
    }

    public static func enabledQuickButtons(for plugins: [PluginDescriptor]) -> [PluginQuickButtonItem] {
        var items: [PluginQuickButtonItem] = []
        for plugin in plugins where plugin.isValid && (plugin.isBuiltin || plugin.isEnabled) {
            if plugin.pinnedInOverlay {
                let pName = plugin.displayName
                items.append(PluginQuickButtonItem(
                    id: "qb-plugin:\(plugin.id)",
                    title: pName,
                    shortTitle: compactLabel(pName),
                    subtitle: plugin.displayDescription,
                    symbolName: plugin.symbolIconName,
                    customIconURL: plugin.customIconURL,
                    accentColor: plugin.manifest.accentColor,
                    pluginID: plugin.id,
                    pluginName: pName,
                    isBuiltin: plugin.isBuiltin,
                    target: .plugin(pluginID: plugin.id)
                ))
            }
            let enabledSet = Set(plugin.overrides.quickButtonCommandIDs)
            guard !enabledSet.isEmpty else { continue }
            for spec in plugin.declaredCommands where enabledSet.contains(spec.id) {
                let reg = PluginRegisteredCommand(plugin: plugin, command: spec)
                items.append(PluginQuickButtonItem(
                    id: "qb-cmd:\(plugin.id)::\(spec.id)",
                    title: reg.localizedTitle,
                    shortTitle: compactLabel(reg.localizedTitle),
                    subtitle: "\(plugin.displayName) · \(reg.localizedSubtitle)",
                    symbolName: reg.symbolName,
                    customIconURL: reg.pluginCustomIconURL,
                    accentColor: plugin.manifest.accentColor,
                    pluginID: plugin.id,
                    pluginName: plugin.displayName,
                    isBuiltin: plugin.isBuiltin,
                    target: .command(pluginID: plugin.id, commandID: spec.id)
                ))
            }
        }
        return items
    }

    public static func matchCommands(
        _ commands: [PluginRegisteredCommand],
        query: String,
        requireSearchEnabled: Bool,
        allowEmptyQuery: Bool = false,
        limit: Int = 20
    ) -> [(command: PluginRegisteredCommand, score: Int)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let pool = requireSearchEnabled ? commands.filter(\.isSearchEnabled) : commands
        if needle.isEmpty {
            guard allowEmptyQuery else { return [] }
            return pool.prefix(limit).enumerated().map { idx, cmd in
                let qbBonus = cmd.isQuickButtonEnabled ? 180 : 0
                return (cmd, 7_400 + cmd.rankingBoost + qbBonus - idx)
            }
        }

        var scored: [(PluginRegisteredCommand, Int)] = []
        for cmd in pool {
            var base = 0
            if cmd.keywordsLowercased.contains(needle) { base = 9_620 }
            else if cmd.keywordsLowercased.contains(where: { needle.hasPrefix($0 + " ") }) { base = 9_580 }
            else if cmd.titleLowercased == needle || cmd.localizedTitleLowercased == needle { base = 9_350 }
            else if cmd.keywordsLowercased.contains(where: { $0.hasPrefix(needle) }) { base = 9_120 }
            else if cmd.titleLowercased.hasPrefix(needle) || cmd.localizedTitleLowercased.hasPrefix(needle) { base = 8_820 }
            else if cmd.pinyinInitials.hasPrefix(needle) { base = 8_460 }
            else if cmd.fullPinyin.hasPrefix(needle) { base = 7_960 }
            else if cmd.titleLowercased.contains(needle) || cmd.localizedTitleLowercased.contains(needle) { base = 7_150 }
            else if cmd.keywordsLowercased.contains(where: { $0.contains(needle) }) { base = 6_850 }
            else if cmd.pinyinInitials.contains(needle) || cmd.fullPinyin.contains(needle) { base = 6_350 }
            else if cmd.subtitleLowercased.contains(needle) { base = 5_900 }

            if base > 0 {
                let qbBonus = cmd.isQuickButtonEnabled ? 160 : 0
                scored.append((cmd, base + cmd.rankingBoost + qbBonus))
            }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
        return Array(scored.prefix(limit))
    }

    public static func extractTrailingQuery(rawQuery: String, for command: PluginRegisteredCommand) -> String {
        guard command.command.passQuery != false else { return "" }
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for kw in command.command.keywords.sorted(by: { $0.count > $1.count }) {
            let kwLower = kw.lowercased()
            if lower.hasPrefix(kwLower + " ") {
                return String(trimmed.dropFirst(kw.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func compactLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 8 { return trimmed }
        return String(trimmed.prefix(8))
    }
}
