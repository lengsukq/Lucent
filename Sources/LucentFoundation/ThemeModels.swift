import Foundation

public enum AppThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case pureFrost = "pure-frost"
    case prismPulse = "prism-pulse"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pureFrost: "凝霜留白"
        case .prismPulse: "霓彩流光"
        }
    }

    public var englishBadge: String {
        switch self {
        case .pureFrost: "PURE FROST"
        case .prismPulse: "PRISM PULSE"
        }
    }

    public var subtitle: String {
        switch self {
        case .pureFrost: "纯净磨砂与克制留白，零弥散杂光，清爽耐看"
        case .prismPulse: "活力光谱渐变与通透棱镜高光，灵动鲜明"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .pureFrost: L10n.pick("凝霜留白", "Pure Frost")
        case .prismPulse: L10n.pick("霓彩流光", "Prism Pulse")
        }
    }

    public var localizedSubtitle: String {
        switch self {
        case .pureFrost: L10n.pick("纯净磨砂与克制留白，零弥散杂光，清爽耐看", "Clean frosted surface with crisp contrast and zero ambient glow")
        case .prismPulse: L10n.pick("活力光谱渐变与通透棱镜高光，灵动鲜明", "Vibrant prism gradients with specular glass highlights")
        }
    }

    public var symbolName: String {
        switch self {
        case .pureFrost: "circle.lefthalf.filled"
        case .prismPulse: "sparkles"
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

    enum CodingKeys: String, CodingKey {
        case selectedTheme
    }

    public init(selectedTheme: AppThemeID = .pureFrost) {
        self.selectedTheme = selectedTheme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedTheme = (try? c.decode(AppThemeID.self, forKey: .selectedTheme)) ?? .pureFrost
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
