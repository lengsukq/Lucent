import Foundation

public enum PluginConfigControlStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case automatic, slider, segmented
}

public struct PluginCommandLocaleStrings: Codable, Sendable, Hashable, Equatable {
    public let title: String?
    public let subtitle: String?
    public init(title: String? = nil, subtitle: String? = nil) {
        self.title = title; self.subtitle = subtitle
    }
}

public struct PluginConfigFieldLocaleStrings: Codable, Sendable, Hashable, Equatable {
    public let label: String?
    public let placeholder: String?
    public let helpText: String?
    public let section: String?

    public init(label: String? = nil, placeholder: String? = nil, helpText: String? = nil, section: String? = nil) {
        self.label = label; self.placeholder = placeholder; self.helpText = helpText; self.section = section
    }
}

public struct PluginLocaleStrings: Codable, Sendable, Hashable, Equatable {
    public let name: String?
    public let description: String?
    public let categoryTag: String?
    public let commands: [String: PluginCommandLocaleStrings]?
    public let config: [String: PluginConfigFieldLocaleStrings]?

    public init(
        name: String? = nil, description: String? = nil, categoryTag: String? = nil,
        commands: [String: PluginCommandLocaleStrings]? = nil,
        config: [String: PluginConfigFieldLocaleStrings]? = nil
    ) {
        self.name = name; self.description = description; self.categoryTag = categoryTag
        self.commands = commands; self.config = config
    }
}

public struct PluginRuntimeStatus: Codable, Sendable, Hashable, Equatable {
    public let summary: String
    public let badge: String?
    public let updatedAtEpoch: Double

    public init(summary: String, badge: String? = nil, updatedAtEpoch: Double = Date().timeIntervalSince1970) {
        self.summary = summary; self.badge = badge; self.updatedAtEpoch = updatedAtEpoch
    }
}

public enum PluginIconResolver {
    public static let supportedExtensions: Set<String> = ["png", "svg", "icns", "jpg", "jpeg", "webp", "tiff", "pdf"]

    public static func looksLikeRelativeFilePath(_ rawIcon: String?) -> Bool {
        guard let raw = rawIcon?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        if raw.contains("/") { return true }
        return supportedExtensions.contains((raw as NSString).pathExtension.lowercased())
    }

    public static func resolveBundleIconURL(rawIcon: String?, in bundleDirectory: URL) -> URL? {
        guard let raw = rawIcon?.trimmingCharacters(in: .whitespacesAndNewlines),
              looksLikeRelativeFilePath(raw),
              !raw.hasPrefix("/"), !raw.hasPrefix("~"), !raw.contains(".."),
              supportedExtensions.contains((raw as NSString).pathExtension.lowercased())
        else { return nil }
        let rootPath = bundleDirectory.standardizedFileURL.path
        let target = bundleDirectory.appendingPathComponent(raw).standardizedFileURL
        guard target.path.hasPrefix(rootPath + "/"), FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }

    public static func resolveItemIconURL(rawIcon: String?, bundleDirectory: URL?, dataDirectory: URL?) -> URL? {
        guard let raw = rawIcon?.trimmingCharacters(in: .whitespacesAndNewlines),
              looksLikeRelativeFilePath(raw), !raw.contains(".."),
              supportedExtensions.contains((raw as NSString).pathExtension.lowercased())
        else { return nil }
        if raw.hasPrefix("/") {
            let abs = URL(fileURLWithPath: raw).standardizedFileURL
            if let dataRoot = dataDirectory?.standardizedFileURL.path, abs.path.hasPrefix(dataRoot + "/"), FileManager.default.fileExists(atPath: abs.path) { return abs }
            if let bundleRoot = bundleDirectory?.standardizedFileURL.path, abs.path.hasPrefix(bundleRoot + "/"), FileManager.default.fileExists(atPath: abs.path) { return abs }
            return nil
        }
        if let bundleDirectory, let hit = resolveBundleIconURL(rawIcon: raw, in: bundleDirectory) { return hit }
        if let dataDirectory, let hit = resolveBundleIconURL(rawIcon: raw, in: dataDirectory) { return hit }
        return nil
    }

    public static func validateManifestIcon(_ rawIcon: String?, in bundleDirectory: URL) -> String? {
        guard let raw = rawIcon?.trimmingCharacters(in: .whitespacesAndNewlines), looksLikeRelativeFilePath(raw) else { return nil }
        if raw.hasPrefix("/") || raw.hasPrefix("~") || raw.contains("..") {
            return "icon 图标文件路径必须位于插件包目录内部且不得越界"
        }
        let ext = (raw as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return "icon 图标文件格式不支持：'\(ext)'" }
        let rootPath = bundleDirectory.standardizedFileURL.path
        let target = bundleDirectory.appendingPathComponent(raw).standardizedFileURL
        guard target.path.hasPrefix(rootPath + "/") else { return "icon 图标文件路径试图逃逸插件目录" }
        if !FileManager.default.fileExists(atPath: target.path) { return "icon 图标文件不存在：\(raw)" }
        return nil
    }
}

