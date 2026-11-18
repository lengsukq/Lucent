import LucentFoundation
import Foundation

public struct PackagedPluginArtifact: Sendable, Hashable {
    public let archiveURL: URL
    public let sha256: String
    public let sizeBytes: Int
    public let registryItem: PluginStoreItem
    public let registryFileURL: URL?

    public init(archiveURL: URL, sha256: String, sizeBytes: Int, registryItem: PluginStoreItem, registryFileURL: URL?) {
        self.archiveURL = archiveURL
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.registryItem = registryItem
        self.registryFileURL = registryFileURL
    }
}

public enum PluginStorePackager {
    public static func packagePluginForStore(
        pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory(),
        outputDirectory: URL,
        downloadURL: String? = nil,
        homepage: String? = nil,
        minAppVersion: String? = nil,
        changelog: String? = nil,
        updateRegistryAt registryFileURL: URL? = nil,
        storeId: String = "custom-store",
        storeName: String = "Custom Lucent Store",
        maintainer: String? = nil
    ) throws -> PackagedPluginArtifact {
        guard PluginSystem.isSafePluginID(pluginID), !PluginBuiltinRegistry.isBuiltin(id: pluginID) else {
            throw LucentError.pluginInvalid("仅支持打包合法的外部扩展插件（当前 id: '\(pluginID)'）")
        }
        let sourceDir = pluginsRoot.appendingPathComponent(pluginID, isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: sourceDir.path) else {
            throw LucentError.pluginInvalid("未找到插件目录：\(pluginID)")
        }
        let loaded = PluginSystem.loadPlugin(at: sourceDir, snapshot: PluginStateSnapshot(), in: pluginsRoot, includeSecrets: false)
        guard loaded.isValid else {
            throw LucentError.pluginInvalid("打包前校验未通过：\(loaded.validationIssues.joined(separator: "；"))")
        }

        let fm = FileManager.default
        let tempStage = fm.temporaryDirectory.appendingPathComponent("lucent-pack-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempStage) }
        let cleanBundleDir = tempStage.appendingPathComponent(pluginID, isDirectory: true)
        try copyCleanPluginBundle(from: sourceDir, to: cleanBundleDir)

        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let archiveURL = outputDirectory.appendingPathComponent("\(pluginID).zip", isDirectory: false).standardizedFileURL
        if fm.fileExists(atPath: archiveURL.path) {
            try fm.removeItem(at: archiveURL)
        }

        let res = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", cleanBundleDir.path, archiveURL.path],
            timeoutSeconds: 15.0
        )
        guard res.exitCode == 0, let archiveData = try? Data(contentsOf: archiveURL) else {
            throw LucentError.pluginInvalid("生成 .zip 归档失败：\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let sha256 = PluginStoreService.computeSHA256Hex(archiveData)
        let m = loaded.manifest
        let effectiveDownloadURL = (downloadURL?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "./\(pluginID).zip"
        let effectiveMinApp = (minAppVersion?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? m.minAppVersion

        let item = PluginStoreItem(
            id: m.id,
            name: m.name,
            version: m.version,
            minAppVersion: effectiveMinApp,
            changelog: changelog,
            description: m.description,
            author: m.author,
            icon: (m.icon.map { PluginIconResolver.looksLikeRelativeFilePath($0) ? nil : $0 }) ?? nil,
            accentColor: m.accentColor,
            categoryTag: m.categoryTag,
            mode: m.mode,
            keywords: m.keywords,
            capabilities: m.declaredCapabilities.map(\.rawValue),
            resourceScopes: m.declaredResourceScopes.map(\.rawValue),
            accepts: m.accepts,
            homepage: homepage,
            downloadURL: effectiveDownloadURL,
            sha256: sha256,
            sizeBytes: archiveData.count,
            locales: m.locales
        )

        if let registryFileURL {
            try upsertItemInRegistryFile(
                item: item,
                at: registryFileURL,
                storeId: storeId,
                storeName: storeName,
                maintainer: maintainer ?? m.author,
                homepage: homepage
            )
        }

        return PackagedPluginArtifact(
            archiveURL: archiveURL,
            sha256: sha256,
            sizeBytes: archiveData.count,
            registryItem: item,
            registryFileURL: registryFileURL
        )
    }

    public static func upsertItemInRegistryFile(
        item: PluginStoreItem,
        at registryFileURL: URL,
        storeId: String,
        storeName: String,
        maintainer: String? = nil,
        homepage: String? = nil
    ) throws {
        var existingItems: [PluginStoreItem] = []
        var resolvedStoreID = storeId
        var resolvedStoreName = storeName
        var resolvedDesc: String? = nil
        var resolvedMaintainer = maintainer
        var resolvedHomepage = homepage

        if FileManager.default.fileExists(atPath: registryFileURL.path),
           let data = try? Data(contentsOf: registryFileURL),
           let current = try? JSONDecoder().decode(PluginStoreRegistryManifest.self, from: data) {
            existingItems = current.plugins
            resolvedStoreID = current.storeId
            resolvedStoreName = current.storeName
            resolvedDesc = current.description
            resolvedMaintainer = maintainer ?? current.maintainer
            resolvedHomepage = homepage ?? current.homepage
        }

        if let idx = existingItems.firstIndex(where: { $0.id == item.id }) {
            existingItems[idx] = item
        } else {
            existingItems.append(item)
        }
        existingItems.sort { $0.id < $1.id }

        let nextManifest = PluginStoreRegistryManifest(
            schemaVersion: PluginStoreRegistryManifest.currentSchemaVersion,
            storeId: resolvedStoreID,
            storeName: resolvedStoreName,
            description: resolvedDesc,
            maintainer: resolvedMaintainer,
            homepage: resolvedHomepage,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            plugins: existingItems
        )
        let issues = nextManifest.validate()
        guard issues.isEmpty else {
            throw LucentError.pluginInvalid("生成商店清单校验失败：\(issues.joined(separator: "；"))")
        }

        try FileManager.default.createDirectory(at: registryFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(nextManifest).write(to: registryFileURL, options: .atomic)
    }

    private static func copyCleanPluginBundle(from sourceDir: URL, to destDir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let rootStd = sourceDir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            let vals = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if vals.isSymbolicLink == true {
                throw LucentError.pluginInvalid("插件目录内不允许包含符号链接：\(fileURL.lastPathComponent)")
            }
            guard vals.isRegularFile == true else { continue }
            let fileStd = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard fileStd.hasPrefix(rootStd + "/") else { continue }
            let rel = String(fileStd.dropFirst(rootStd.count + 1))
            guard BackupArchiveService.isSafeRelativePluginPath(rel) else { continue }

            let outFile = destDir.appendingPathComponent(rel, isDirectory: false)
            try fm.createDirectory(at: outFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: fileURL, to: outFile)
            let perms = ((try? fm.attributesOfItem(atPath: fileStd)[.posixPermissions]) as? Int) ?? 0o644
            let mode = (perms & 0o111) != 0 ? 0o755 : 0o644
            try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: outFile.path)
        }
    }
}
