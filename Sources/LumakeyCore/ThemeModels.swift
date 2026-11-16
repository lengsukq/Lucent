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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Lumakey", isDirectory: true)
            .appendingPathComponent("theme-config.json", isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> AppThemeConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppThemeConfig.self, from: data)
        else {
            return AppThemeConfig()
        }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL()) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
