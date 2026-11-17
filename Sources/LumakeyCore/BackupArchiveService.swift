import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import CryptoKit
import Foundation

public enum BackupArchiveService {
    public static let defaultMaxEmbeddedImageBytes: Int = 2 * 1024 * 1024
    static let typedConfigReservedNames: Set<String> = [
        "mos-config.json", "telemetry-v2.json", "pinned-clipboard.json"
    ]
    static let redactedWebDAVKeys: Set<String> = [
        "password", "passwd", "apppassword", "webdavpassword", "authpassword", "secret", "token"
    ]

    public static func defaultAppSupportDirectory() -> URL {
        LumakeyAppPaths.defaultAppSupportDirectory()
    }

    public static func defaultBackupFileName(date: Date = Date()) -> String {
        var sec = time_t(date.timeIntervalSince1970)
        var local = tm()
        localtime_r(&sec, &local)
        return String(
            format: "lumakey-backup-%04d%02d%02d-%02d%02d%02d.%@",
            Int(local.tm_year) + 1900, Int(local.tm_mon) + 1, Int(local.tm_mday),
            Int(local.tm_hour), Int(local.tm_min), Int(local.tm_sec),
            BackupEnvelope.fileExtension
        )
    }

    public static func computePayloadSHA256(_ payload: BackupPayload) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let bytes = try enc.encode(payload)
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isSafeConfigFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix(".") else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(".."), !name.contains("\0") else { return false }
        let lower = name.lowercased()
        guard !lower.contains("vault"), !lower.contains("secret") else { return false }
        return lower.hasSuffix(".json")
    }

    public static func isSafeRelativePluginPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 256 else { return false }
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.hasPrefix("~") else { return false }
        guard !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    public static func exportBackupData(
        appSupportDirectory: URL = defaultAppSupportDirectory(),
        pluginsDirectory: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        clipboardEntries: [ClipboardEntry] = [],
        mosConfig: MosConfig? = nil,
        telemetryConfig: SystemMonitorConfig? = nil,
        maxEmbeddedImageBytes: Int = defaultMaxEmbeddedImageBytes,
        maxPluginDataBytesPerPlugin: Int = defaultMaxPluginDataBytesPerPlugin,
        encryptionPassphrase: String? = nil,
        compress: Bool = false,
        appVersion: String = "0.7.1",
        createdAt: Date = Date()
    ) throws -> Data {
        let resolvedPluginsDir = pluginsDirectory ?? appSupportDirectory.appendingPathComponent("Plugins", isDirectory: true)
        let resolvedMos = mosConfig ?? MosConfig.load(from: appSupportDirectory.appendingPathComponent("mos-config.json"))
        let resolvedTelemetry = telemetryConfig ?? SystemMonitorConfig.load(from: appSupportDirectory.appendingPathComponent("telemetry-v2.json"))
        let rawConfigs = collectRawConfigFiles(in: appSupportDirectory)
        let clipboardRecords = encodePinnedClipboard(clipboardEntries, maxEmbeddedImageBytes: maxEmbeddedImageBytes)
        let pluginBundles = collectPluginBundles(in: resolvedPluginsDir)
        let pluginDataBundles = collectPluginDataBundles(in: resolvedPluginsDir, maxBytesPerPlugin: maxPluginDataBytesPerPlugin)
        let externalFiles = collectExternalPluginFiles(in: resolvedPluginsDir, homeDirectory: homeDirectory)
        let encryptedSecrets: BackupEncryptedSecretsEnvelope? = if let pass = encryptionPassphrase, !pass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try sealPluginSecrets(in: resolvedPluginsDir, passphrase: pass)
        } else {
            nil
        }

        let draftPayload = BackupPayload(
            mosConfig: resolvedMos,
            telemetryConfig: resolvedTelemetry,
            rawConfigFiles: rawConfigs,
            pinnedClipboardItems: clipboardRecords,
            plugins: pluginBundles,
            pluginData: pluginDataBundles,
            externalPluginFiles: externalFiles,
            encryptedPluginSecrets: encryptedSecrets
        )
        let canonicalEnc = JSONEncoder()
        canonicalEnc.outputFormatting = [.sortedKeys]
        let normalizedPayload = try JSONDecoder().decode(BackupPayload.self, from: canonicalEnc.encode(draftPayload))
        let sha256 = try computePayloadSHA256(normalizedPayload)

        let iso = ISO8601DateFormatter()
        let envelope = BackupEnvelope(
            schemaVersion: BackupEnvelope.currentSchemaVersion,
            createdAtISO8601: iso.string(from: createdAt),
            appVersion: appVersion,
            hostName: ProcessInfo.processInfo.hostName,
            payloadSHA256: sha256,
            payload: normalizedPayload
        )
        let outEnc = JSONEncoder()
        outEnc.outputFormatting = compress ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        let rawJSON = try outEnc.encode(envelope)
        return compress ? try compressLZFSEFrame(rawJSON) : rawJSON
    }

    public static func inspectBackupData(_ data: Data) throws -> BackupInspectionSummary {
        let compressed = isCompressedArchive(data)
        let rawJSON = try decompressIfNeeded(data)
        let envelope = try decodeAndVerifyEnvelope(rawJSON)
        let p = envelope.payload
        let configNames = ["mos-config.json", "telemetry-v2.json"] + p.rawConfigFiles.keys.sorted()
        let skippedImages = p.pinnedClipboardItems.filter(\.skippedLargeImage).count
        let dataFiles = p.pluginData.reduce(0) { $0 + $1.files.count }
        return BackupInspectionSummary(
            schemaVersion: envelope.schemaVersion,
            createdAtISO8601: envelope.createdAtISO8601,
            appVersion: envelope.appVersion,
            hostName: envelope.hostName,
            payloadSHA256: envelope.payloadSHA256,
            archiveByteCount: data.count,
            isCompressed: compressed,
            configFileNames: configNames,
            pinnedClipboardCount: p.pinnedClipboardItems.count,
            skippedLargeImageCount: skippedImages,
            pluginIDs: p.plugins.map(\.id),
            pluginDataPluginIDs: p.pluginData.map(\.id),
            pluginDataFileCount: dataFiles,
            externalFileCount: p.externalPluginFiles.count,
            hasEncryptedSecrets: p.encryptedPluginSecrets != nil
        )
    }

    public static func restoreBackupData(
        _ data: Data,
        options: BackupRestoreOptions = .all,
        appSupportDirectory: URL = defaultAppSupportDirectory(),
        pluginsDirectory: URL? = nil,
        clipboardImagesDirectory: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> BackupRestoreReport {
        let rawJSON = try decompressIfNeeded(data)
        let envelope = try decodeAndVerifyEnvelope(rawJSON)
        let payload = envelope.payload
        let resolvedPluginsDir = pluginsDirectory ?? appSupportDirectory.appendingPathComponent("Plugins", isDirectory: true)
        let resolvedClipDir = clipboardImagesDirectory ?? appSupportDirectory.appendingPathComponent("ClipboardPinned", isDirectory: true)

        try validatePayloadSafety(
            payload,
            appSupportDirectory: appSupportDirectory,
            pluginsDirectory: resolvedPluginsDir,
            homeDirectory: homeDirectory
        )

        var restoredSecretPlugins: [String] = []
        if options.restoreEncryptedSecrets, let secretEnv = payload.encryptedPluginSecrets {
            restoredSecretPlugins = try openAndRestorePluginSecrets(
                secretEnv, passphrase: options.decryptionPassphrase, in: resolvedPluginsDir
            )
        }

        let safetyURL: URL? = options.createSafetySnapshotBeforeRestore
            ? writePreRestoreSafetySnapshot(appSupportDirectory: appSupportDirectory, pluginsDirectory: resolvedPluginsDir)
            : nil

        var restoredConfigs: [String] = []
        if options.restoreConfigs {
            try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            payload.mosConfig.save(to: appSupportDirectory.appendingPathComponent("mos-config.json"))
            payload.telemetryConfig.save(to: appSupportDirectory.appendingPathComponent("telemetry-v2.json"))
            restoredConfigs.append(contentsOf: ["mos-config.json", "telemetry-v2.json"])

            for name in payload.rawConfigFiles.keys.sorted() {
                guard let content = payload.rawConfigFiles[name] else { continue }
                let cleanContent = sanitizeConfigTextIfNeeded(fileName: name, rawText: content)
                let target = appSupportDirectory.appendingPathComponent(name, isDirectory: false)
                try Data(cleanContent.utf8).write(to: target, options: .atomic)
                restoredConfigs.append(name)
            }
        }

        var restoredClip: [ClipboardEntry] = []
        var skippedClip = 0
        if options.restoreClipboard {
            let decoded = try restorePinnedClipboard(payload.pinnedClipboardItems, imageDir: resolvedClipDir)
            restoredClip = ClipboardPersistenceStore.savePinnedEntries(
                decoded.entries, appSupportDirectory: appSupportDirectory, mediaDirectory: resolvedClipDir
            )
            skippedClip = decoded.skippedCount
        }

        var restoredPlugins: [String] = []
        if options.restorePlugins {
            restoredPlugins = try restorePlugins(
                payload.plugins, in: resolvedPluginsDir, overwrite: options.overwriteExistingPlugins
            )
        }

        var restoredDataIDs: [String] = []
        var restoredExtCount = 0
        if options.restorePluginData {
            restoredDataIDs = try restorePluginDataBundles(
                payload.pluginData, in: resolvedPluginsDir, overwrite: options.overwriteExistingPlugins
            )
            restoredExtCount = try restoreExternalPluginFiles(
                payload.externalPluginFiles, in: resolvedPluginsDir,
                homeDirectory: homeDirectory, overwrite: options.overwriteExistingPlugins
            )
        }

        return BackupRestoreReport(
            mosConfig: payload.mosConfig,
            telemetryConfig: payload.telemetryConfig,
            restoredConfigFileNames: restoredConfigs,
            restoredClipboardEntries: restoredClip,
            skippedClipboardCount: skippedClip,
            restoredPluginIDs: restoredPlugins,
            restoredPluginDataIDs: restoredDataIDs,
            restoredExternalFileCount: restoredExtCount,
            restoredSecretPluginIDs: restoredSecretPlugins,
            safetySnapshotURL: safetyURL
        )
    }
}
