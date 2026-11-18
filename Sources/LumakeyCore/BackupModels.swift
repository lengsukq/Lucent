import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import CoreGraphics
import Foundation

public enum BackupArchiveError: Error, LocalizedError, Sendable, Equatable {
    case corruptedArchive(String)
    case unsupportedSchemaVersion(Int)
    case checksumMismatch(expected: String, actual: String)
    case unsafePluginID(String)
    case unsafePath(String)
    case passwordRequired
    case invalidPassword
    case ioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .corruptedArchive(let detail):
            "备份文件已损坏或并非有效的 .lumakeybackup 归档：\(detail)"
        case .unsupportedSchemaVersion(let ver):
            "不支持的备份归档版本（schemaVersion = \(ver)），请升级 Lumakey 后重试"
        case .checksumMismatch(let expected, let actual):
            "备份完整性校验失败（SHA-256 不匹配，期望 \(expected.prefix(12))…，实际 \(actual.prefix(12))…）"
        case .unsafePluginID(let id):
            "备份归档包含不合法的插件标识符：\(id)"
        case .unsafePath(let path):
            "已拦截不安全的归档路径写入请求：\(path)"
        case .passwordRequired:
            "此备份包包含加密的插件密钥，请输入备份加密口令后恢复（或取消勾选「恢复加密密钥」）"
        case .invalidPassword:
            "备份加密口令不正确或加密密钥数据已损坏"
        case .ioFailed(let detail):
            "备份读写操作失败：\(detail)"
        }
    }
}

public enum BackupClipboardKind: String, Codable, Sendable, Equatable {
    case text, colorHex, image, file
}

public struct BackupClipboardRecord: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: BackupClipboardKind
    public var capturedAtISO8601: String
    public var textValue: String?
    public var colorHex: String?
    public var imageBase64: String?
    public var imageWidth: Double?
    public var imageHeight: Double?
    public var imageExtension: String?
    public var skippedLargeImage: Bool
    public var originalByteSize: Int?
    public var filePath: String?

    public init(
        id: String, title: String, subtitle: String, kind: BackupClipboardKind,
        capturedAtISO8601: String, textValue: String? = nil, colorHex: String? = nil,
        imageBase64: String? = nil, imageWidth: Double? = nil, imageHeight: Double? = nil,
        imageExtension: String? = nil, skippedLargeImage: Bool = false,
        originalByteSize: Int? = nil, filePath: String? = nil
    ) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind
        self.capturedAtISO8601 = capturedAtISO8601; self.textValue = textValue
        self.colorHex = colorHex; self.imageBase64 = imageBase64
        self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.imageExtension = imageExtension; self.skippedLargeImage = skippedLargeImage
        self.originalByteSize = originalByteSize; self.filePath = filePath
    }
}

public struct BackupPluginFileRecord: Codable, Sendable, Equatable {
    public var relativePath: String
    public var contentBase64: String
    public var posixPermissions: Int
    public var isExecutable: Bool

    public init(relativePath: String, contentBase64: String, posixPermissions: Int, isExecutable: Bool) {
        self.relativePath = relativePath; self.contentBase64 = contentBase64
        self.posixPermissions = posixPermissions; self.isExecutable = isExecutable
    }
}

public struct BackupPluginBundle: Codable, Sendable, Equatable {
    public var id: String
    public var files: [BackupPluginFileRecord]

    public init(id: String, files: [BackupPluginFileRecord]) {
        self.id = id; self.files = files
    }
}

public struct BackupPluginDataBundle: Codable, Sendable, Equatable {
    public var id: String
    public var files: [BackupPluginFileRecord]
    public var skippedLargeFileCount: Int

    public init(id: String, files: [BackupPluginFileRecord], skippedLargeFileCount: Int = 0) {
        self.id = id; self.files = files; self.skippedLargeFileCount = skippedLargeFileCount
    }
}

public struct BackupExternalPathFile: Codable, Sendable, Equatable {
    public var pluginID: String
    public var configKey: String
    public var homeRelativePath: String
    public var contentBase64: String

    public init(pluginID: String, configKey: String, homeRelativePath: String, contentBase64: String) {
        self.pluginID = pluginID; self.configKey = configKey
        self.homeRelativePath = homeRelativePath; self.contentBase64 = contentBase64
    }
}

public struct BackupEncryptedSecretsEnvelope: Codable, Sendable, Equatable {
    public var kdf: String
    public var saltBase64: String
    public var sealedBoxBase64: String

    public init(kdf: String = "SHA256x65536-HKDF-AESGCM", saltBase64: String, sealedBoxBase64: String) {
        self.kdf = kdf; self.saltBase64 = saltBase64; self.sealedBoxBase64 = sealedBoxBase64
    }
}

public struct BackupPayload: Codable, Sendable, Equatable {
    public var mosConfig: MosConfig
    public var telemetryConfig: SystemMonitorConfig
    public var rawConfigFiles: [String: String]
    public var pinnedClipboardItems: [BackupClipboardRecord]
    public var plugins: [BackupPluginBundle]
    public var pluginData: [BackupPluginDataBundle]
    public var externalPluginFiles: [BackupExternalPathFile]
    public var scriptFiles: [BackupPluginFileRecord]
    public var encryptedPluginSecrets: BackupEncryptedSecretsEnvelope?

