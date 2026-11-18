import LucentFoundation
import Foundation

public struct PluginStoreItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let minAppVersion: String?
    public let changelog: String?
    public let description: String
    public let author: String?
    public let icon: String?
    public let accentColor: String?
    public let categoryTag: String?
    public let mode: PluginMode
    public let keywords: [String]
    public let capabilities: [String]
    public let resourceScopes: [String]
    public let accepts: [String]?
    public let homepage: String?
    public let downloadURL: String
    public let sha256: String
    public let sizeBytes: Int?
    public let locales: [String: PluginLocaleStrings]?

    public var declaredCapabilities: [PluginCapability] {
        var seen = Set<PluginCapability>()
        return capabilities.compactMap { raw in
            guard let cap = PluginCapability(rawValue: raw), seen.insert(cap).inserted else { return nil }
            return cap
        }
    }

    public var declaredResourceScopes: [PluginResourceScope] {
        var seen = Set<PluginResourceScope>()
        return resourceScopes.compactMap { raw in
            guard let scope = PluginResourceScope(rawValue: raw), seen.insert(scope).inserted else { return nil }
            return scope
        }
    }

    public var isPureSandbox: Bool {
        declaredCapabilities.isEmpty && declaredResourceScopes.isEmpty
    }

    public func localizedName(locale: AppLanguage = L10n.current) -> String {
        if let hit = locales?[locale.rawValue]?.name, !hit.isEmpty { return hit }
        return name
    }

    public func localizedDescription(locale: AppLanguage = L10n.current) -> String {
        if let hit = locales?[locale.rawValue]?.description, !hit.isEmpty { return hit }
        return description
    }

    public func localizedCategoryTag(locale: AppLanguage = L10n.current) -> String {
        if let hit = locales?[locale.rawValue]?.categoryTag, !hit.isEmpty { return hit }
        if let tag = categoryTag, !tag.isEmpty { return tag }
        return mode == .view ? "VIEW" : "SCRIPT"
    }

    public init(
        id: String, name: String, version: String, minAppVersion: String? = nil,
        changelog: String? = nil, description: String, author: String? = nil,
        icon: String? = nil, accentColor: String? = nil, categoryTag: String? = nil,
        mode: PluginMode = .view, keywords: [String],
        capabilities: [String], resourceScopes: [String], accepts: [String]? = nil,
        homepage: String? = nil, downloadURL: String, sha256: String,
        sizeBytes: Int? = nil, locales: [String: PluginLocaleStrings]? = nil
    ) {
        self.id = id; self.name = name; self.version = version
        self.minAppVersion = minAppVersion; self.changelog = changelog
        self.description = description; self.author = author; self.icon = icon
        self.accentColor = accentColor; self.categoryTag = categoryTag
        self.mode = mode; self.keywords = keywords
        self.capabilities = capabilities; self.resourceScopes = resourceScopes; self.accepts = accepts
        self.homepage = homepage; self.downloadURL = downloadURL; self.sha256 = sha256
        self.sizeBytes = sizeBytes; self.locales = locales
    }
}

public struct PluginStoreRegistryManifest: Codable, Sendable, Hashable {
    public static let defaultFileName = "lucent-registry.json"
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int?
    public let storeId: String
    public let storeName: String
    public let description: String?
    public let maintainer: String?
    public let homepage: String?
    public let updatedAt: String?
    public let plugins: [PluginStoreItem]

    public init(
        schemaVersion: Int? = 1, storeId: String, storeName: String,
        description: String? = nil, maintainer: String? = nil,
        homepage: String? = nil, updatedAt: String? = nil, plugins: [PluginStoreItem]
    ) {
        self.schemaVersion = schemaVersion; self.storeId = storeId; self.storeName = storeName
        self.description = description; self.maintainer = maintainer
        self.homepage = homepage; self.updatedAt = updatedAt; self.plugins = plugins
    }

