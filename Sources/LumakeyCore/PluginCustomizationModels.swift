import Foundation

public enum PluginContextKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case url
    case text
    case image
    case file
    case directory

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .url: L10n.pick("网页链接 (URL)", "Web URL")
        case .text: L10n.pick("纯文本与识字内容", "Plain Text & OCR")
        case .image: L10n.pick("图片与截图文件", "Image & Screenshot")
        case .file: L10n.pick("本地文件", "Local File")
        case .directory: L10n.pick("本地文件夹", "Local Folder")
        }
    }

    public var symbolName: String {
        switch self {
        case .url: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .directory: "folder"
        }
    }
}

public struct PluginContextPayload: Codable, Sendable, Hashable, Equatable {
    public let kind: PluginContextKind
    public let text: String?
    public let url: String?
    public let filePaths: [String]?
    public let source: String

    public init(
        kind: PluginContextKind,
        text: String? = nil,
        url: String? = nil,
        filePaths: [String]? = nil,
        source: String
    ) {
        self.kind = kind
        self.text = text
        self.url = url
        self.filePaths = filePaths
        self.source = source
    }

    public var primaryQuery: String {
        if let url, !url.isEmpty { return url }
        if let text, !text.isEmpty { return text }
        return filePaths?.first ?? ""
    }

    public func toJSONObject() -> [String: Any] {
        var obj: [String: Any] = ["kind": kind.rawValue, "source": source]
        if let text { obj["text"] = text }
        if let url { obj["url"] = url }
        if let filePaths { obj["filePaths"] = filePaths }
        return obj
    }
}

public enum PluginContextMatcher {
    public static func matchingPlugins(
        in plugins: [PluginDescriptor],
        for context: PluginContextPayload
    ) -> [PluginDescriptor] {
        plugins.filter { plugin in
            !plugin.isBuiltin && plugin.isValid && plugin.isEnabled
                && plugin.declaredContextKinds.contains(context.kind)
        }
        .sorted { lhs, rhs in
            if lhs.effectiveRankingBoost != rhs.effectiveRankingBoost {
                return lhs.effectiveRankingBoost > rhs.effectiveRankingBoost
            }
            return lhs.id < rhs.id
        }
    }

    public static func payloadFromClipboard(_ entry: ClipboardEntry) -> PluginContextPayload? {
        switch entry.payloadKind {
        case .image(let url, _):
            return PluginContextPayload(kind: .image, filePaths: [url.path], source: "clipboard")
        case .file(let url):
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir && MediaClassifier.classify(url: url, isDirectory: false) == .image {
                return PluginContextPayload(kind: .image, filePaths: [url.path], source: "clipboard")
            }
            return PluginContextPayload(kind: isDir ? .directory : .file, filePaths: [url.path], source: "clipboard")
        case .colorHex(let hex):
            return PluginContextPayload(kind: .text, text: hex, source: "clipboard")
        case .text:
            guard let raw = entry.textValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            if let parsed = URL(string: raw),
               let scheme = parsed.scheme?.lowercased(),
               (scheme == "http" || scheme == "https"),
               parsed.host != nil {
                return PluginContextPayload(kind: .url, text: raw, url: raw, source: "clipboard")
            }
            return PluginContextPayload(kind: .text, text: raw, source: "clipboard")
        }
    }

    public static func payloadFromFiles(_ urls: [URL], source: String = "workspace") -> PluginContextPayload? {
        guard let first = urls.first else { return nil }
        let paths = urls.map { $0.standardizedFileURL.path }
        if urls.count == 1 {
            let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                return PluginContextPayload(kind: .directory, filePaths: paths, source: source)
            }
            if MediaClassifier.classify(url: first, isDirectory: false) == .image {
                return PluginContextPayload(kind: .image, filePaths: paths, source: source)
            }
        }
        return PluginContextPayload(kind: .file, filePaths: paths, source: source)
    }

    public static func payloadFromText(_ rawText: String, source: String) -> PluginContextPayload? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = URL(string: trimmed),
           let scheme = parsed.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           parsed.host != nil {
            return PluginContextPayload(kind: .url, text: trimmed, url: trimmed, source: source)
        }
        return PluginContextPayload(kind: .text, text: trimmed, source: source)
    }
}

