import Foundation
import LocalAuthentication
import Security

public struct WebDAVConfig: Codable, Sendable, Equatable {
    public static let configFileName = "webdav-config.json"

    public var serverURL: String
    public var username: String
    public var remoteDirectory: String
    public var keepLatestCount: Int
    public var autoBackupOnLaunch: Bool

    enum CodingKeys: String, CodingKey {
        case serverURL
        case username
        case remoteDirectory
        case keepLatestCount
        case autoBackupOnLaunch
    }

    public init(
        serverURL: String = "",
        username: String = "",
        remoteDirectory: String = "LumakeyBackups",
        keepLatestCount: Int = 10,
        autoBackupOnLaunch: Bool = false
    ) {
        self.serverURL = serverURL
        self.username = username
        self.remoteDirectory = remoteDirectory
        self.keepLatestCount = max(1, keepLatestCount)
        self.autoBackupOnLaunch = autoBackupOnLaunch
    }

    public var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func defaultConfigURL(
        in appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent(configFileName, isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> WebDAVConfig {
        guard let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(WebDAVConfig.self, from: data) else {
            return WebDAVConfig()
        }
        decoded.keepLatestCount = max(1, decoded.keepLatestCount)
        if decoded.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decoded.remoteDirectory = "LumakeyBackups"
        }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL()) {
        var normalized = self
        normalized.keepLatestCount = max(1, normalized.keepLatestCount)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(normalized) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

public struct WebDAVProviderPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sampleURL: String
    public let setupHint: String
    public let symbol: String

    public static let allPresets: [WebDAVProviderPreset] = [
        WebDAVProviderPreset(
            id: "jianguoyun",
            name: "坚果云",
            sampleURL: "https://dav.jianguoyun.com/dav/",
            setupHint: "坚果云基础路径必须包含 /dav/，并在网页端「账户信息 -> 安全选项」生成第三方应用专用密码。",
            symbol: "icloud.fill"
        ),
        WebDAVProviderPreset(
            id: "nextcloud",
            name: "Nextcloud",
            sampleURL: "https://cloud.example.com/remote.php/dav/files/username/",
            setupHint: "Nextcloud 路径末尾替换为您自己的登录用户名，推荐使用「安全 -> 设备与会话」应用密码。",
            symbol: "cloud.fill"
        ),
        WebDAVProviderPreset(
            id: "synology",
            name: "Synology / NAS",
            sampleURL: "https://nas.example.com:5006/",
            setupHint: "群晖 / 绿联 / LightIsle NAS 开启 WebDAV Server 后默认 HTTPS 端口 5006（HTTP 为 5005）。",
            symbol: "externaldrive.connected.to.line.below.fill"
        ),
        WebDAVProviderPreset(
            id: "alist",
            name: "Alist / OpenList",
            sampleURL: "https://alist.example.com/dav/",
            setupHint: "Alist 与 OpenList 统一挂载 WebDAV 入口为 /dav/，账号需开启 WebDAV 读取与管理写入权限。",
            symbol: "server.rack"
        )
    ]
}

public enum WebDAVKeychainError: Error, LocalizedError, Sendable, Equatable {
    case unhandledStatus(OSStatus)
    case vaultError(String)

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return L10n.pick("WebDAV 密钥访问失败：\(msg)", "WebDAV secret access failed: \(msg)")
        case .vaultError(let detail):
            return detail
        }
    }
}

public enum WebDAVKeychainStore {
    public static let defaultService = "app.lumakey.macos.webdav"

    private static func normalizedAccount(_ account: String) -> String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }

    public static func savePassword(
        _ password: String,
        account: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws {
        let acct = normalizedAccount(account)
        do {
            try LocalSecretVault.saveValue(password, service: service, account: acct, customVaultURL: customVaultURL)
            if password.isEmpty && customVaultURL == nil {
                deleteLegacyPasswordSilently(account: acct, service: service)
            }
        } catch {
            throw WebDAVKeychainError.vaultError(error.localizedDescription)
        }
    }

    public static func loadPassword(
        account: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws -> String? {
        let acct = normalizedAccount(account)
        if let stored = try? LocalSecretVault.loadValue(service: service, account: acct, customVaultURL: customVaultURL),
           !stored.isEmpty {
            return stored
        }
        guard customVaultURL == nil else { return nil }
        if let legacy = loadLegacyPasswordSilently(account: acct, service: service), !legacy.isEmpty {
            try? LocalSecretVault.saveValue(legacy, service: service, account: acct)
            deleteLegacyPasswordSilently(account: acct, service: service)
            return legacy
        }
        return nil
    }

    public static func deletePassword(
        account: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws {
        let acct = normalizedAccount(account)
        do {
            try LocalSecretVault.deleteValue(service: service, account: acct, customVaultURL: customVaultURL)
            if customVaultURL == nil {
                deleteLegacyPasswordSilently(account: acct, service: service)
            }
        } catch {
            throw WebDAVKeychainError.vaultError(error.localizedDescription)
        }
    }

    private static func loadLegacyPasswordSilently(account: String, service: String) -> String? {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacyPasswordSilently(account: String, service: String) {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: ctx
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