extension PluginManifest {
    public func localeBundle(for language: AppLanguageID = L10n.current) -> PluginLocaleStrings? {
        guard let locales, !locales.isEmpty else { return nil }
        if let exact = locales[language.rawValue] { return exact }
        let prefix = language == .english ? "en" : "zh"
        return locales.first(where: { $0.key.lowercased().hasPrefix(prefix) })?.value
    }

    public func localizedName(for language: AppLanguageID = L10n.current) -> String {
        if let custom = localeBundle(for: language)?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty { return custom }
        return L10n.translate(name, for: language)
    }

    public func localizedDescription(for language: AppLanguageID = L10n.current) -> String {
        if let custom = localeBundle(for: language)?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty { return custom }
        return L10n.translate(description, for: language)
    }

    public func localizedCategoryTag(isBuiltin: Bool, for language: AppLanguageID = L10n.current) -> String {
        if isBuiltin { return L10n.pick("原生内置", "Native", forLanguage: language) }
        if let locTag = localeBundle(for: language)?.categoryTag?.trimmingCharacters(in: .whitespacesAndNewlines), !locTag.isEmpty { return locTag }
        if let rawTag = categoryTag?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTag.isEmpty { return L10n.translate(rawTag, for: language) }
        return L10n.pick("扩展", "Extension", forLanguage: language)
    }

    public func localizedCommandTitle(_ cmd: PluginCommandSpec, for language: AppLanguageID = L10n.current) -> String {
        if let val = localeBundle(for: language)?.commands?[cmd.id]?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return L10n.translate(cmd.title, for: language)
    }

    public func localizedCommandSubtitle(_ cmd: PluginCommandSpec, for language: AppLanguageID = L10n.current) -> String {
        if let val = localeBundle(for: language)?.commands?[cmd.id]?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return L10n.translate(cmd.subtitle, for: language)
    }

    public func localizedFieldLabel(_ field: PluginConfigField, for language: AppLanguageID = L10n.current) -> String {
        if let val = localeBundle(for: language)?.config?[field.key]?.label?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return L10n.translate(field.label, for: language)
    }

    public func localizedFieldPlaceholder(_ field: PluginConfigField, for language: AppLanguageID = L10n.current) -> String? {
        if let val = localeBundle(for: language)?.config?[field.key]?.placeholder?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return field.placeholder.map { L10n.translate($0, for: language) }
    }

    public func localizedFieldHelpText(_ field: PluginConfigField, for language: AppLanguageID = L10n.current) -> String? {
        if let val = localeBundle(for: language)?.config?[field.key]?.helpText?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return field.helpText.map { L10n.translate($0, for: language) }
    }

    public func localizedFieldSection(_ field: PluginConfigField, for language: AppLanguageID = L10n.current) -> String? {
        if let val = localeBundle(for: language)?.config?[field.key]?.section?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty { return val }
        return field.section.map { L10n.translate($0, for: language) }
    }
}

extension PluginDescriptor {
    public var displayName: String { manifest.localizedName() }
    public var displayDescription: String { manifest.localizedDescription() }
    public var displayCategoryBadge: String { runtimeStatus?.badge ?? manifest.localizedCategoryTag(isBuiltin: isBuiltin) }
    public var customIconURL: URL? { isBuiltin ? nil : PluginIconResolver.resolveBundleIconURL(rawIcon: manifest.icon, in: directoryURL) }
    public var symbolIconName: String {
        if let icon = manifest.icon, !icon.isEmpty, !PluginIconResolver.looksLikeRelativeFilePath(icon) { return icon }
        return isBuiltin ? "sparkles" : "puzzlepiece.extension.fill"
    }
    public var effectiveStatusSummary: String {
        if let meta = builtinMetadata { return meta.statusSummary }
        if let rt = runtimeStatus, !rt.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return rt.summary }
        return displayDescription
    }
    public func effectiveCommandHotKey(for commandID: String) -> String? {
        if let custom = overrides.commandHotKeys[commandID] { return custom.isEmpty ? nil : custom }
        return declaredCommands.first(where: { $0.id == commandID })?.hotkey
    }
}

extension L10n {
    @inline(__always)
    public static func pick(_ zhHans: String, _ english: String, forLanguage language: AppLanguageID) -> String {
        language == .english ? english : zhHans
    }
}
