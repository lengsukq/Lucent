import Foundation
import LocalAuthentication
import Security

public enum PluginKeychainError: Error, LocalizedError, Sendable, Equatable {
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return "插件钥匙串访问失败：\(msg)"
        }
    }
}

public enum PluginKeychainStore {
    public static let defaultService = "app.lumakey.macos.plugins"

    private static func accountKey(pluginID: String, fieldKey: String) -> String {
        "\(pluginID):\(fieldKey)"
    }

    public static func saveSecret(
        _ value: String,
        pluginID: String,
        fieldKey: String,
        service: String = defaultService
    ) throws {
        if value.isEmpty {
            try deleteSecret(pluginID: pluginID, fieldKey: fieldKey, service: service)
            return
        }
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw PluginKeychainError.unhandledStatus(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insertQuery[kSecAttrLabel as String] = "Lumakey Plugin (\(acct))"
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PluginKeychainError.unhandledStatus(addStatus)
        }
    }

    public static func loadSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService,
        allowInteraction: Bool = true
    ) throws -> String? {
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowInteraction {
            let ctx = LAContext()
            ctx.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = ctx
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || (!allowInteraction && status == errSecInteractionNotAllowed) {
            return nil
        }
        guard status == errSecSuccess else {
            throw PluginKeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteSecret(
        pluginID: String,
        fieldKey: String,
        service: String = defaultService
    ) throws {
        let acct = accountKey(pluginID: pluginID, fieldKey: fieldKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PluginKeychainError.unhandledStatus(status)
        }
    }

    public static func deleteSecrets(
        pluginID: String,
        fieldKeys: [String],
        service: String = defaultService
    ) {
        for key in fieldKeys where !key.isEmpty {
            try? deleteSecret(pluginID: pluginID, fieldKey: key, service: service)
        }
    }
}
