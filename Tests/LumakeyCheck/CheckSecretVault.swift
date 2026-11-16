import CryptoKit
import Foundation
import LumakeyCore

func testV087LocalSecretVaultAndLazyLoading() throws {
    let tmp = try makeTempDir("v087-vault")
    defer { try? FileManager.default.removeItem(at: tmp) }

    // 1. Verify 0700 directory + 0600 file permissions + AES-GCM ciphertext opacity + tamper detection
    let vaultDir = tmp.appendingPathComponent(".vault", isDirectory: true)
    let vaultURL = vaultDir.appendingPathComponent("secrets.v1.enc", isDirectory: false)
    let rawSecret = "ntn_super_secret_token_987654321"

    try LocalSecretVault.saveValue(rawSecret, service: "test.svc", account: "notion:token", customVaultURL: vaultURL)
    check(FileManager.default.fileExists(atPath: vaultURL.path), "vault file written on disk")

    let dirPerms = ((try FileManager.default.attributesOfItem(atPath: vaultDir.path)[.posixPermissions]) as? Int) ?? 0
    let filePerms = ((try FileManager.default.attributesOfItem(atPath: vaultURL.path)[.posixPermissions]) as? Int) ?? 0
    check((dirPerms & 0o777) == 0o700, "vault directory permissions strictly 0700 (got \(String(dirPerms & 0o777, radix: 8)))")
    check((filePerms & 0o777) == 0o600, "vault file permissions strictly 0600 (got \(String(filePerms & 0o777, radix: 8)))")

    let onDiskBytes = try Data(contentsOf: vaultURL)
    check(onDiskBytes.prefix(LocalSecretVault.magicHeader.count) == LocalSecretVault.magicHeader, "vault starts with LMKYVLT1 header")
    check(onDiskBytes.range(of: Data(rawSecret.utf8)) == nil, "plaintext secret never appears in on-disk vault bytes")
    check(onDiskBytes.range(of: Data("notion:token".utf8)) == nil, "account identifiers encrypted inside AES-GCM payload")

    LocalSecretVault.clearMemoryCache()
    let reloaded = try LocalSecretVault.loadValue(service: "test.svc", account: "notion:token", customVaultURL: vaultURL)
    check(reloaded == rawSecret, "cold reload from disk decrypts exact secret")

    // Verify wrong symmetric key fails authentication
    let foreignKey = SymmetricKey(size: .bits256)
    var rejectedForeignKey = false
    do {
        _ = try LocalSecretVault.openPayloadData(onDiskBytes, keyOverride: foreignKey)
    } catch LocalSecretVaultError.invalidCiphertext {
        rejectedForeignKey = true
    }
    check(rejectedForeignKey, "AES-GCM rejects decryption with foreign machine key")

    // Verify single-byte ciphertext tampering fails authentication
    var tampered = onDiskBytes
    tampered[tampered.count - 4] ^= 0xFF
    try tampered.write(to: vaultURL, options: .atomic)
    LocalSecretVault.clearMemoryCache()
    var rejectedTamper = false
    do {
        _ = try LocalSecretVault.loadValue(service: "test.svc", account: "notion:token", customVaultURL: vaultURL)
    } catch LocalSecretVaultError.invalidCiphertext {
        rejectedTamper = true
    }
    check(rejectedTamper, "AES-GCM authentication tag catches 1-byte tampering")

    // 2. Verify BackupArchiveService strictly isolates .vault and rejects secret/vault config names
    let supportDir = tmp.appendingPathComponent("Support", isDirectory: true)
    let prodLikeVault = LocalSecretVault.defaultVaultFileURL(in: supportDir)
    try LocalSecretVault.saveValue("do-not-export-me-ever", service: "app.lumakey.macos.plugins", account: "p1:key", customVaultURL: prodLikeVault)
    AppLanguageConfig(selectedLanguage: .zhHans).save(to: supportDir.appendingPathComponent("language-config.json"))

    let backupData = try BackupArchiveService.exportBackupData(appSupportDirectory: supportDir, appVersion: "0.8.7")
    let backupText = String(data: backupData, encoding: .utf8) ?? ""
    check(!backupText.contains("do-not-export-me-ever") && !backupText.contains("secrets.v1.enc") && !backupText.contains("LMKYVLT1"), "BackupArchiveService completely excludes .vault encrypted file")
    check(!BackupArchiveService.isSafeConfigFileName("secrets.json"), "BackupArchiveService rejects secrets.json")
    check(!BackupArchiveService.isSafeConfigFileName("local-vault.json"), "BackupArchiveService rejects *vault*.json")

    // 3. Verify lazy loading: listPlugins(includeSecrets: false) keeps userConfig secret-free, while resolvedUserConfigWithSecrets & runScriptPlugin load on demand
    let pluginsDir = supportDir.appendingPathComponent("Plugins", isDirectory: true)
    let pluginDir = pluginsDir.appendingPathComponent("lazy-sec-demo", isDirectory: true)
    try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

    let manifestJSON = """
    {
      "schemaVersion": 3,
      "id": "lazy-sec-demo",
      "name": "Lazy Secret Demo",
      "version": "1.0.0",
      "description": "Verifies lazy secret loading",
      "mode": "script",
      "keywords": ["lazysec"],
      "entry": "run.sh",
      "capabilities": [],
      "resourceScopes": [],
      "config": [
        { "key": "endpoint", "label": "Endpoint", "type": "text", "defaultValue": "https://api.example.com" },
        { "key": "api_key", "label": "API Key", "type": "secret", "required": true }
      ]
    }
    """
    try manifestJSON.write(to: pluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
    let scriptBody = """
    #!/bin/sh
    cat
    """
    let scriptURL = pluginDir.appendingPathComponent("run.sh")
    try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let sandboxService = PluginDataPaths.keychainService(forPluginsRoot: pluginsDir)
    defer { PluginKeychainStore.deleteSecrets(pluginID: "lazy-sec-demo", fieldKeys: ["api_key"], service: sandboxService) }

    try PluginSystem.updatePluginConfig(
        id: "lazy-sec-demo",
        values: ["endpoint": "https://custom.example.com", "api_key": "sk-lazy-vault-777"],
        in: pluginsDir
    )

    // Cold startup / list refresh path: includeSecrets: false
    let coldList = PluginSystem.listPlugins(in: pluginsDir, includeBuiltin: false, includeSecrets: false)
    guard let coldPlugin = coldList.first(where: { $0.id == "lazy-sec-demo" }) else {
        check(false, "lazy-sec-demo listed")
        return
    }
    check(coldPlugin.userConfig["endpoint"] == "https://custom.example.com", "non-secret config loaded on startup")
    check(coldPlugin.userConfig["api_key"] == nil, "secret NOT loaded into memory when includeSecrets == false")

    // Settings inspector path: resolvedUserConfigWithSecrets loads on demand
    let inspectorConfig = PluginSystem.resolvedUserConfigWithSecrets(for: coldPlugin, in: pluginsDir)
    check(inspectorConfig["api_key"] == "sk-lazy-vault-777", "resolvedUserConfigWithSecrets lazily loads secret for settings view")

    // Execution path: running coldPlugin (even though coldPlugin.userConfig had no secret) injects secret into stdin on demand!
    let execRes = try PluginSystem.runScriptPlugin(coldPlugin, query: "ping", in: pluginsDir)
    check(execRes.exitCode == 0 && execRes.stdout.contains("sk-lazy-vault-777"), "runScriptPlugin lazily resolves secret from 0600 vault on execution")

    print("[ok] v0.8.7 LocalSecretVault (0700/0600 AES-GCM + Tamper Guard + Backup Isolation) & Lazy Secret Loading")
}
