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
        self.kind = kind
    }
}
