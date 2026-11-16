import CryptoKit
import Darwin
import Foundation
import IOKit

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

/// 绑定本机硬件标识与当前 UID 的 `0700/0600` `AES-GCM` (256-bit) 本地密钥保险箱。
/// 彻底避免无付费 Provisioning Profile 或跨版本重编时触发传统 macOS 文件型钥匙串密码弹窗，同时防止明文落盘与备份归档外泄。
public enum LocalSecretVault {
    public static let magicHeader = Data("LMKYVLT1".utf8)
    public static let vaultDirectoryName = ".vault"
    public static let vaultFileName = "secrets.v1.enc"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var memoryCache: [String: [String: [String: String]]] = [:]

    private struct VaultPayload: Codable {
        var schemaVersion: Int = 1
        var services: [String: [String: String]] = [:]
    }

    public static func defaultVaultFileURL(
        in appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory
            .appendingPathComponent(vaultDirectoryName, isDirectory: true)
            .appendingPathComponent(vaultFileName, isDirectory: false)
    }

    public static func vaultFileURL(forService service: String, customVaultURL: URL? = nil) -> URL {
        if let customVaultURL { return customVaultURL }
        if service == PluginKeychainStore.defaultService || service == WebDAVKeychainStore.defaultService {
            return defaultVaultFileURL()
        }
        var hash: UInt64 = 14695981039346656037
        for b in service.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lk-vault-\(getuid())", isDirectory: true)
        return dir.appendingPathComponent("svc-\(String(hash, radix: 16)).v1.enc", isDirectory: false)
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
    }

    // MARK: - Crypto & 0700/0600 Atomic Persistence

    public static func sealPayloadData(_ plaintext: Data, keyOverride: SymmetricKey? = nil) throws -> Data {
        let key = keyOverride ?? deriveMachineBoundKey()
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

    public static func openPayloadData(_ rawData: Data, keyOverride: SymmetricKey? = nil) throws -> Data {
        guard rawData.count > magicHeader.count + 28,
              rawData.prefix(magicHeader.count) == magicHeader else {
            throw LocalSecretVaultError.invalidCiphertext
        }
        let combined = rawData.dropFirst(magicHeader.count)
        let key = keyOverride ?? deriveMachineBoundKey()
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
        let raw = try Data(contentsOf: fileURL)
        let plain = try openPayloadData(raw)
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
        let plain = try encoder.encode(VaultPayload(schemaVersion: 1, services: services))
        let encrypted = try sealPayloadData(plain)

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

    private static func deriveMachineBoundKey() -> SymmetricKey {
        let uuid = readHardwarePlatformUUID()
        let ikm = Data("lumakey-local-vault-v1|\(uuid)|uid=\(getuid())".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data("app.lumakey.macos.local-secret-vault.salt.v1".utf8),
            info: Data("aes-256-gcm-v1".utf8),
            outputByteCount: 32
        )
    }

    private static func readHardwarePlatformUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "macos-arm64-local" }
        defer { IOObjectRelease(service) }
        if let cfProp = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
           !cfProp.isEmpty {
            return cfProp
        }
        return "macos-arm64-local"
    }
}