public struct PluginUserOverrides: Codable, Sendable, Hashable, Equatable {
    public var customKeywords: [String]?
    public var customHotKey: String?
    public var commandHotKeys: [String: String]
    public var pinnedInOverlay: Bool
    public var includeInGlobalSearch: Bool
    public var showInSettingsSidebar: Bool
    public var priorityBoost: Int
    public var launchCount: Int
    public var lastUsedAtEpoch: Double?
    public var quickButtonCommandIDs: [String]
    public var disabledCommandIDs: [String]

    enum CodingKeys: String, CodingKey {
        case customKeywords, customHotKey, commandHotKeys, pinnedInOverlay, includeInGlobalSearch
        case showInSettingsSidebar, priorityBoost, launchCount, lastUsedAtEpoch
        case quickButtonCommandIDs, disabledCommandIDs
    }

    public init(
        customKeywords: [String]? = nil,
        customHotKey: String? = nil,
        commandHotKeys: [String: String] = [:],
        pinnedInOverlay: Bool = false,
        includeInGlobalSearch: Bool = true,
        showInSettingsSidebar: Bool = true,
        priorityBoost: Int = 0,
        launchCount: Int = 0,
        lastUsedAtEpoch: Double? = nil,
        quickButtonCommandIDs: [String] = [],
        disabledCommandIDs: [String] = []
    ) {
        self.customKeywords = customKeywords
        self.customHotKey = customHotKey
        self.commandHotKeys = commandHotKeys
        self.pinnedInOverlay = pinnedInOverlay
        self.includeInGlobalSearch = includeInGlobalSearch
        self.showInSettingsSidebar = showInSettingsSidebar
        self.priorityBoost = min(max(priorityBoost, -200), 300)
        self.launchCount = max(0, launchCount)
        self.lastUsedAtEpoch = lastUsedAtEpoch
        self.quickButtonCommandIDs = quickButtonCommandIDs
        self.disabledCommandIDs = disabledCommandIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.customKeywords = try c.decodeIfPresent([String].self, forKey: .customKeywords)
        self.customHotKey = try c.decodeIfPresent(String.self, forKey: .customHotKey)
        self.commandHotKeys = try c.decodeIfPresent([String: String].self, forKey: .commandHotKeys) ?? [:]
        self.pinnedInOverlay = try c.decodeIfPresent(Bool.self, forKey: .pinnedInOverlay) ?? false
        self.includeInGlobalSearch = try c.decodeIfPresent(Bool.self, forKey: .includeInGlobalSearch) ?? true
        self.showInSettingsSidebar = try c.decodeIfPresent(Bool.self, forKey: .showInSettingsSidebar) ?? true
        let rawBoost = try c.decodeIfPresent(Int.self, forKey: .priorityBoost) ?? 0
        self.priorityBoost = min(max(rawBoost, -200), 300)
        let rawCount = try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        self.launchCount = max(0, rawCount)
        self.lastUsedAtEpoch = try c.decodeIfPresent(Double.self, forKey: .lastUsedAtEpoch)
        self.quickButtonCommandIDs = try c.decodeIfPresent([String].self, forKey: .quickButtonCommandIDs) ?? []
        self.disabledCommandIDs = try c.decodeIfPresent([String].self, forKey: .disabledCommandIDs) ?? []
    }

    public var hasCustomizations: Bool {
        customKeywords != nil || customHotKey != nil || !commandHotKeys.isEmpty || pinnedInOverlay
            || !includeInGlobalSearch || !showInSettingsSidebar || priorityBoost != 0
            || !quickButtonCommandIDs.isEmpty || !disabledCommandIDs.isEmpty
    }

    public func usageScoreBoost(now: Date = Date()) -> Int {
        var score = min(max(priorityBoost, -200), 300)
        if pinnedInOverlay { score += 240 }
        if launchCount > 0 {
            score += min(Int(log2(Double(launchCount + 1)) * 32.0), 180)
        }
        if let epoch = lastUsedAtEpoch {
            let age = now.timeIntervalSince1970 - epoch
            if age >= 0 && age < 86_400 { score += 60 }
            else if age >= 0 && age < 604_800 { score += 25 }
        }
        return score
    }
}
