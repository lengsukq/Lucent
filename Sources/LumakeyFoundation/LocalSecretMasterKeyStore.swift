import CryptoKit
import Darwin
import Foundation
import IOKit
import LocalAuthentication
import Security

/// 双轨高熵主密钥管理器：
/// 1. 稳定签名 `.app` 构建：优先将 256-bit CSPRNG 随机主密钥存入系统 Keychain（签名固定零弹窗）；
/// 2. Ad-hoc 社区构建 / CLI / 自定义测试库：采用 `SecRandomCopyBytes` 生成 32 字节真随机种子（`0600` + `UF_HIDDEN` + 排除备份），
///    再结合硬件平台标识进行 HKDF 信封派生，彻底消除纯 `IOPlatformUUID + uid` 低熵可被同机推算的风险。
public enum LocalSecretMasterKeyStore {
    public static let masterKeyFileName = "master.v2.key"
    public static let keychainService = "app.lumakey.macos.vault.master-key"
    public static let keychainAccount = "master-key-v2"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedKeys: [String: SymmetricKey] = [:]

    public static func clearCache() {
        lock.withLock { cachedKeys.removeAll() }
    }

    public static func loadOrCreateMasterKey(
        forVaultDirectory vaultDir: URL,
        allowSystemKeychain: Bool? = nil
    ) throws -> SymmetricKey {
        let dirKey = vaultDir.standardizedFileURL.path
        if let hit = lock.withLock({ cachedKeys[dirKey] }) {
            return hit
        }

        let rawSeed = try resolveRawSeed(forVaultDirectory: vaultDir, allowSystemKeychain: allowSystemKeychain)
        let derived = deriveEnvelopeKey(fromRandomSeed: rawSeed)
        lock.withLock { cachedKeys[dirKey] = derived }
        return derived
    }

    /// 仅供读取历史 `LMKYVLT1` 密文并透明迁移至 `LMKYVLT2` 使用。
    public static func deriveLegacyV1Key() -> SymmetricKey {
        let uuid = readHardwarePlatformUUID()
        let ikm = Data("lumakey-local-vault-v1|\(uuid)|uid=\(getuid())".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data("app.lumakey.macos.local-secret-vault.salt.v1".utf8),
            info: Data("aes-256-gcm-v1".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - Internal Seed Resolution

    private static func resolveRawSeed(
        forVaultDirectory vaultDir: URL,
        allowSystemKeychain: Bool?
    ) throws -> Data {
        let defaultVaultDir = LocalSecretVault.defaultVaultFileURL().deletingLastPathComponent().standardizedFileURL.path
        let isDefaultVault = (vaultDir.standardizedFileURL.path == defaultVaultDir)
        let shouldTryKeychain = allowSystemKeychain ?? (isDefaultVault && isStableSignedAppBundle())

        if shouldTryKeychain {
            if let existingKC = loadKeychainSeedSilently(), existingKC.count == 32 {
                return existingKC
            }
            let fresh = try generateCSPRNGBytes(count: 32)
            if saveKeychainSeedSilently(fresh) {
                return fresh
            }
        }

        var fm = FileManager.default
        if !fm.fileExists(atPath: vaultDir.path) {
            try fm.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        _ = Darwin.chmod(vaultDir.path, mode_t(0o700))
        markHiddenAndExcludedFromBackup(vaultDir, isDirectory: true, fileManager: &fm)

        let seedURL = vaultDir.appendingPathComponent(masterKeyFileName, isDirectory: false)
        if let existing = try? Data(contentsOf: seedURL), existing.count == 32 {
            _ = Darwin.chmod(seedURL.path, mode_t(0o600))
            return existing
        }

        let fresh = try generateCSPRNGBytes(count: 32)
        try writeAtomicSeed0600(fresh, to: seedURL, in: vaultDir)
        markHiddenAndExcludedFromBackup(seedURL, isDirectory: false, fileManager: &fm)
        return fresh
    }

    private static func deriveEnvelopeKey(fromRandomSeed seed: Data) -> SymmetricKey {
        let uuid = readHardwarePlatformUUID()
        var ikm = Data(capacity: seed.count + 64)
        ikm.append(seed)
        ikm.append(Data("|lumakey-vault-v2|\(uuid)|uid=\(getuid())".utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data("app.lumakey.macos.local-secret-vault.salt.v2".utf8),
            info: Data("aes-256-gcm-v2".utf8),
            outputByteCount: 32
        )
    }

    private static func generateCSPRNGBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw LocalSecretVaultError.ioFailed("CSPRNG SecRandomCopyBytes status \(status)")
        }
        return Data(bytes)
    }

    private static func writeAtomicSeed0600(_ data: Data, to targetURL: URL, in dirURL: URL) throws {
        let tmpURL = dirURL.appendingPathComponent(".seed-tmp-\(UUID().uuidString)", isDirectory: false)
        let fd = Darwin.open(tmpURL.path, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, mode_t(0o600))
        guard fd >= 0 else {
            throw LocalSecretVaultError.ioFailed("seed open errno \(errno)")
        }
        let ok: Bool = data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return true }
            var written = 0
            while written < ptr.count {
                let n = Darwin.write(fd, base.advanced(by: written), ptr.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
        _ = Darwin.fchmod(fd, mode_t(0o600))
        _ = Darwin.close(fd)
        guard ok else {
            try? FileManager.default.removeItem(at: tmpURL)
            throw LocalSecretVaultError.ioFailed("seed write errno \(errno)")
        }
        if Darwin.link(tmpURL.path, targetURL.path) != 0 {
            try? FileManager.default.removeItem(at: tmpURL)
            if let raced = try? Data(contentsOf: targetURL), raced.count == 32 {
                return
            }
            throw LocalSecretVaultError.ioFailed("seed link errno \(errno)")
        }
        try? FileManager.default.removeItem(at: tmpURL)
        _ = Darwin.chmod(targetURL.path, mode_t(0o600))
    }

    private static func markHiddenAndExcludedFromBackup(_ url: URL, isDirectory: Bool, fileManager: inout FileManager) {
        _ = Darwin.chflags(url.path, UInt32(UF_HIDDEN))
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        if !isDirectory { values.isHidden = true }
        try? mutableURL.setResourceValues(values)
    }

    private static func isStableSignedAppBundle() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return false }
        return CodeSigningInspector.inspect(bundleURL: bundleURL).isStableForTCC
    }

    private static func loadKeychainSeedSilently() -> Data? {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: ctx
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    private static func saveKeychainSeedSilently(_ seed: Data) -> Bool {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: seed
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func readHardwarePlatformUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "macos-arm64-local" }
        defer { IOObjectRelease(service) }
        if let cfProp = IORegistryEntryCreateCFProperty(
            service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String, !cfProp.isEmpty {
            return cfProp
        }
        return "macos-arm64-local"
    }
}
