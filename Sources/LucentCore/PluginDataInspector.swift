import Foundation

public struct PluginDataStatus: Sendable, Hashable, Equatable {
    public let dataDirectoryURL: URL?
    public let dataDirectoryExists: Bool
    public let cacheBytes: Int64
    public let cacheFileCount: Int
    public let searchIndexEntryCount: Int
    public let searchIndexUpdatedAt: Date?
    public let missingRequiredSecretKeys: [String]
    public let configuredSecretKeys: [String]
    public let needsAutoRefresh: Bool
    public let runtimeStatus: PluginRuntimeStatus?
}

public enum PluginDataInspector {
    public static let statusFileName = "status.json"

    public static func statusFileURL(for pluginID: String, pluginsRoot: URL) -> URL? {
        PluginDataPaths.dataDirectory(for: pluginID, pluginsRoot: pluginsRoot)?
            .appendingPathComponent(statusFileName, isDirectory: false)
    }

    public static func readRuntimeStatus(
        for pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) -> PluginRuntimeStatus? {
        guard let url = statusFileURL(for: pluginID, pluginsRoot: pluginsRoot),
              let data = try? Data(contentsOf: url),
              data.count <= 16_384,
              let decoded = try? JSONDecoder().decode(PluginRuntimeStatus.self, from: data),
              !decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return decoded
    }

    public static func saveRuntimeStatus(
        _ status: PluginRuntimeStatus,
        for pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) {
        guard let dir = PluginDataPaths.ensureDataDirectory(for: pluginID, pluginsRoot: pluginsRoot) else { return }
        let url = dir.appendingPathComponent(statusFileName, isDirectory: false)
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func inspect(
        _ plugin: PluginDescriptor,
        in pluginsRoot: URL? = nil,
        now: Date = Date()
    ) -> PluginDataStatus {
        let resolvedRoot = pluginsRoot ?? plugin.directoryURL.deletingLastPathComponent()
        let dataDir = plugin.isBuiltin ? nil : PluginDataPaths.dataDirectory(for: plugin.id, pluginsRoot: resolvedRoot)
        let fm = FileManager.default
        var totalBytes: Int64 = 0
        var fileCount = 0
        var dirExists = false

        if let dataDir, fm.fileExists(atPath: dataDir.path) {
            dirExists = true
            if let enumerator = fm.enumerator(at: dataDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
                for case let url as URL in enumerator {
                    let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if vals?.isRegularFile == true {
                        fileCount += 1
                        totalBytes += Int64(vals?.fileSize ?? 0)
                    }
                }
            }
        }

        var idxCount = 0
        var idxMtime: Date? = nil
        if !plugin.isBuiltin, let idxURL = PluginSearchIndex.indexFileURL(for: plugin, in: resolvedRoot) {
            idxMtime = (try? fm.attributesOfItem(atPath: idxURL.path)[.modificationDate]) as? Date
            idxCount = PluginSearchIndex.loadEntries(for: [plugin], in: resolvedRoot).count
        }

        let secretFields = (plugin.manifest.config ?? []).filter { $0.type == .secret }
        var configuredSecrets: [String] = []
        var missingRequired: [String] = []
        let kcService = PluginDataPaths.keychainService(forPluginsRoot: resolvedRoot)
        let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: resolvedRoot)
        for field in secretFields {
            let val = plugin.userConfig[field.key]
                ?? (try? PluginKeychainStore.loadSecret(pluginID: plugin.id, fieldKey: field.key, service: kcService, customVaultURL: scopedVault))
            if let val, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                configuredSecrets.append(field.key)
            } else if field.required == true {
                missingRequired.append(field.key)
            }
        }

        var needsRefresh = false
        if !plugin.isBuiltin, plugin.isEnabled, plugin.isValid, missingRequired.isEmpty,
           let interval = plugin.manifest.refreshIntervalSeconds, interval > 0 {
            if let idxMtime {
                needsRefresh = now.timeIntervalSince(idxMtime) >= Double(interval)
            } else {
                needsRefresh = true
            }
        }

        let rt = plugin.isBuiltin ? nil : readRuntimeStatus(for: plugin.id, in: resolvedRoot)
        return PluginDataStatus(
            dataDirectoryURL: dataDir,
            dataDirectoryExists: dirExists,
            cacheBytes: totalBytes,
            cacheFileCount: fileCount,
            searchIndexEntryCount: idxCount,
            searchIndexUpdatedAt: idxMtime,
            missingRequiredSecretKeys: missingRequired,
            configuredSecretKeys: configuredSecrets,
            needsAutoRefresh: needsRefresh,
            runtimeStatus: rt
        )
    }

    public static func clearPluginData(
        for pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory(),
        preserveSearchIndex: Bool = false
    ) {
        guard let dir = PluginDataPaths.dataDirectory(for: pluginID, pluginsRoot: pluginsRoot),
              FileManager.default.fileExists(atPath: dir.path) else { return }
        if !preserveSearchIndex {
            PluginDataPaths.removeDataDirectory(for: pluginID, pluginsRoot: pluginsRoot)
            return
        }
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items where item.lastPathComponent != PluginSearchIndex.defaultIndexFileName {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
