import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation
import LocalAuthentication
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

/// 插件密钥安全存储：主存储采用本机 `0700/0600` `AES-GCM` 加密保险箱（`LocalSecretVault`），彻底杜绝跨版本升级或无证书分发时的系统钥匙串密码弹窗；
/// 读取未命中时以 `LAContext.interactionNotAllowed = true` 静默无弹窗迁移历史钥匙串记录。
public enum PluginKeychainStore {
    public static let defaultService = "app.lumakey.macos.plugins"

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
            if value.isEmpty {
                deleteLegacyKeychainSilently(account: acct, service: service)
            }
        } catch {
            throw PluginKeychainError.vaultError(error.localizedDescription)
        }
    }

    public static func loadSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        allowInteraction: Bool = false,
        customVaultURL: URL? = nil
    ) throws -> String? {
        let _ = allowInteraction
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        if let stored = try? LocalSecretVault.loadValue(service: service, account: acct, customVaultURL: customVaultURL),
           !stored.isEmpty {
            return stored
        }
        guard customVaultURL == nil else { return nil }
        if let legacy = loadLegacyKeychainSilently(account: acct, service: service), !legacy.isEmpty {
            try? LocalSecretVault.saveValue(legacy, service: service, account: acct)
            deleteLegacyKeychainSilently(account: acct, service: service)
            return legacy
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
            pluginID: pluginID, fieldKey: fieldKey, service: service,
            allowInteraction: false, customVaultURL: customVaultURL
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
            if customVaultURL == nil {
                deleteLegacyKeychainSilently(account: acct, service: service)
            }
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

    // MARK: - Strictly Non-Interactive Legacy Keychain Migration (Zero Popup Guarantee)

    private static func loadLegacyKeychainSilently(account: String, service: String) -> String? {
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

    private static func deleteLegacyKeychainSilently(account: String, service: String) {
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
