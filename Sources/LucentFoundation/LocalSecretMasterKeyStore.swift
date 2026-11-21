import CryptoKit
import Darwin
import Foundation
import IOKit
import LocalAuthentication
import Security

/// 双轨高熵主密钥管理器：
/// 1. 具备 Apple `TeamIdentifier` 的稳定签名 `.app` 构建（Developer ID / Apple Development）：优先将 256-bit CSPRNG 随机主密钥存入系统 Keychain（`teamid:` 分区跨重编零弹窗）；
/// 2. 本机自签名证书（无 Team ID）/ Ad-hoc 社区构建 / CLI / 自定义测试库：采用 `SecRandomCopyBytes` 生成 32 字节真随机种子（`0600` + `UF_HIDDEN` + 排除备份），
///    再结合硬件平台标识进行 HKDF 信封派生，避免无 Team ID 触发 `cdhash:` 钥匙串反复弹窗，并支持历史 Keychain 种子单次无损迁移落盘。
public enum LocalSecretMasterKeyStore {
    public static let masterKeyFileName = "master.v2.key"
    public static let keychainService = "app.lucent.macos.vault.master-key"
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

    // MARK: - Internal Seed Resolution

    private enum BundleKeychainPolicy {
        case stableKeychain
        case migrateLegacyKeychainToLocalFile
        case localFileOnly
    }

    private static func resolveRawSeed(
        forVaultDirectory vaultDir: URL,
        allowSystemKeychain: Bool?
    ) throws -> Data {
        let defaultVaultDir = LocalSecretVault.defaultVaultFileURL().deletingLastPathComponent().standardizedFileURL.path
        let isDefaultVault = (vaultDir.standardizedFileURL.path == defaultVaultDir)
        let bundlePolicy = signingKeychainPolicy()
        let shouldUseKeychain = allowSystemKeychain ?? (isDefaultVault && bundlePolicy == .stableKeychain)
        let seedURL = vaultDir.appendingPathComponent(masterKeyFileName, isDirectory: false)

        if shouldUseKeychain {
            if let existingKC = loadKeychainSeedSilently(), existingKC.count == 32 {
                return existingKC
            }
            if let existingLocal = try? Data(contentsOf: seedURL), existingLocal.count == 32 {
                _ = saveKeychainSeedSilently(existingLocal)
                return existingLocal
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

        if let existing = try? Data(contentsOf: seedURL), existing.count == 32 {
            _ = Darwin.chmod(seedURL.path, mode_t(0o600))
            return existing
        }

        if allowSystemKeychain == nil,
           isDefaultVault,
           bundlePolicy == .migrateLegacyKeychainToLocalFile,
           hasExistingEncryptedVault(in: vaultDir),
           hasKeychainSeedMetadata() {
            guard let migrated = loadKeychainSeedSilently(), migrated.count == 32 else {
                throw LocalSecretVaultError.ioFailed("keychain master key migration denied or unavailable")
            }
            try writeAtomicSeed0600(migrated, to: seedURL, in: vaultDir)
            markHiddenAndExcludedFromBackup(seedURL, isDirectory: false, fileManager: &fm)
            return migrated
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
        ikm.append(Data("|lucent-vault-v2|\(uuid)|uid=\(getuid())".utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data("app.lucent.macos.local-secret-vault.salt.v2".utf8),
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

    private static func signingKeychainPolicy() -> BundleKeychainPolicy {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return .localFileOnly }
        let status = CodeSigningInspector.inspect(bundleURL: bundleURL)
        if status.isStableForKeychain { return .stableKeychain }
        if status.isStableForTCC { return .migrateLegacyKeychainToLocalFile }
        return .localFileOnly
    }

    private static func hasExistingEncryptedVault(in vaultDir: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: vaultDir.appendingPathComponent(LocalSecretVault.vaultFileName, isDirectory: false).path) {
            return true
        }
        let servicesDir = vaultDir.appendingPathComponent("services", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(atPath: servicesDir.path) else { return false }
        return entries.contains { $0.hasSuffix(".v2.enc") }
    }

    private static func hasKeychainSeedMetadata() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
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
