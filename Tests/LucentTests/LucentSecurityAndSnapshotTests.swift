import CryptoKit
import Foundation
import Testing
@testable import LucentCore
@testable import LucentFoundation
@testable import LucentSearch

@Suite("Lucent Security & Snapshot Integrity Tests")
struct LucentSecurityAndSnapshotTests {
    private func makeIsolatedDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lucent-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("LocalSecretVault seals secrets with high-entropy CSPRNG seed and rejects legacy headers or foreign keys")
    func vaultCSPRNGSealingAndTamperRejection() throws {
        let root = try makeIsolatedDir("vault")
        defer { try? FileManager.default.removeItem(at: root) }

        let vaultDir = root.appendingPathComponent(".vault", isDirectory: true)
        let vaultURL = LocalSecretVault.defaultVaultFileURL(in: root)
        LocalSecretVault.clearMemoryCache()

        try LocalSecretVault.saveValue("fresh-secret-42", service: "svc", account: "acct", customVaultURL: vaultURL)
        LocalSecretVault.clearMemoryCache()

        let loaded = try LocalSecretVault.loadValue(service: "svc", account: "acct", customVaultURL: vaultURL)
        #expect(loaded == "fresh-secret-42")
        #expect(FileManager.default.fileExists(atPath: vaultURL.path))

        let v2Bytes = try Data(contentsOf: vaultURL)
        #expect(v2Bytes.prefix(LocalSecretVault.magicHeader.count) == LocalSecretVault.magicHeader)
        #expect(throws: LocalSecretVaultError.invalidCiphertext) {
            _ = try LocalSecretVault.openPayloadData(
                v2Bytes,
                vaultDirectory: vaultDir,
                keyOverride: SymmetricKey(size: .bits256)
            )
        }