    public func validate() -> [String] {
        var issues: [String] = []
        if let ver = schemaVersion, ver != Self.currentSchemaVersion {
            issues.append("不支持的商店 schemaVersion: \(ver)（当前支持 1）")
        }
        if !PluginSystem.isSafePluginID(storeId) {
            issues.append("storeId '\(storeId)' 不合法（仅允许小写字母、数字和连字符）")
        }
        if storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("storeName 不能为空")
        }
        var seenIDs = Set<String>()
        for item in plugins {
            if !PluginSystem.isSafePluginID(item.id) || PluginBuiltinRegistry.isBuiltin(id: item.id) {
                issues.append("插件 id '\(item.id)' 不合法或占用了 builtin- 保留前缀")
            }
            if !seenIDs.insert(item.id).inserted {
                issues.append("商店清单存在重复插件 id '\(item.id)'")
            }
            if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("插件 '\(item.id)' 缺少名称")
            }
            if item.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("插件 '\(item.id)' 缺少版本号")
            }
            if item.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("插件 '\(item.id)' 缺少 downloadURL")
            }
            if !Self.isValidSHA256Hex(item.sha256) {
                issues.append("插件 '\(item.id)' 的 sha256 必须为 64 位十六进制摘要")
            }
            for rawCap in item.capabilities where PluginCapability(rawValue: rawCap) == nil {
                issues.append("插件 '\(item.id)' 声明了未知 capability '\(rawCap)'")
            }
            for rawScope in item.resourceScopes where PluginResourceScope(rawValue: rawScope) == nil {
                issues.append("插件 '\(item.id)' 声明了未知 resourceScope '\(rawScope)'")
            }
        }
        return issues
    }

    public static func isValidSHA256Hex(_ raw: String) -> Bool {
        guard raw.count == 64 else { return false }
        return raw.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 65 && scalar.value <= 70)
                || (scalar.value >= 97 && scalar.value <= 102)
        }
    }
}

public struct PluginStoreSubscription: Codable, Sendable, Hashable, Identifiable {
    public var id: String { manifest.storeId }
    public let sourceURL: String
    public let resolvedRegistryURL: String
    public let addedAtISO8601: String
    public var lastSyncedAtISO8601: String
    public var manifest: PluginStoreRegistryManifest

    public init(
        sourceURL: String, resolvedRegistryURL: String,
        addedAtISO8601: String, lastSyncedAtISO8601: String, manifest: PluginStoreRegistryManifest
    ) {
        self.sourceURL = sourceURL; self.resolvedRegistryURL = resolvedRegistryURL
        self.addedAtISO8601 = addedAtISO8601; self.lastSyncedAtISO8601 = lastSyncedAtISO8601
        self.manifest = manifest
    }
}

public struct PluginStoreCatalogSnapshot: Codable, Sendable, Hashable {
    public static let fileName = "plugin-registries.json"
    public var schemaVersion: Int
    public var stores: [PluginStoreSubscription]
    public var seededDefaultStoreIDs: [String]?

    public init(schemaVersion: Int = 1, stores: [PluginStoreSubscription] = [], seededDefaultStoreIDs: [String]? = nil) {
        self.schemaVersion = schemaVersion
        self.stores = stores
        self.seededDefaultStoreIDs = seededDefaultStoreIDs
    }
}

public enum PluginStoreInstallState: Sendable, Hashable, Equatable {
    case notInstalled
    case installedUpToDate(version: String)
    case updateAvailable(installed: String, available: String)
}

public enum PluginVersionComparator {
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = parseSegments(lhs)
        let rightParts = parseSegments(rhs)
        let count = max(leftParts.count, rightParts.count)
        for idx in 0..<count {
            let l = idx < leftParts.count ? leftParts[idx] : 0
            let r = idx < rightParts.count ? rightParts[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parseSegments(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V")) ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? withoutPrefix
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

public struct SinglePluginCandidate: Sendable, Hashable, Identifiable {
    public var id: String { manifest.id }
    public let manifest: PluginManifest
    public let sourceInput: String
    public let resolvedDownloadURL: String
    public let originDisplay: String
    public let sha256: String
    public let stagingBundleDirectory: URL
    public let stagingRootDirectory: URL?

    public init(
        manifest: PluginManifest, sourceInput: String, resolvedDownloadURL: String,
        originDisplay: String, sha256: String,
        stagingBundleDirectory: URL, stagingRootDirectory: URL?
    ) {
        self.manifest = manifest; self.sourceInput = sourceInput
        self.resolvedDownloadURL = resolvedDownloadURL; self.originDisplay = originDisplay
        self.sha256 = sha256; self.stagingBundleDirectory = stagingBundleDirectory
        self.stagingRootDirectory = stagingRootDirectory
    }

    public func cleanupStagingIfNeeded() {
        if let root = stagingRootDirectory { try? FileManager.default.removeItem(at: root) }
    }
}

public enum DiscoveredPluginSource: Sendable, Hashable {
    case storeRegistry(PluginStoreSubscription)
    case singlePlugin(SinglePluginCandidate)
}