    enum CodingKeys: String, CodingKey {
        case mosConfig, telemetryConfig, rawConfigFiles, pinnedClipboardItems, plugins
        case pluginData, externalPluginFiles, scriptFiles, encryptedPluginSecrets
    }

    public init(
        mosConfig: MosConfig,
        telemetryConfig: SystemMonitorConfig,
        rawConfigFiles: [String: String],
        pinnedClipboardItems: [BackupClipboardRecord],
        plugins: [BackupPluginBundle],
        pluginData: [BackupPluginDataBundle] = [],
        externalPluginFiles: [BackupExternalPathFile] = [],
        scriptFiles: [BackupPluginFileRecord] = [],
        encryptedPluginSecrets: BackupEncryptedSecretsEnvelope? = nil
    ) {
        self.mosConfig = mosConfig; self.telemetryConfig = telemetryConfig
        self.rawConfigFiles = rawConfigFiles; self.pinnedClipboardItems = pinnedClipboardItems
        self.plugins = plugins; self.pluginData = pluginData
        self.externalPluginFiles = externalPluginFiles
        self.scriptFiles = scriptFiles
        self.encryptedPluginSecrets = encryptedPluginSecrets
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.mosConfig = try c.decode(MosConfig.self, forKey: .mosConfig)
        self.telemetryConfig = try c.decode(SystemMonitorConfig.self, forKey: .telemetryConfig)
        self.rawConfigFiles = try c.decode([String: String].self, forKey: .rawConfigFiles)
        self.pinnedClipboardItems = try c.decode([BackupClipboardRecord].self, forKey: .pinnedClipboardItems)
        self.plugins = try c.decode([BackupPluginBundle].self, forKey: .plugins)
        self.pluginData = try c.decodeIfPresent([BackupPluginDataBundle].self, forKey: .pluginData) ?? []
        self.externalPluginFiles = try c.decodeIfPresent([BackupExternalPathFile].self, forKey: .externalPluginFiles) ?? []
        self.scriptFiles = try c.decodeIfPresent([BackupPluginFileRecord].self, forKey: .scriptFiles) ?? []
        self.encryptedPluginSecrets = try c.decodeIfPresent(BackupEncryptedSecretsEnvelope.self, forKey: .encryptedPluginSecrets)
    }
}

public struct BackupEnvelope: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 2
    public static let fileExtension: String = "lumakeybackup"

    public var schemaVersion: Int
    public var createdAtISO8601: String
    public var appVersion: String
    public var hostName: String
    public var payloadSHA256: String
    public var payload: BackupPayload

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAtISO8601: String, appVersion: String, hostName: String,
        payloadSHA256: String, payload: BackupPayload
    ) {
        self.schemaVersion = schemaVersion; self.createdAtISO8601 = createdAtISO8601
        self.appVersion = appVersion; self.hostName = hostName
        self.payloadSHA256 = payloadSHA256; self.payload = payload
    }
}

public struct BackupRestoreOptions: Sendable, Equatable {
    public var restoreConfigs: Bool
    public var restoreClipboard: Bool
    public var restorePlugins: Bool
    public var restorePluginData: Bool
    public var restoreEncryptedSecrets: Bool
    public var overwriteExistingPlugins: Bool
    public var createSafetySnapshotBeforeRestore: Bool
    public var decryptionPassphrase: String?

    public static let all = BackupRestoreOptions()

    public init(
        restoreConfigs: Bool = true,
        restoreClipboard: Bool = true,
        restorePlugins: Bool = true,
        restorePluginData: Bool = true,
        restoreEncryptedSecrets: Bool = true,
        overwriteExistingPlugins: Bool = true,
        createSafetySnapshotBeforeRestore: Bool = true,
        decryptionPassphrase: String? = nil
    ) {
        self.restoreConfigs = restoreConfigs; self.restoreClipboard = restoreClipboard
        self.restorePlugins = restorePlugins; self.restorePluginData = restorePluginData
        self.restoreEncryptedSecrets = restoreEncryptedSecrets
        self.overwriteExistingPlugins = overwriteExistingPlugins
        self.createSafetySnapshotBeforeRestore = createSafetySnapshotBeforeRestore
        self.decryptionPassphrase = decryptionPassphrase
    }
}

public struct BackupInspectionSummary: Sendable, Equatable {
    public let schemaVersion: Int
    public let createdAtISO8601: String
    public let appVersion: String
    public let hostName: String
    public let payloadSHA256: String
    public let archiveByteCount: Int
    public let isCompressed: Bool
    public let configFileNames: [String]
    public let pinnedClipboardCount: Int
    public let skippedLargeImageCount: Int
    public let pluginIDs: [String]
    public let pluginDataPluginIDs: [String]
    public let pluginDataFileCount: Int
    public let externalFileCount: Int
    public let hasEncryptedSecrets: Bool

    public var configCount: Int { configFileNames.count }
    public var pluginCount: Int { pluginIDs.count }
}

public struct BackupRestoreReport: Sendable, Equatable {
    public let mosConfig: MosConfig
    public let telemetryConfig: SystemMonitorConfig
    public let restoredConfigFileNames: [String]
    public let restoredClipboardEntries: [ClipboardEntry]
    public let skippedClipboardCount: Int
    public let restoredPluginIDs: [String]
    public let restoredPluginDataIDs: [String]
    public let restoredExternalFileCount: Int
    public let restoredSecretPluginIDs: [String]
    public let safetySnapshotURL: URL?
}
