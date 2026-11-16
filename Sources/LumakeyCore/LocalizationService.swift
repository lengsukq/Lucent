import Foundation

private final class LanguageStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValue: AppLanguageID
    private var loadedTable: [String: String]?

    init(initial: AppLanguageID) {
        self.currentValue = initial
    }

    func getLanguage() -> AppLanguageID {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    func setLanguage(_ next: AppLanguageID) {
        lock.lock()
        currentValue = next
        lock.unlock()
    }

    func englishCatalog() -> [String: String] {
        lock.lock()
        if let cached = loadedTable {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = Self.loadEnglishStringsFromDisk()
        lock.lock()
        loadedTable = resolved
        lock.unlock()
        return resolved
    }

    private static func loadEnglishStringsFromDisk() -> [String: String] {
        var candidateURLs: [URL] = []
        if let lprojPath = Bundle.main.path(forResource: "en", ofType: "lproj") {
            candidateURLs.append(URL(fileURLWithPath: lprojPath).appendingPathComponent("Localizable.strings"))
        }
        if let resURL = Bundle.main.resourceURL {
            candidateURLs.append(resURL.appendingPathComponent("en.lproj/Localizable.strings"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidateURLs.append(cwd.appendingPathComponent("apps/macos/en.lproj/Localizable.strings"))
        let execDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        candidateURLs.append(execDir.appendingPathComponent("../Resources/en.lproj/Localizable.strings").standardizedFileURL)

        for url in candidateURLs where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String],
               !dict.isEmpty {
                return dict
            }
        }
        return [:]
    }
}

private let globalLanguageState = LanguageStateBox(
    initial: AppLanguageConfig.loadOrBootstrap().selectedLanguage
)

public enum L10n {
    public static var current: AppLanguageID {
        globalLanguageState.getLanguage()
    }

    public static var isEnglish: Bool {
        globalLanguageState.getLanguage() == .english
    }

    public static func setCurrent(_ language: AppLanguageID) {
        globalLanguageState.setLanguage(language)
    }

    public static func reloadFromDisk(url: URL = AppLanguageConfig.defaultConfigURL()) -> AppLanguageID {
        let cfg = AppLanguageConfig.loadOrBootstrap(from: url)
        globalLanguageState.setLanguage(cfg.selectedLanguage)
        return cfg.selectedLanguage
    }

    @inline(__always)
    public static func pick(_ zhHans: String, _ english: String) -> String {
        globalLanguageState.getLanguage() == .english ? english : zhHans
    }

    public static func translate(_ text: String, for language: AppLanguageID = L10n.current) -> String {
        guard language == .english, !text.isEmpty else { return text }
        let table = globalLanguageState.englishCatalog()
        if let exact = table[text] {
            return exact
        }
        return LocalizationPatterns.translateDynamic(text, table: table)
    }
}
