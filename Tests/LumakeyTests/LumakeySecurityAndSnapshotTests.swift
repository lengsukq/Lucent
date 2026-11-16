import CryptoKit
import Foundation
import Testing
@testable import LumakeyCore
@testable import LumakeyFoundation
@testable import LumakeySearch

@Suite("Lumakey Security & Snapshot Integrity Tests")
struct LumakeySecurityAndSnapshotTests {
    private func makeIsolatedDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumakey-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("LocalSecretVault v2 uses high-entropy CSPRNG seed and migrates legacy LMKYVLT1")
    func vaultCSPRNGAndLegacyMigration() throws {
        let root = try makeIsolatedDir("vault")
        defer { try? FileManager.default.removeItem(at: root) }

        let vaultDir = root.appendingPathComponent(".vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let legacyURL = vaultDir.appendingPathComponent(LocalSecretVault.legacyVaultFileName)

        let v1Plain = Data(#"{"schemaVersion":1,"services":{"svc":{"acct":"migrated-secret-42"}}}"#.utf8)
        let v1Sealed = try AES.GCM.seal(
            v1Plain,
            using: LocalSecretMasterKeyStore.deriveLegacyV1Key(),
            nonce: AES.GCM.Nonce(),
            authenticating: LocalSecretVault.legacyV1MagicHeader
        )
        var legacyBlob = Data(LocalSecretVault.legacyV1MagicHeader)
        legacyBlob.append(try #require(v1Sealed.combined))
        try legacyBlob.write(to: legacyURL, options: .atomic)
        LocalSecretVault.clearMemoryCache()

        let v2URL = LocalSecretVault.defaultVaultFileURL(in: root)
        let loaded = try LocalSecretVault.loadValue(service: "svc", account: "acct", customVaultURL: v2URL)
        #expect(loaded == "migrated-secret-42")
        #expect(FileManager.default.fileExists(atPath: v2URL.path))
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))

        let v2Bytes = try Data(contentsOf: v2URL)
        #expect(v2Bytes.prefix(LocalSecretVault.magicHeader.count) == LocalSecretVault.magicHeader)
        #expect(throws: LocalSecretVaultError.invalidCiphertext) {
            _ = try LocalSecretVault.openPayloadData(
                v2Bytes,
                vaultDirectory: vaultDir,
                keyOverride: LocalSecretMasterKeyStore.deriveLegacyV1Key()
            )
        }
    }

    @Test("PluginSandboxProfileBuilder enforces scope isolation and blocks vault access")
    func sandboxProfileScopeIsolation() throws {
        let root = try makeIsolatedDir("sandbox")
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDir = root.appendingPathComponent("Plugins/demo", isDirectory: true)
        let dataDir = root.appendingPathComponent("PluginData/demo", isDirectory: true)
        let tmpDir = root.appendingPathComponent("tmp", isDirectory: true)
        let vaultDir = root.appendingPathComponent(".vault", isDirectory: true)
        for d in [pluginDir, dataDir, tmpDir, vaultDir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }

        let strictProfile = PluginSandboxProfileBuilder.buildProfile(
            pluginDirectory: pluginDir,
            dataDirectory: dataDir,
            isolatedTmpDirectory: tmpDir,
            vaultDirectories: [vaultDir],
            bridgeSocketPath: "/tmp/lk-bridge.sock",
            allowedScopes: []
        )
        #expect(strictProfile.contains("(deny network-outbound (remote ip))"))
        #expect(strictProfile.contains("(allow network-outbound (remote unix-socket (path-literal \"/tmp/lk-bridge.sock\")))"))
        #expect(strictProfile.contains("(deny file-write*"))
        #expect(strictProfile.contains("(deny process-exec*"))
        #expect(strictProfile.contains("(deny file-read* file-write* (subpath \"\(vaultDir.standardizedFileURL.path)\"))"))

        // Even when all scopes are granted, .vault and Keychains remain unconditionally blocked at profile tail
        let permissiveProfile = PluginSandboxProfileBuilder.buildProfile(
            pluginDirectory: pluginDir,
            dataDirectory: dataDir,
            isolatedTmpDirectory: tmpDir,
            vaultDirectories: [vaultDir],
            bridgeSocketPath: nil,
            allowedScopes: [.network, .filesystem, .subprocess]
        )
        #expect(!permissiveProfile.contains("(deny network-outbound (remote ip))"))
        #expect(permissiveProfile.hasSuffix("(deny file-read* file-write* (subpath \"\(vaultDir.resolvingSymlinksInPath().standardizedFileURL.path)\"))")
                || permissiveProfile.contains("(deny file-read* file-write* (subpath \"\(vaultDir.standardizedFileURL.path)\"))"))

        let cleanEnv = PluginSandboxProfileBuilder.sanitizedEnvironment(
            pluginVariables: ["LUMAKEY_LOCALE": "zh-Hans"],
            isolatedTmpDirectory: tmpDir,
            hostEnvironment: ["OPENAI_API_KEY": "sk-secret", "AWS_SECRET_ACCESS_KEY": "aws-sec", "LANG": "zh_CN.UTF-8"]
        )
        #expect(cleanEnv["OPENAI_API_KEY"] == nil)
        #expect(cleanEnv["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(cleanEnv["LUMAKEY_LOCALE"] == "zh-Hans")
        #expect(cleanEnv["TMPDIR"] == tmpDir.path)
    }

    @Test("EverythingSnapshotStore LMKYIDX3 detects bit-flip tampering and truncation")
    func snapshotIntegrityAndCorruptionRecovery() throws {
        let root = try makeIsolatedDir("idx3")
        defer { try? FileManager.default.removeItem(at: root) }

        let scanRoot = root.appendingPathComponent("Files", isDirectory: true)
        let cacheDir = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data("swift".utf8).write(to: scanRoot.appendingPathComponent("Kernel.swift"))

        let index = try EverythingIndex.build(rootURLs: [scanRoot], maxNodes: 200)
        let snapURL = try #require(EverythingSnapshotStore.save(index, scopeKey: "unit-idx3", cacheDirectory: cacheDir))
        let valid = EverythingSnapshotStore.load(scopeKey: "unit-idx3", expectedRoots: [scanRoot], cacheDirectory: cacheDir)
        #expect(valid?.nodes.count == 1)

        // 1. Flip a byte inside node payload -> SHA-256 mismatch must safely return nil
        let originalBytes = try Data(contentsOf: snapURL)
        var corrupted = originalBytes
        corrupted[originalBytes.count - 36] ^= 0x5A
        try corrupted.write(to: snapURL, options: .atomic)
        #expect(EverythingSnapshotStore.load(scopeKey: "unit-idx3", expectedRoots: [scanRoot], cacheDirectory: cacheDir) == nil)

        // 2. Truncate mid-file -> bounds + SHA-256 check must safely return nil
        let truncated = originalBytes.prefix(originalBytes.count - 20)
        try truncated.write(to: snapURL, options: .atomic)
        #expect(EverythingSnapshotStore.load(scopeKey: "unit-idx3", expectedRoots: [scanRoot], cacheDirectory: cacheDir) == nil)
    }
}
