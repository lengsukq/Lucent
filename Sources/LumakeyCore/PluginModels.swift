import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum PluginConfigFieldType: String, Codable, Sendable, Hashable, CaseIterable {
    case text, secret, boolean, select, number, path, directory, tags
}

public struct PluginConfigField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let type: PluginConfigFieldType
    public let control: PluginConfigControlStyle?
    public let defaultValue: String?
    public let placeholder: String?
    public let options: [String]?
    public let required: Bool?
    public let section: String?
    public let helpText: String?
    public let minValue: Double?
    public let maxValue: Double?
    public let stepValue: Double?
    public let includeInBackup: Bool?

    public init(
        key: String, label: String, type: PluginConfigFieldType = .text,
        control: PluginConfigControlStyle? = nil, defaultValue: String? = nil,
        placeholder: String? = nil, options: [String]? = nil, required: Bool? = nil,
        section: String? = nil, helpText: String? = nil,
        minValue: Double? = nil, maxValue: Double? = nil, stepValue: Double? = nil,
        includeInBackup: Bool? = nil
    ) {
        self.key = key; self.label = label; self.type = type; self.control = control
        self.defaultValue = defaultValue; self.placeholder = placeholder
        self.options = options; self.required = required
        self.section = section; self.helpText = helpText
        self.minValue = minValue; self.maxValue = maxValue; self.stepValue = stepValue
        self.includeInBackup = includeInBackup
    }
}

public struct PluginManifest: Codable, Sendable, Hashable {
    public static let defaultTimeoutSeconds: Double = 8.0

    public let schemaVersion: Int?
    public let id: String
    public let name: String
    public let version: String
    public let minAppVersion: String?
    public let description: String
    public let mode: PluginMode
    public let keywords: [String]
    public let entry: String
    public let author: String?
    public let icon: String?
    public let accentColor: String?
    public let categoryTag: String?
    public let hotkey: String?
    public let includeInGlobalSearch: Bool?
    public let searchIndexInGlobalSearch: Bool?
    public let backupExclude: [String]?
    public let config: [PluginConfigField]?
    public let capabilities: [String]?
    public let resourceScopes: [String]?
    public let accepts: [String]?
    public let acceptExtensions: [String]?
    public let acceptURLHosts: [String]?
    public let timeoutSeconds: Double?
    public let refreshIntervalSeconds: Int?
    public let window: PluginManifestWindowDefaults?
    public let commands: [PluginCommandSpec]?
    public let locales: [String: PluginLocaleStrings]?

    public var declaredCapabilities: [PluginCapability] {
        var seen = Set<PluginCapability>()
        return (capabilities ?? []).compactMap { raw in
            guard let cap = PluginCapability(rawValue: raw), seen.insert(cap).inserted else { return nil }
            return cap
        }
    }

    public var declaredResourceScopes: [PluginResourceScope] {
        var seen = Set<PluginResourceScope>()
        return (resourceScopes ?? []).compactMap { raw in
            guard let scope = PluginResourceScope(rawValue: raw), seen.insert(scope).inserted else { return nil }
            return scope
        }
    }

    public var declaredContextKinds: [PluginContextKind] {
        var seen = Set<PluginContextKind>()
        return (accepts ?? []).compactMap { raw in
            guard let kind = PluginContextKind(rawValue: raw), seen.insert(kind).inserted else { return nil }
            return kind
        }
    }

    public var effectiveTimeoutSeconds: Double {
        guard let raw = timeoutSeconds, raw.isFinite else { return Self.defaultTimeoutSeconds }
        return min(max(raw, 3.0), 30.0)
    }

