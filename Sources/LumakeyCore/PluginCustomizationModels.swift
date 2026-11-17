import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum PluginContextKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case url, text, image, file, directory

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
        kind: PluginContextKind, text: String? = nil, url: String? = nil,
        filePaths: [String]? = nil, source: String
    ) {
        self.kind = kind; self.text = text; self.url = url
        self.filePaths = filePaths; self.source = source
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
            guard !plugin.isBuiltin && plugin.isValid && plugin.isEnabled
                    && plugin.declaredContextKinds.contains(context.kind) else { return false }
            return satisfiesGranularConstraints(plugin: plugin, context: context)
        }
        .sorted { lhs, rhs in
            if lhs.effectiveRankingBoost != rhs.effectiveRankingBoost {
                return lhs.effectiveRankingBoost > rhs.effectiveRankingBoost
            }
            return lhs.id < rhs.id
        }
    }

    private static func satisfiesGranularConstraints(plugin: PluginDescriptor, context: PluginContextPayload) -> Bool {
        if (context.kind == .file || context.kind == .image),
           let rawExts = plugin.manifest.acceptExtensions {
            let allowed = Set(rawExts.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    .lowercased()
            }.filter { !$0.isEmpty })
            if !allowed.isEmpty {
                let paths = context.filePaths ?? []
                let hasMatch = paths.contains { path in
                    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                    return !ext.isEmpty && allowed.contains(ext)
                }
                if !hasMatch { return false }
            }
        }
        if context.kind == .url, let rawHosts = plugin.manifest.acceptURLHosts {
            let allowedHosts = rawHosts.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty }
            if !allowedHosts.isEmpty {
                guard let urlStr = context.url ?? context.text,
                      let host = URL(string: urlStr)?.host?.lowercased(),
                      !host.isEmpty else { return false }
                let hostMatched = allowedHosts.contains { pattern in
                    host == pattern || host.hasSuffix("." + pattern)
                }
                if !hostMatched { return false }
            }
        }
        return true
    }

    public static func payloadFromClipboard(_ entry: ClipboardEntry) -> PluginContextPayload? {
        switch entry.payloadKind {
        case .image(let url, _):
            let paths = entry.fileURLs.isEmpty ? [url.path] : entry.fileURLs.map(\.path)
            return PluginContextPayload(kind: .image, filePaths: paths, source: "clipboard")
        case .video(let url):
            let paths = entry.fileURLs.isEmpty ? [url.path] : entry.fileURLs.map(\.path)
            return PluginContextPayload(kind: .file, filePaths: paths, source: "clipboard")
        case .file(let url):
            let paths = entry.fileURLs.isEmpty ? [url.path] : entry.fileURLs.map(\.path)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if paths.count == 1 && !isDir && MediaClassifier.classify(url: url, isDirectory: false) == .image {
                return PluginContextPayload(kind: .image, filePaths: paths, source: "clipboard")
            }
            return PluginContextPayload(kind: (paths.count == 1 && isDir) ? .directory : .file, filePaths: paths, source: "clipboard")
        case .colorHex(let hex):
            return PluginContextPayload(kind: .text, text: hex, source: "clipboard")
        case .text:
            guard let raw = entry.textValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            if let parsed = URL(string: raw), let scheme = parsed.scheme?.lowercased(),
               (scheme == "http" || scheme == "https"), parsed.host != nil {
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
            if isDir { return PluginContextPayload(kind: .directory, filePaths: paths, source: source) }
            if MediaClassifier.classify(url: first, isDirectory: false) == .image {
                return PluginContextPayload(kind: .image, filePaths: paths, source: source)
            }
        }
        return PluginContextPayload(kind: .file, filePaths: paths, source: source)
    }

    public static func payloadFromText(_ rawText: String, source: String) -> PluginContextPayload? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"), parsed.host != nil {
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
    public var showInMenuBar: Bool
    public var menuBarCommandIDs: [String]
    public var includeInGlobalSearchOverride: Bool?
    public var searchIndexGlobalOverride: Bool?
    public var showInSettingsSidebar: Bool
    public var priorityBoost: Int
    public var launchCount: Int
    public var lastUsedAtEpoch: Double?
    public var quickButtonCommandIDs: [String]
    public var commandSearchOverrides: [String: Bool]

    public var includeInGlobalSearch: Bool {
        get { includeInGlobalSearchOverride ?? true }
        set { includeInGlobalSearchOverride = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case customKeywords, customHotKey, commandHotKeys, pinnedInOverlay
        case showInMenuBar, menuBarCommandIDs
        case includeInGlobalSearchOverride, searchIndexGlobalOverride
        case showInSettingsSidebar, priorityBoost, launchCount, lastUsedAtEpoch
        case quickButtonCommandIDs, commandSearchOverrides
    }

    public init(
        customKeywords: [String]? = nil, customHotKey: String? = nil,
        commandHotKeys: [String: String] = [:], pinnedInOverlay: Bool = false,
        showInMenuBar: Bool = false, menuBarCommandIDs: [String] = [],
        includeInGlobalSearchOverride: Bool? = nil, searchIndexGlobalOverride: Bool? = nil,
        showInSettingsSidebar: Bool = true, priorityBoost: Int = 0,
        launchCount: Int = 0, lastUsedAtEpoch: Double? = nil,
        quickButtonCommandIDs: [String] = [], commandSearchOverrides: [String: Bool] = [:]
    ) {
        self.customKeywords = customKeywords; self.customHotKey = customHotKey
        self.commandHotKeys = commandHotKeys; self.pinnedInOverlay = pinnedInOverlay
        self.showInMenuBar = showInMenuBar; self.menuBarCommandIDs = menuBarCommandIDs
        self.includeInGlobalSearchOverride = includeInGlobalSearchOverride
        self.searchIndexGlobalOverride = searchIndexGlobalOverride
        self.showInSettingsSidebar = showInSettingsSidebar
        self.priorityBoost = min(max(priorityBoost, -200), 300)
        self.launchCount = max(0, launchCount); self.lastUsedAtEpoch = lastUsedAtEpoch
        self.quickButtonCommandIDs = quickButtonCommandIDs; self.commandSearchOverrides = commandSearchOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.customKeywords = try c.decodeIfPresent([String].self, forKey: .customKeywords)
        self.customHotKey = try c.decodeIfPresent(String.self, forKey: .customHotKey)
        self.commandHotKeys = try c.decodeIfPresent([String: String].self, forKey: .commandHotKeys) ?? [:]
        self.pinnedInOverlay = try c.decodeIfPresent(Bool.self, forKey: .pinnedInOverlay) ?? false
        self.showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? false
        self.menuBarCommandIDs = try c.decodeIfPresent([String].self, forKey: .menuBarCommandIDs) ?? []
        self.includeInGlobalSearchOverride = try c.decodeIfPresent(Bool.self, forKey: .includeInGlobalSearchOverride)
        self.searchIndexGlobalOverride = try c.decodeIfPresent(Bool.self, forKey: .searchIndexGlobalOverride)
        self.showInSettingsSidebar = try c.decodeIfPresent(Bool.self, forKey: .showInSettingsSidebar) ?? true
        self.priorityBoost = min(max(try c.decodeIfPresent(Int.self, forKey: .priorityBoost) ?? 0, -200), 300)
        self.launchCount = max(0, try c.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0)
        self.lastUsedAtEpoch = try c.decodeIfPresent(Double.self, forKey: .lastUsedAtEpoch)
        self.quickButtonCommandIDs = try c.decodeIfPresent([String].self, forKey: .quickButtonCommandIDs) ?? []
        self.commandSearchOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .commandSearchOverrides) ?? [:]
    }

    public var hasCustomizations: Bool {
        customKeywords != nil || customHotKey != nil || !commandHotKeys.isEmpty || pinnedInOverlay
            || showInMenuBar || !menuBarCommandIDs.isEmpty
            || includeInGlobalSearchOverride != nil || searchIndexGlobalOverride != nil
            || !showInSettingsSidebar || priorityBoost != 0
            || !quickButtonCommandIDs.isEmpty || !commandSearchOverrides.isEmpty
    }

    public func usageScoreBoost(now: Date = Date()) -> Int {
        var score = min(max(priorityBoost, -200), 300)
        if pinnedInOverlay { score += 240 }
        if launchCount > 0 { score += min(Int(log2(Double(launchCount + 1)) * 32.0), 180) }
        if let epoch = lastUsedAtEpoch {
            let age = now.timeIntervalSince1970 - epoch
            if age >= 0 && age < 86_400 { score += 60 }
            else if age >= 0 && age < 604_800 { score += 25 }
        }
        return score
    }
}
