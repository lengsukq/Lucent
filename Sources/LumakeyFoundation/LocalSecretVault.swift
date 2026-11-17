import CryptoKit
import Darwin
import Foundation

public enum LocalSecretVaultError: Error, LocalizedError, Sendable, Equatable {
    case invalidCiphertext
    case ioFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCiphertext:
            L10n.pick("本机加密密钥库校验失败（密文已损坏或非本机生成）", "Local encrypted secret vault verification failed (corrupted or foreign machine)")
        case .ioFailed(let detail):
            L10n.pick("本机加密密钥库读写失败：\(detail)", "Local encrypted secret vault I/O failed: \(detail)")
        }
    }
}

public enum LumakeyAppPaths {
    public static let pluginsKeychainService = "app.lumakey.macos.plugins"
    public static let webdavKeychainService = "app.lumakey.macos.webdav"
    public static let lumaLinkKeychainService = "app.lumakey.macos.lumalink"

    public static let primaryVaultServices: Set<String> = [
        pluginsKeychainService, webdavKeychainService, lumaLinkKeychainService
    ]

    public static func defaultAppSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Lumakey", isDirectory: true)
    }
}

/// 基于双轨 256-bit 随机主密钥（`LocalSecretMasterKeyStore`）与 `0700/0600` 原子持久化的 `AES-GCM` 本地密钥保险箱。
public enum LocalSecretVault {
    public static let magicHeader = Data("LMKYVLT2".utf8)
    public static let vaultDirectoryName = ".vault"
    public static let vaultFileName = "secrets.v2.enc"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var memoryCache: [String: [String: [String: String]]] = [:]

    private struct VaultPayload: Codable {
        var schemaVersion: Int = 2
        var services: [String: [String: String]] = [:]
    }

    public static func defaultVaultFileURL(
        in appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory
            .appendingPathComponent(vaultDirectoryName, isDirectory: true)
            .appendingPathComponent(vaultFileName, isDirectory: false)
    }

    public static func vaultFileURL(forService service: String, customVaultURL: URL? = nil) -> URL {
        if let customVaultURL { return customVaultURL }
        if LumakeyAppPaths.primaryVaultServices.contains(service) {
            return defaultVaultFileURL()
        }
        let digest = SHA256.hash(data: Data(service.utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return LumakeyAppPaths.defaultAppSupportDirectory()
            .appendingPathComponent(vaultDirectoryName, isDirectory: true)
            .appendingPathComponent("services", isDirectory: true)
            .appendingPathComponent("svc-\(hex).v2.enc", isDirectory: false)
    }

    public static func saveValue(
        _ value: String,
        service: String,
        account: String,
        customVaultURL: URL? = nil
    ) throws {
        if value.isEmpty {
            try deleteValue(service: service, account: account, customVaultURL: customVaultURL)
            return
        }
        let fileURL = vaultFileURL(forService: service, customVaultURL: customVaultURL)
        try lock.withLock {
            var services = (try? loadServicesLocked(at: fileURL)) ?? [:]
            var acctMap = services[service] ?? [:]
            acctMap[account] = value
            services[service] = acctMap
            try writeServicesLocked(services, to: fileURL)
        }
    }

    public static func loadValue(
        service: String,
        account: String,
        customVaultURL: URL? = nil
    ) throws -> String? {
        let fileURL = vaultFileURL(forService: service, customVaultURL: customVaultURL)
        return try lock.withLock {
            let services = try loadServicesLocked(at: fileURL)
            return services[service]?[account]
        }
    }

    public static func hasValue(
        service: String,
        account: String,
        customVaultURL: URL? = nil
    ) -> Bool {
        guard let val = try? loadValue(service: service, account: account, customVaultURL: customVaultURL) else {
            return false
        }
        return !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func deleteValue(
        service: String,
        account: String,
        customVaultURL: URL? = nil
    ) throws {
        let fileURL = vaultFileURL(forService: service, customVaultURL: customVaultURL)
        try lock.withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                memoryCache.removeValue(forKey: fileURL.standardizedFileURL.path)
                return
            }
            var services = (try? loadServicesLocked(at: fileURL)) ?? [:]
            services[service]?.removeValue(forKey: account)
            if services[service]?.isEmpty == true {
                services.removeValue(forKey: service)
            }
            if services.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                memoryCache.removeValue(forKey: fileURL.standardizedFileURL.path)
            } else {
                try writeServicesLocked(services, to: fileURL)
            }
        }
    }

