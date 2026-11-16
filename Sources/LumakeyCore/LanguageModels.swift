import Foundation

public typealias AppLanguage = AppLanguageID

public enum AppLanguageID: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case zhHans = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var nativeTitle: String {
        switch self {
        case .zhHans: "简体中文"
        case .english: "English"
        }
    }

    public var badgeText: String {
        switch self {
        case .zhHans: "ZH-HANS"
        case .english: "EN"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .zhHans: "zh-Hans"
        case .english: "en"
        }
    }

    public var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    public var symbolName: String {
        switch self {
        case .zhHans: "character.bubble.fill"
        case .english: "globe"
        }
    }

    public var localizedSubtitle: String {
        switch self {
        case .zhHans:
            L10n.pick("原生简体中文界面，支持应用与命令中文全拼/首字母检索", "Native Simplified Chinese UI with Pinyin search")
        case .english:
            L10n.pick("原生英文界面，同时完整保留中文应用与拼音检索能力", "Native English UI while keeping full Pinyin & CJK search")
        }
    }

    public var next: AppLanguageID {
        switch self {
        case .zhHans: .english
        case .english: .zhHans
        }
    }
}

public struct AppLanguageConfig: Codable, Sendable, Hashable, Equatable {
    public var selectedLanguage: AppLanguageID

    enum CodingKeys: String, CodingKey {
        case selectedLanguage
    }

    public init(selectedLanguage: AppLanguageID) {
        self.selectedLanguage = selectedLanguage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode(String.self, forKey: .selectedLanguage))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let exact = AppLanguageID(rawValue: raw) {
            self.selectedLanguage = exact
        } else if raw.lowercased().hasPrefix("zh") {
            self.selectedLanguage = .zhHans
        } else if raw.lowercased().hasPrefix("en") {
            self.selectedLanguage = .english
        } else {
            self.selectedLanguage = Self.detectSystemLanguage()
        }
    }

    /// 根据 macOS 系统首选语言列表识别首次打开时的默认界面语言（首选语言为 `zh*` 选用 `.zhHans`，其余选用 `.english`）。
    public static func detectSystemLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages,
        fallbackLocaleID: String = Locale.current.identifier
    ) -> AppLanguageID {
        for raw in preferredLanguages {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if tag.isEmpty { continue }
            return tag.hasPrefix("zh") ? .zhHans : .english
        }
        return fallbackLocaleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("zh")
            ? .zhHans
            : .english
    }

    public static func defaultConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Lumakey", isDirectory: true)
            .appendingPathComponent("language-config.json", isDirectory: false)
    }

    public static func hasSavedPreference(at url: URL = defaultConfigURL()) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 首次启动尚无 `language-config.json` 时自动根据系统语言初始化并落盘；后续启动直接读取用户保存的语言配置。
    public static func loadOrBootstrap(
        from url: URL = defaultConfigURL(),
        preferredLanguages: [String] = Locale.preferredLanguages,
        fallbackLocaleID: String = Locale.current.identifier,
        persistBootstrap: Bool = true
    ) -> AppLanguageConfig {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppLanguageConfig.self, from: data) {
            return decoded
        }
        let detected = detectSystemLanguage(
            preferredLanguages: preferredLanguages,
            fallbackLocaleID: fallbackLocaleID
        )
        let initial = AppLanguageConfig(selectedLanguage: detected)
        if persistBootstrap {
            initial.save(to: url)
        }
        return initial
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
