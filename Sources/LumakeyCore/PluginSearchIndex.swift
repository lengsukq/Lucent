import Foundation

public struct PluginSearchEntry: Identifiable, Sendable, Hashable {
    public let id: String
    public let pluginID: String
    public let pluginName: String
    public let itemID: String
    public let title: String
    public let subtitle: String
    public let url: String?
    public let copyText: String?
    public let icon: String?
    public let badge: String?
    public let tags: [String]
    public let pinned: Bool
    public let priority: Int
    public let commandArgs: [String]?

    public let titleLowercased: String
    public let subtitleLowercased: String
    public let urlLowercased: String
    public let tagsLowercased: [String]
    public let fullPinyin: String
    public let pinyinInitials: String

    public init(
        pluginID: String,
        pluginName: String,
        itemID: String,
        title: String,
        subtitle: String = "",
        url: String? = nil,
        copyText: String? = nil,
        icon: String? = nil,
        badge: String? = nil,
        tags: [String] = [],
        pinned: Bool = false,
        priority: Int = 0,
        commandArgs: [String]? = nil
    ) {
        self.id = "\(pluginID):\(itemID)"
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.copyText = copyText
        self.icon = icon
        self.badge = badge
        self.tags = tags
        self.pinned = pinned
        self.priority = priority
        self.commandArgs = commandArgs
        self.titleLowercased = title.lowercased()
        self.subtitleLowercased = subtitle.lowercased()
        self.urlLowercased = (url ?? "").lowercased()
        self.tagsLowercased = tags.map { $0.lowercased() }
        let (full, initials) = PinyinHelper.convert(title)
        self.fullPinyin = full
        self.pinyinInitials = initials
    }
}

public enum PluginSearchIndex {
    public static let defaultIndexFileName = "search-index.json"
    private static let maxIndexBytes = 524_288

    private struct RawEnvelope: Decodable {
        let items: [RawItem]
    }

    private struct RawItem: Decodable {
        let id: String?
        let title: String
        let subtitle: String?
        let url: String?
        let copyText: String?
        let icon: String?
        let badge: String?
        let tags: [String]?
        let pinned: Bool?
        let priority: Int?
        let commandArgs: [String]?
    }

    public static func indexFileURL(
        for plugin: PluginDescriptor,
        in pluginsRoot: URL? = nil
    ) -> URL? {
        let resolvedRoot = pluginsRoot ?? plugin.directoryURL.deletingLastPathComponent()
        if let managedURL = PluginDataPaths.searchIndexURL(for: plugin.id, pluginsRoot: resolvedRoot),
           FileManager.default.fileExists(atPath: managedURL.path) {
            return managedURL
        }
        let rootPath = plugin.directoryURL.standardizedFileURL.path
        let legacyURL = plugin.directoryURL.appendingPathComponent(defaultIndexFileName).standardizedFileURL
        guard legacyURL.path.hasPrefix(rootPath + "/"),
              FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        return legacyURL
    }

    public static func loadEntries(
        for plugins: [PluginDescriptor],
        in pluginsRoot: URL? = nil,
        maxItemsPerPlugin: Int = 500
    ) -> [PluginSearchEntry] {
        var all: [PluginSearchEntry] = []
        for plugin in plugins where !plugin.isBuiltin && plugin.isValid && plugin.isEnabled {
            guard let fileURL = indexFileURL(for: plugin, in: pluginsRoot),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attrs[.size] as? Int,
                  fileSize > 0, fileSize <= maxIndexBytes,
                  let data = try? Data(contentsOf: fileURL)
            else { continue }

            let rawItems: [RawItem]
            if let env = try? JSONDecoder().decode(RawEnvelope.self, from: data) {
                rawItems = env.items
            } else if let arr = try? JSONDecoder().decode([RawItem].self, from: data) {
                rawItems = arr
            } else {
                continue
            }

            for (idx, item) in rawItems.prefix(maxItemsPerPlugin).enumerated() {
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let itemID = (item.id?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "row-\(idx)"
                all.append(
                    PluginSearchEntry(
                        pluginID: plugin.id,
                        pluginName: plugin.manifest.name,
                        itemID: itemID,
                        title: title,
                        subtitle: item.subtitle ?? "",
                        url: item.url,
                        copyText: item.copyText,
                        icon: item.icon,
                        badge: item.badge,
                        tags: item.tags ?? [],
                        pinned: item.pinned ?? false,
                        priority: item.priority ?? 0,
                        commandArgs: item.commandArgs
                    )
                )
            }
        }
        return all
    }

    public static func match(
        entries: [PluginSearchEntry],
        query: String,
        limit: Int = 15
    ) -> [(entry: PluginSearchEntry, score: Int)] {
        let tokens = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        var hits: [(entry: PluginSearchEntry, score: Int)] = []
        for entry in entries {
            var totalScore = 0
            var matchedAll = true
            for tok in tokens {
                let s = scoreToken(tok, against: entry)
                if s <= 0 {
                    matchedAll = false
                    break
                }
                totalScore += s
            }
            guard matchedAll else { continue }
            let avgScore = totalScore / tokens.count
            let boost = (entry.pinned ? 150 : 0) + min(max(entry.priority, 0), 100)
            hits.append((entry, avgScore + boost))
        }

        hits.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.pinned != rhs.entry.pinned { return lhs.entry.pinned }
            if lhs.entry.priority != rhs.entry.priority { return lhs.entry.priority > rhs.entry.priority }
            return lhs.entry.titleLowercased < rhs.entry.titleLowercased
        }
        return Array(hits.prefix(limit))
    }

    private static func scoreToken(_ token: String, against entry: PluginSearchEntry) -> Int {
        if token.hasPrefix("#"), token.count > 1 {
            let tagNeedle = String(token.dropFirst())
            if entry.tagsLowercased.contains(tagNeedle) { return 8_400 }
            if entry.tagsLowercased.contains(where: { $0.contains(tagNeedle) }) { return 7_900 }
            return 0
        }
        if entry.titleLowercased == token { return 9_200 }
        if entry.titleLowercased.hasPrefix(token) { return 8_700 }
        if entry.pinyinInitials.hasPrefix(token) { return 8_300 }
        if entry.titleLowercased.contains(token) || entry.fullPinyin.hasPrefix(token) { return 7_700 }
        if entry.tagsLowercased.contains(where: { $0 == token || $0.contains(token) }) { return 7_500 }
        if entry.fullPinyin.contains(token) || entry.pinyinInitials.contains(token) { return 6_800 }
        if entry.urlLowercased.contains(token) || entry.subtitleLowercased.contains(token) { return 6_200 }
        return 0
    }
}