    public init(
        schemaVersion: Int? = nil, id: String, name: String, version: String,
        minAppVersion: String? = nil, description: String,
        mode: PluginMode, keywords: [String], entry: String, author: String? = nil,
        icon: String? = nil, accentColor: String? = nil, categoryTag: String? = nil,
        hotkey: String? = nil, includeInGlobalSearch: Bool? = nil,
        searchIndexInGlobalSearch: Bool? = nil, backupExclude: [String]? = nil,
        config: [PluginConfigField]? = nil,
        capabilities: [String]? = nil, resourceScopes: [String]? = nil,
        accepts: [String]? = nil, acceptExtensions: [String]? = nil,
        acceptURLHosts: [String]? = nil, timeoutSeconds: Double? = nil,
        refreshIntervalSeconds: Int? = nil,
        window: PluginManifestWindowDefaults? = nil,
        commands: [PluginCommandSpec]? = nil, locales: [String: PluginLocaleStrings]? = nil
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.version = version; self.minAppVersion = minAppVersion; self.description = description
        self.mode = mode; self.keywords = keywords; self.entry = entry
        self.author = author; self.icon = icon; self.accentColor = accentColor
        self.categoryTag = categoryTag; self.hotkey = hotkey
        self.includeInGlobalSearch = includeInGlobalSearch
        self.searchIndexInGlobalSearch = searchIndexInGlobalSearch
        self.backupExclude = backupExclude
        self.config = config; self.capabilities = capabilities; self.resourceScopes = resourceScopes
        self.accepts = accepts; self.acceptExtensions = acceptExtensions
        self.acceptURLHosts = acceptURLHosts; self.timeoutSeconds = timeoutSeconds
        self.refreshIntervalSeconds = refreshIntervalSeconds; self.window = window
        self.commands = commands; self.locales = locales
    }
}

public struct PluginInstanceState: Codable, Sendable, Hashable, Equatable {
    public var isEnabled: Bool
    public var configValues: [String: String]
    public var grantedCapabilities: [String]
    public var revokedResourceScopes: [String]
    public var overrides: PluginUserOverrides

    enum CodingKeys: String, CodingKey {
        case isEnabled, configValues, grantedCapabilities, revokedResourceScopes, overrides
    }

    public init(
        isEnabled: Bool = true, configValues: [String: String] = [:],
        grantedCapabilities: [String] = [], revokedResourceScopes: [String] = [],
        overrides: PluginUserOverrides = PluginUserOverrides()
    ) {
        self.isEnabled = isEnabled; self.configValues = configValues
        self.grantedCapabilities = grantedCapabilities; self.revokedResourceScopes = revokedResourceScopes
        self.overrides = overrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.configValues = try c.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
        self.grantedCapabilities = try c.decodeIfPresent([String].self, forKey: .grantedCapabilities) ?? []
        self.revokedResourceScopes = try c.decodeIfPresent([String].self, forKey: .revokedResourceScopes) ?? []
        self.overrides = try c.decodeIfPresent(PluginUserOverrides.self, forKey: .overrides) ?? PluginUserOverrides()
    }
}

public struct PluginStateSnapshot: Codable, Sendable, Hashable, Equatable {
    public var schemaVersion: Int
    public var plugins: [String: PluginInstanceState]

    public init(schemaVersion: Int = 3, plugins: [String: PluginInstanceState] = [:]) {
        self.schemaVersion = schemaVersion; self.plugins = plugins
    }
}