    public static func clearMemoryCache() {
        lock.withLock { memoryCache.removeAll() }
        LocalSecretMasterKeyStore.clearCache()
    }

    // MARK: - Crypto & 0700/0600 Atomic Persistence

    public static func sealPayloadData(
        _ plaintext: Data,
        vaultDirectory: URL? = nil,
        keyOverride: SymmetricKey? = nil
    ) throws -> Data {
        let resolvedDir = vaultDirectory ?? defaultVaultFileURL().deletingLastPathComponent()
        let key = try keyOverride ?? LocalSecretMasterKeyStore.loadOrCreateMasterKey(forVaultDirectory: resolvedDir)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: magicHeader)
        guard let combined = sealed.combined else {
            throw LocalSecretVaultError.invalidCiphertext
        }
        var out = Data()
        out.reserveCapacity(magicHeader.count + combined.count)
        out.append(magicHeader)
        out.append(combined)
        return out
    }

    public static func openPayloadData(
        _ rawData: Data,
        vaultDirectory: URL? = nil,
        keyOverride: SymmetricKey? = nil
    ) throws -> Data {
        let resolvedDir = vaultDirectory ?? defaultVaultFileURL().deletingLastPathComponent()
        guard rawData.count > magicHeader.count + 28,
              rawData.prefix(magicHeader.count) == magicHeader else {
            throw LocalSecretVaultError.invalidCiphertext
        }
        let combined = rawData.dropFirst(magicHeader.count)
        let key = try keyOverride ?? LocalSecretMasterKeyStore.loadOrCreateMasterKey(forVaultDirectory: resolvedDir)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: magicHeader)
        } catch {
            throw LocalSecretVaultError.invalidCiphertext
        }
    }

    private static func loadServicesLocked(at fileURL: URL) throws -> [String: [String: String]] {
        let key = fileURL.standardizedFileURL.path
        if let cached = memoryCache[key] {
            return cached
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let vaultDir = fileURL.deletingLastPathComponent()
        let raw = try Data(contentsOf: fileURL)
        let plain = try openPayloadData(raw, vaultDirectory: vaultDir)
        let decoded = try JSONDecoder().decode(VaultPayload.self, from: plain)
        memoryCache[key] = decoded.services
        return decoded.services
    }

    private static func writeServicesLocked(_ services: [String: [String: String]], to fileURL: URL) throws {
        let dirURL = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        _ = Darwin.chmod(dirURL.path, mode_t(0o700))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try encoder.encode(VaultPayload(schemaVersion: 2, services: services))
        let encrypted = try sealPayloadData(plain, vaultDirectory: dirURL)

        let tmpURL = dirURL.appendingPathComponent(".vault-tmp-\(UUID().uuidString)", isDirectory: false)
        let fd = Darwin.open(tmpURL.path, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, mode_t(0o600))
        guard fd >= 0 else {
            throw LocalSecretVaultError.ioFailed("open errno \(errno)")
        }
        let writeOK: Bool = encrypted.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return true }
            var offset = 0
            while offset < ptr.count {
                let n = Darwin.write(fd, base.advanced(by: offset), ptr.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        _ = Darwin.fchmod(fd, mode_t(0o600))
        _ = Darwin.close(fd)
        guard writeOK else {
            try? fm.removeItem(at: tmpURL)
            throw LocalSecretVaultError.ioFailed("write errno \(errno)")
        }
        guard Darwin.rename(tmpURL.path, fileURL.path) == 0 else {
            let err = errno
            try? fm.removeItem(at: tmpURL)
            throw LocalSecretVaultError.ioFailed("rename errno \(err)")
        }
        _ = Darwin.chmod(fileURL.path, mode_t(0o600))
        memoryCache[fileURL.standardizedFileURL.path] = services
    }
}
