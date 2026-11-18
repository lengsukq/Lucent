import Compression
import CryptoKit
import Foundation
import Security

extension BackupArchiveService {
    public static let compressedMagicHeader = Data("LCNTBK02".utf8)
    public static let maxDecompressedArchiveBytes: Int = 256 * 1024 * 1024
    private static let secretsAuthAAD = Data("LCNTSEC2".utf8)
    private static let kdfRounds = 65_536

    public static func isCompressedArchive(_ data: Data) -> Bool {
        data.count > compressedMagicHeader.count + 8 && data.prefix(compressedMagicHeader.count) == compressedMagicHeader
    }

    static func compressLZFSEFrame(_ rawJSON: Data) throws -> Data {
        guard !rawJSON.isEmpty else { return rawJSON }
        let dstCap = rawJSON.count + max(4096, rawJSON.count / 8)
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCap)
        defer { dstBuf.deallocate() }

        let compressedCount: Int = rawJSON.withUnsafeBytes { srcPtr in
            guard let base = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dstBuf, dstCap, base, rawJSON.count, nil, COMPRESSION_LZFSE)
        }
        guard compressedCount > 0 else {
            throw BackupArchiveError.ioFailed("LZFSE 归档压缩失败")
        }
        var out = Data()
        out.reserveCapacity(compressedMagicHeader.count + 8 + compressedCount)
        out.append(compressedMagicHeader)
        var rawLenLE = UInt64(rawJSON.count).littleEndian
        withUnsafeBytes(of: &rawLenLE) { out.append(contentsOf: $0) }
        out.append(dstBuf, count: compressedCount)
        return out
    }

    static func decompressIfNeeded(_ archiveData: Data) throws -> Data {
        guard isCompressedArchive(archiveData) else { return archiveData }
        let headerEnd = compressedMagicHeader.count
        let lenBytes = archiveData.subdata(in: headerEnd..<(headerEnd + 8))
        let expectedLen = Int(lenBytes.withUnsafeBytes { $0.load(as: UInt64.self).littleEndian })
        guard expectedLen > 0, expectedLen <= maxDecompressedArchiveBytes else {
            throw BackupArchiveError.corruptedArchive("压缩头声明长度异常 (\(expectedLen))")
        }
        let payloadSlice = archiveData.dropFirst(headerEnd + 8)
        guard !payloadSlice.isEmpty else {
            throw BackupArchiveError.corruptedArchive("压缩归档数据帧为空")
        }

        let dstCap = expectedLen + 64
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCap)
        defer { dstBuf.deallocate() }

        let decodedCount: Int = payloadSlice.withUnsafeBytes { srcPtr in
            guard let base = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(dstBuf, dstCap, base, payloadSlice.count, nil, COMPRESSION_LZFSE)
        }
        guard decodedCount == expectedLen else {
            throw BackupArchiveError.corruptedArchive("LZFSE 解压字节数不匹配（期望 \(expectedLen)，实际 \(decodedCount)）")
        }
        return Data(bytes: dstBuf, count: decodedCount)
    }

    static func derivePassphraseKey(passphrase: String, salt: Data) -> SymmetricKey {
        let passData = Data(passphrase.utf8)
        var digest = Data(SHA256.hash(data: salt + passData))
        for _ in 1..<kdfRounds {
            var hasher = SHA256()
            hasher.update(data: digest)
            hasher.update(data: salt)
            digest = Data(hasher.finalize())
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: digest),
            salt: salt,
            info: Data("LucentBackupSecretsV2".utf8),
            outputByteCount: 32
        )
    }

    static func sealPluginSecrets(
        in pluginsDir: URL,
        passphrase: String
    ) throws -> BackupEncryptedSecretsEnvelope? {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let plugins = PluginSystem.listPlugins(in: pluginsDir, includeDisabled: true, includeBuiltin: false, includeSecrets: false)
        let service = PluginDataPaths.keychainService(forPluginsRoot: pluginsDir)
        let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: pluginsDir)
        var secretMap: [String: [String: String]] = [:]

        for plugin in plugins where PluginSystem.isSafePluginID(plugin.id) {
            let secretFields = (plugin.manifest.config ?? []).filter { $0.type == .secret }
            guard !secretFields.isEmpty else { continue }
            var perPlugin: [String: String] = [:]
            for field in secretFields {
                if let val = try? PluginKeychainStore.loadSecret(
                    pluginID: plugin.id, fieldKey: field.key,
                    service: service, customVaultURL: scopedVault
                ), !val.isEmpty {
                    perPlugin[field.key] = val
                }
            }
            if !perPlugin.isEmpty {
                secretMap[plugin.id] = perPlugin
            }
        }
        guard !secretMap.isEmpty else { return nil }

        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 16, ptr.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw BackupArchiveError.ioFailed("安全随机盐生成失败")
        }

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let plainBytes = try enc.encode(secretMap)
        let key = derivePassphraseKey(passphrase: trimmed, salt: salt)
        let sealed = try AES.GCM.seal(plainBytes, using: key, nonce: AES.GCM.Nonce(), authenticating: secretsAuthAAD)
        guard let combined = sealed.combined else {
            throw BackupArchiveError.ioFailed("AES-GCM 密钥封装失败")
        }
        return BackupEncryptedSecretsEnvelope(
            saltBase64: salt.base64EncodedString(),
            sealedBoxBase64: combined.base64EncodedString()
        )
    }

    static func openAndRestorePluginSecrets(
        _ envelope: BackupEncryptedSecretsEnvelope,
        passphrase: String?,
        in pluginsDir: URL
    ) throws -> [String] {
        let trimmed = (passphrase ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackupArchiveError.passwordRequired
        }
        guard let salt = Data(base64Encoded: envelope.saltBase64), salt.count >= 12,
              let combined = Data(base64Encoded: envelope.sealedBoxBase64) else {
            throw BackupArchiveError.corruptedArchive("加密密钥信封格式损坏")
        }
        let key = derivePassphraseKey(passphrase: trimmed, salt: salt)
        let plainBytes: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            plainBytes = try AES.GCM.open(box, using: key, authenticating: secretsAuthAAD)
        } catch {
            throw BackupArchiveError.invalidPassword
        }

        guard let secretMap = try? JSONDecoder().decode([String: [String: String]].self, from: plainBytes) else {
            throw BackupArchiveError.corruptedArchive("解密后的插件密钥字典无效")
        }
        let service = PluginDataPaths.keychainService(forPluginsRoot: pluginsDir)
        let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: pluginsDir)
        var restoredIDs: [String] = []
        for pluginID in secretMap.keys.sorted() {
            guard PluginSystem.isSafePluginID(pluginID), let kv = secretMap[pluginID] else {
                throw BackupArchiveError.unsafePluginID(pluginID)
            }
            var wrote = false
            for (fieldKey, val) in kv where !fieldKey.isEmpty && fieldKey.count <= 128 && !val.isEmpty {
                try PluginKeychainStore.saveSecret(
                    val, pluginID: pluginID, fieldKey: fieldKey,
                    service: service, customVaultURL: scopedVault
                )
                wrote = true
            }
            if wrote { restoredIDs.append(pluginID) }
        }
        return restoredIDs
    }
}