public struct PluginDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let directoryURL: URL
    public let manifest: PluginManifest
    public let validationIssues: [String]
    public let nameLowercased: String
    public let descriptionLowercased: String
    public let localizedSearchPoolLowercased: String
    public let keywordsLowercased: [String]
    public let effectiveKeywords: [String]
    public let effectiveKeywordsLowercased: [String]
    public let isEnabled: Bool
    public let userConfig: [String: String]
    public let kind: PluginKind
    public let grantedCapabilities: Set<PluginCapability>
    public let revokedResourceScopes: Set<PluginResourceScope>
    public let overrides: PluginUserOverrides
    public let builtinMetadata: BuiltinPluginMetadata?
    public let runtimeStatus: PluginRuntimeStatus?

    public var isValid: Bool { validationIssues.isEmpty }
    public var isBuiltin: Bool { kind == .builtin }
    public var declaredCapabilities: [PluginCapability] { manifest.declaredCapabilities }
    public var declaredResourceScopes: [PluginResourceScope] { manifest.declaredResourceScopes }
    public var grantedResourceScopes: Set<PluginResourceScope> {
        Set(declaredResourceScopes).subtracting(revokedResourceScopes)
    }
    public var declaredContextKinds: [PluginContextKind] { manifest.declaredContextKinds }
    public var declaredCommands: [PluginCommandSpec] { manifest.commands ?? [] }
    public var declaredPermissions: [LumakeyPermission] { PluginPermissionAudit.declaredPermissions(for: self) }
    public var isPureSandbox: Bool { declaredPermissions.isEmpty }
    public var pinnedInOverlay: Bool { overrides.pinnedInOverlay }
    public var showInMenuBar: Bool { overrides.showInMenuBar }
    public var includeInGlobalSearch: Bool {
        overrides.includeInGlobalSearchOverride ?? manifest.includeInGlobalSearch ?? true
    }
    public var searchIndexInGlobalSearch: Bool {
        overrides.searchIndexGlobalOverride ?? manifest.searchIndexInGlobalSearch ?? includeInGlobalSearch
    }
    public var showInSettingsSidebar: Bool { overrides.showInSettingsSidebar }
    public var effectiveRankingBoost: Int { overrides.usageScoreBoost() }
    public var effectiveHotKey: String? {
        if let custom = overrides.customHotKey { return custom.isEmpty ? nil : custom }
        return manifest.hotkey
    }
    public func isCommandSearchEnabled(_ spec: PluginCommandSpec) -> Bool {
        if let explicit = overrides.commandSearchOverrides[spec.id] { return explicit }
        if let cmdDefault = spec.includeInGlobalSearch { return cmdDefault }
        return includeInGlobalSearch
    }
    public func isCapabilityGranted(_ capability: PluginCapability) -> Bool {
        declaredCapabilities.contains(capability) && grantedCapabilities.contains(capability)
    }
    public func isResourceScopeGranted(_ scope: PluginResourceScope) -> Bool {
        declaredResourceScopes.contains(scope) && !revokedResourceScopes.contains(scope)
    }

    public init(
        id: String, directoryURL: URL, manifest: PluginManifest, validationIssues: [String],
        isEnabled: Bool = true, userConfig: [String: String] = [:], kind: PluginKind = .external,
        grantedCapabilities: Set<PluginCapability> = [], revokedResourceScopes: Set<PluginResourceScope> = [],
        overrides: PluginUserOverrides = PluginUserOverrides(),
        builtinMetadata: BuiltinPluginMetadata? = nil, runtimeStatus: PluginRuntimeStatus? = nil
    ) {
        let resolvedKws = (overrides.customKeywords?.filter { !$0.isEmpty }).flatMap { $0.isEmpty ? nil : $0 } ?? manifest.keywords
        self.id = id; self.directoryURL = directoryURL; self.manifest = manifest; self.validationIssues = validationIssues
        self.nameLowercased = manifest.name.lowercased(); self.descriptionLowercased = manifest.description.lowercased()
        let extraNames = (manifest.locales?.values.compactMap { [$0.name, $0.description].compactMap { $0 }.joined(separator: " ") } ?? []).joined(separator: " ")
        self.localizedSearchPoolLowercased = "\(manifest.name) \(manifest.description) \(extraNames)".lowercased()
        self.keywordsLowercased = manifest.keywords.map { $0.lowercased() }
        self.effectiveKeywords = resolvedKws; self.effectiveKeywordsLowercased = resolvedKws.map { $0.lowercased() }
        self.isEnabled = isEnabled; self.userConfig = userConfig; self.kind = kind
        self.grantedCapabilities = grantedCapabilities; self.revokedResourceScopes = revokedResourceScopes
        self.overrides = overrides; self.builtinMetadata = builtinMetadata; self.runtimeStatus = runtimeStatus
    }
}

public struct PluginExecutionResult: Sendable, Hashable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int

    public init(exitCode: Int32, stdout: String, stderr: String, durationMs: Int) {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr; self.durationMs = durationMs
    }
}