        var unsupportedHeaderBlob = Data("LCNTVLT1".utf8)
        unsupportedHeaderBlob.append(Data(repeating: 0xAB, count: 48))
        #expect(throws: LocalSecretVaultError.invalidCiphertext) {
            _ = try LocalSecretVault.openPayloadData(unsupportedHeaderBlob, vaultDirectory: vaultDir)
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
            bridgeSocketPath: "/tmp/lc-bridge.sock",
            allowedScopes: []
        )
        #expect(strictProfile.contains("(deny network-outbound (remote ip))"))
        #expect(strictProfile.contains("(allow network-outbound (remote unix-socket (path-literal \"/tmp/lc-bridge.sock\")))"))
        #expect(strictProfile.contains("(deny file-write*"))
        #expect(strictProfile.contains("(deny process-exec*"))
        #expect(strictProfile.contains("(allow process-exec* (literal \"/Applications/Xcode.app/Contents/Developer/usr/bin/python3\")"))
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
            pluginVariables: ["LUCENT_LOCALE": "zh-Hans"],
            isolatedTmpDirectory: tmpDir,
            hostEnvironment: ["OPENAI_API_KEY": "sk-secret", "AWS_SECRET_ACCESS_KEY": "aws-sec", "LANG": "zh_CN.UTF-8"]
        )
        #expect(cleanEnv["OPENAI_API_KEY"] == nil)
        #expect(cleanEnv["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(cleanEnv["LUCENT_LOCALE"] == "zh-Hans")
        #expect(cleanEnv["TMPDIR"] == tmpDir.path)
    }

    @Test("EverythingSnapshotStore LCNTIDX3 detects bit-flip tampering and truncation")
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

    @Test("PluginSandboxProfileBuilder isolates sibling PluginData, host stores, credentials, and osascript/nc")
    func sandboxHardeningCrossPluginAndHostPrivacy() throws {
        let root = try makeIsolatedDir("sandbox-hardening")
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDir = root.appendingPathComponent("Plugins/plugin-a", isDirectory: true)
        let dataRoot = root.appendingPathComponent("PluginData", isDirectory: true)
        let dataDirA = dataRoot.appendingPathComponent("plugin-a", isDirectory: true)
        let tmpDir = root.appendingPathComponent("tmp-a", isDirectory: true)
        let vaultDir = root.appendingPathComponent(".vault", isDirectory: true)
        for d in [pluginDir, dataDirA, tmpDir, vaultDir] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }

        let strictProfile = PluginSandboxProfileBuilder.buildProfile(
            pluginDirectory: pluginDir,
            dataDirectory: dataDirA,
            isolatedTmpDirectory: tmpDir,
            vaultDirectories: [vaultDir],
            bridgeSocketPath: nil,
            allowedScopes: [],
            allowAppleScriptRuntime: false
        )
        let canonicalDataRoot = dataRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalDataA = dataDirA.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(strictProfile.contains("(deny file-read* file-write* (subpath \"\(canonicalDataRoot)\"))"))
        #expect(strictProfile.contains("(allow file-read* file-write* (subpath \"\(canonicalDataA)\"))"))
        #expect(strictProfile.contains("ClipboardHistory"))
        #expect(strictProfile.contains("plugin-state.json"))
        #expect(strictProfile.contains("/.kube"))
        #expect(strictProfile.contains("/.npmrc"))
        #expect(strictProfile.contains("(literal \"/usr/bin/osascript\")"))
        #expect(strictProfile.contains("(literal \"/usr/bin/nc\")"))
        #expect(strictProfile.contains("(literal \"/usr/bin/open\")"))

        let appleScriptProfile = PluginSandboxProfileBuilder.buildProfile(
            pluginDirectory: pluginDir,
            dataDirectory: nil,
            isolatedTmpDirectory: tmpDir,
            vaultDirectories: [vaultDir],
            bridgeSocketPath: nil,
            allowedScopes: [],
            allowAppleScriptRuntime: true
        )
        #expect(!appleScriptProfile.contains("(literal \"/usr/bin/osascript\")"))
    }

    @Test("LauncherEngine wakes Everything index selectively and extracts file stems without URL overhead")
    func launcherIndexWakeAndStemPolicy() {
        #expect(LauncherEngine.shouldWakeEverythingIndex(for: "", filter: .files, scopedPluginID: nil))
        #expect(!LauncherEngine.shouldWakeEverythingIndex(for: "", filter: .all, scopedPluginID: nil))
        #expect(!LauncherEngine.shouldWakeEverythingIndex(for: "s", filter: .all, scopedPluginID: nil))
        #expect(!LauncherEngine.shouldWakeEverythingIndex(for: "1+2*3", filter: .all, scopedPluginID: nil))
        #expect(!LauncherEngine.shouldWakeEverythingIndex(for: "notes", filter: .all, scopedPluginID: "translate-hub"))
        #expect(LauncherEngine.shouldWakeEverythingIndex(for: "ab", filter: .all, scopedPluginID: nil))
        #expect(LauncherEngine.shouldWakeEverythingIndex(for: "文", filter: .all, scopedPluginID: nil))
        #expect(LauncherEngine.shouldWakeEverythingIndex(for: "f a", filter: .all, scopedPluginID: nil))
        #expect(LauncherEngine.shouldWakeEverythingIndex(for: "ext:md", filter: .all, scopedPluginID: nil))

        #expect(LauncherEngine.stemLowercased(of: "report.pdf") == "report")
        #expect(LauncherEngine.stemLowercased(of: "archive.tar.gz") == "archive.tar")
        #expect(LauncherEngine.stemLowercased(of: ".gitignore") == ".gitignore")
        #expect(LauncherEngine.stemLowercased(of: "makefile") == "makefile")

        #expect(PluginSelectionReader.defaultAXMessagingTimeoutSeconds > 0
                && PluginSelectionReader.defaultAXMessagingTimeoutSeconds <= 0.5)
    }

    @Test("DirectoryEntryEnumerator getattrlistbulk matches readdir across Unicode, packages, symlinks, dotfiles, and exclusions")
    func getattrlistbulkMatchesReaddirExactly() throws {
        let root = try makeIsolatedDir("bulk-enum")
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let normalDir = root.appendingPathComponent("中文目录", isDirectory: true)
        let skippedDir = root.appendingPathComponent("node_modules", isDirectory: true)
        let appPkg = root.appendingPathComponent("Demo.app", isDirectory: true)
        let excludedDir = root.appendingPathComponent("SecretSkip", isDirectory: true)
        for d in [normalDir, skippedDir, appPkg, excludedDir] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        try Data("ok".utf8).write(to: root.appendingPathComponent("设计文档 2026.md"))
        try Data("dot".utf8).write(to: root.appendingPathComponent(".hidden"))
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("link-to-dir"),
            withDestinationURL: normalDir
        )

        let exclusions = EverythingIndex.normalizedExcludedSet([excludedDir.path])
        let bulk = try #require(DirectoryEntryEnumerator.enumerateViaGetAttrListBulk(
            at: root.path, includeHidden: false, excludedPaths: exclusions,
            skippedFolders: DirectoryEntryEnumerator.defaultSkippedFolders, scratchBuffer: nil
        ))
        let posix = DirectoryEntryEnumerator.enumerateViaReaddir(
            at: root.path, includeHidden: false, excludedPaths: exclusions,
            skippedFolders: DirectoryEntryEnumerator.defaultSkippedFolders
        )

        #expect(Set(bulk) == Set(posix))
        #expect(bulk.contains(DirectoryChildEntry(name: "中文目录", isDirectory: true)))
        #expect(bulk.contains(DirectoryChildEntry(name: "设计文档 2026.md", isDirectory: false)))
        #expect(bulk.contains(DirectoryChildEntry(name: "Demo.app", isDirectory: false)))
        #expect(bulk.contains(DirectoryChildEntry(name: "link-to-dir", isDirectory: false)))
        let bulkNames = Set(bulk.map(\.name))
        #expect(bulkNames.isDisjoint(with: ["node_modules", "SecretSkip", ".hidden"]))

        let withHiddenBulk = try #require(DirectoryEntryEnumerator.enumerateViaGetAttrListBulk(
            at: root.path, includeHidden: true, excludedPaths: exclusions,
            skippedFolders: DirectoryEntryEnumerator.defaultSkippedFolders, scratchBuffer: nil
        ))
        #expect(withHiddenBulk.contains(DirectoryChildEntry(name: ".hidden", isDirectory: false)))
    }
}
