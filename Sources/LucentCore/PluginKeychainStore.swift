import LucentFoundation
import Foundation
import Security

public enum PluginKeychainError: Error, LocalizedError, Sendable, Equatable {
    case unhandledStatus(OSStatus)
    case vaultError(String)

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return L10n.pick("插件密钥访问失败：\(msg)", "Plugin secret access failed: \(msg)")
        case .vaultError(let detail):
            return detail
        }
    }
}

/// 插件密钥安全存储：采用本机 `0700/0600` `AES-GCM` 加密保险箱（`LocalSecretVault`）。
public enum PluginKeychainStore {
    public static let defaultService = "app.lucent.macos.plugins"

    private static func accountKey(pluginID: String, fieldKey: String) -> String {
        "\(pluginID):\(fieldKey)"
    }

    public static func saveSecret(
        _ value: String,
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws {
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        do {
            try LocalSecretVault.saveValue(value, service: service, account: acct, customVaultURL: customVaultURL)
        } catch {
            throw PluginKeychainError.vaultError(error.localizedDescription)
        }
    }

    public static func loadSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws -> String? {
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        if let stored = try? LocalSecretVault.loadValue(service: service, account: acct, customVaultURL: customVaultURL),
           !stored.isEmpty {
            return stored
        }
        return nil
    }

    public static func hasSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) -> Bool {
        guard let val = try? loadSecret(
            pluginID: pluginID, fieldKey: fieldKey, service: service, customVaultURL: customVaultURL
        ) else { return false }
        return !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func deleteSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) throws {
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        do {
            try LocalSecretVault.deleteValue(service: service, account: acct, customVaultURL: customVaultURL)
        } catch {
            throw PluginKeychainError.vaultError(error.localizedDescription)
        }
    }

    public static func deleteSecrets(
        pluginID: String,
        fieldKeys: [String],
        service: String = defaultService,
        customVaultURL: URL? = nil
    ) {
        for key in fieldKeys where !key.isEmpty {
            try? deleteSecret(pluginID: pluginID, fieldKey: key, service: service, customVaultURL: customVaultURL)
        }
    }
}
