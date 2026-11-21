import Foundation

public enum AppThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pureFrost = "pure-frost"
    case prismPulse = "prism-pulse"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pureFrost: "晴霜浅色"
        case .prismPulse: "曜石暗色"
        }
    }

    public var englishBadge: String {
        switch self {
        case .pureFrost: "LIGHT FROST"
        case .prismPulse: "OBSIDIAN DARK"
        }
    }

    public var subtitle: String {
        switch self {
        case .pureFrost: "通透瓷白毛玻璃与柔和镜面高光，明晰纯粹"
        case .prismPulse: "深邃石墨液态玻璃与冷银折射边缘，沉静专注"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .pureFrost: L10n.pick("晴霜浅色", "Light Frost")
        case .prismPulse: L10n.pick("曜石暗色", "Obsidian Dark")
        }
    }

    public var localizedSubtitle: String {
        switch self {
        case .pureFrost: L10n.pick("通透瓷白毛玻璃与柔和镜面高光，明晰纯粹", "Luminous porcelain glass with crisp specular highlights")
        case .prismPulse: L10n.pick("深邃石墨液态玻璃与冷银折射边缘，沉静专注", "Deep graphite liquid glass with cool silver refraction")
        }
    }

    public var symbolName: String {
        switch self {
        case .pureFrost: "sun.max.fill"
        case .prismPulse: "moon.stars.fill"
        }
    }

    public var next: AppThemeID {
        switch self {
        case .pureFrost: .prismPulse
        case .prismPulse: .pureFrost
        }
    }
}

public struct AppThemeConfig: Codable, Sendable, Hashable, Equatable {
    public var selectedTheme: AppThemeID
    public var followSystemAppearance: Bool

    enum CodingKeys: String, CodingKey {
        case selectedTheme
        case followSystemAppearance
    }

    public init(selectedTheme: AppThemeID = .pureFrost, followSystemAppearance: Bool = false) {
        self.selectedTheme = selectedTheme
        self.followSystemAppearance = followSystemAppearance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedTheme = (try? c.decode(AppThemeID.self, forKey: .selectedTheme)) ?? .pureFrost
        self.followSystemAppearance = (try? c.decode(Bool.self, forKey: .followSystemAppearance)) ?? false
    }

    public static func defaultConfigURL() -> URL {
        LucentAppPaths.configFileURL("theme-config.json")
    }

    public static func load(from url: URL = defaultConfigURL()) -> AppThemeConfig {
        AtomicJSONStore.load(AppThemeConfig.self, from: url, fallback: AppThemeConfig())
    }

    public func save(to url: URL = defaultConfigURL()) {
        AtomicJSONStore.save(self, to: url)
    }
}
