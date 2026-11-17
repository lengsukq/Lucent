import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import CryptoKit
import Foundation

public enum PluginStoreService {
    public static func defaultCatalogFileURL(
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent(PluginStoreCatalogSnapshot.fileName, isDirectory: false)
    }

    public static func loadCatalog(
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) -> PluginStoreCatalogSnapshot {
        let url = defaultCatalogFileURL(appSupportDirectory: appSupportDirectory)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PluginStoreCatalogSnapshot.self, from: data)
        else { return PluginStoreCatalogSnapshot() }
        return decoded
    }

    public static func saveCatalog(
        _ snapshot: PluginStoreCatalogSnapshot,
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: defaultCatalogFileURL(appSupportDirectory: appSupportDirectory), options: .atomic)
    }

    @discardableResult
    public static func upsertStore(
        _ subscription: PluginStoreSubscription,
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) throws -> PluginStoreCatalogSnapshot {
        var catalog = loadCatalog(appSupportDirectory: appSupportDirectory)
        if let idx = catalog.stores.firstIndex(where: { $0.id == subscription.id || $0.resolvedRegistryURL == subscription.resolvedRegistryURL }) {
            let preservedAddedAt = catalog.stores[idx].addedAtISO8601
            catalog.stores[idx] = PluginStoreSubscription(
                sourceURL: subscription.sourceURL,
                resolvedRegistryURL: subscription.resolvedRegistryURL,
                addedAtISO8601: preservedAddedAt,
                lastSyncedAtISO8601: subscription.lastSyncedAtISO8601,
                manifest: subscription.manifest
            )
        } else {
            catalog.stores.append(subscription)
        }
        try saveCatalog(catalog, appSupportDirectory: appSupportDirectory)
        return catalog
    }

    @discardableResult
    public static func removeStore(
        storeID: String,
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory()
    ) throws -> PluginStoreCatalogSnapshot {
        var catalog = loadCatalog(appSupportDirectory: appSupportDirectory)
        catalog.stores.removeAll { $0.id == storeID }
        try saveCatalog(catalog, appSupportDirectory: appSupportDirectory)
        return catalog
    }

    @discardableResult
    public static func refreshStore(
        storeID: String,
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory(),
        fetcher: PluginURLFetcher = PluginStoreSniffer.defaultFetcher
    ) async throws -> PluginStoreSubscription {
        let catalog = loadCatalog(appSupportDirectory: appSupportDirectory)
        guard let existing = catalog.stores.first(where: { $0.id == storeID }) else {
            throw LumakeyError.pluginInvalid("未找到商店订阅源：\(storeID)")
        }
        let resolved: DiscoveredPluginSource
        var usedLocalFallback = false
        do {
            resolved = try await PluginStoreSniffer.resolveSource(from: existing.resolvedRegistryURL, fetcher: fetcher)
        } catch {
            if storeID == PluginStoreDefaults.officialDemoStoreID,
               let demoDir = PluginStoreDefaults.bundledDemoDirectory() {
                resolved = try await PluginStoreSniffer.resolveSource(from: demoDir.path, fetcher: fetcher)
                usedLocalFallback = true
            } else {
                throw error
            }
        }
        guard case .storeRegistry(var updated) = resolved else {
            throw LumakeyError.pluginInvalid("刷新失败：远端地址不再返回有效的商店清单")
        }
        updated = PluginStoreSubscription(
            sourceURL: existing.sourceURL,
            resolvedRegistryURL: usedLocalFallback ? existing.resolvedRegistryURL : updated.resolvedRegistryURL,
            addedAtISO8601: existing.addedAtISO8601,
            lastSyncedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            manifest: updated.manifest
        )
        try upsertStore(updated, appSupportDirectory: appSupportDirectory)
        return updated
    }

    public static func installState(
        for item: PluginStoreItem,
        installedPlugins: [PluginDescriptor]
    ) -> PluginStoreInstallState {
        guard let existing = installedPlugins.first(where: { !$0.isBuiltin && $0.id == item.id }) else {
            return .notInstalled
        }
        let installedVersion = existing.manifest.version
        if PluginVersionComparator.compare(installedVersion, item.version) == .orderedAscending {
            return .updateAvailable(installed: installedVersion, available: item.version)
        }
        return .installedUpToDate(version: installedVersion)
    }

    // MARK: - Safe Archive Unpacking & Installation

    public static func computeSHA256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func unpackArchiveSafely(
        archiveData: Data,
        expectedSHA256: String?
    ) throws -> (stagingRoot: URL, pluginDir: URL, computedSHA256: String) {
        let computed = computeSHA256Hex(archiveData)
        if let expected = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty {
            guard computed.lowercased() == expected.lowercased() else {
                throw LumakeyError.pluginInvalid("插件包 SHA-256 校验不匹配（期望 \(expected.prefix(12))…，实际 \(computed.prefix(12))…）")
            }
        }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("lumakey-pkg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let zipFile = stagingRoot.appendingPathComponent("archive.zip")
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try archiveData.write(to: zipFile, options: .atomic)

        let res = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zipFile.path, extractDir.path],
            timeoutSeconds: 12.0
        )
        guard res.exitCode == 0 else {
            try? fm.removeItem(at: stagingRoot)
            throw LumakeyError.pluginInvalid("解压插件归档失败：\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        do {
            try sanitizeAndAuditExtractedTree(at: extractDir)
            let pluginDir = try locatePluginRoot(inside: extractDir)
            return (stagingRoot, pluginDir, computed)
        } catch {
            try? fm.removeItem(at: stagingRoot)
            throw error
        }
    }

    private static func sanitizeAndAuditExtractedTree(at rootDir: URL) throws {
        let fm = FileManager.default
        let macosxMeta = rootDir.appendingPathComponent("__MACOSX", isDirectory: true)
        if fm.fileExists(atPath: macosxMeta.path) { try? fm.removeItem(at: macosxMeta) }

        let rootPath = rootDir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: rootDir,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            options: []
        ) else { return }

        var toRemove: [URL] = []
        for case let itemURL as URL in enumerator {
            if itemURL.lastPathComponent == ".DS_Store" {
                toRemove.append(itemURL)
                continue
            }
            let vals = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if vals.isSymbolicLink == true {
                throw LumakeyError.pluginInvalid("拒绝安装包含符号链接的插件包：\(itemURL.lastPathComponent)")
            }
            let resolved = itemURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootPath + "/") else {
                throw LumakeyError.pluginInvalid("检测到插件压缩包路径越界逃逸")
            }
            let rel = String(resolved.dropFirst(rootPath.count + 1))
            guard BackupArchiveService.isSafeRelativePluginPath(rel) else {
                throw LumakeyError.pluginInvalid("插件压缩包内存在非法相对路径：\(rel)")
            }
        }
        for junk in toRemove { try? fm.removeItem(at: junk) }
    }

    private static func locatePluginRoot(inside extractDir: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: extractDir.appendingPathComponent("plugin.json").path) {
            return extractDir
        }
        let children = (try? fm.contentsOfDirectory(
            at: extractDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let subdirs = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if subdirs.count == 1, fm.fileExists(atPath: subdirs[0].appendingPathComponent("plugin.json").path) {
            return subdirs[0]
        }
        throw LumakeyError.pluginInvalid("插件压缩包根目录或顶层文件夹中未找到 plugin.json")
    }

    @discardableResult
    public static func installStoreItem(
        _ item: PluginStoreItem,
        from store: PluginStoreSubscription?,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory(),
        fetcher: PluginURLFetcher = PluginStoreSniffer.defaultFetcher
    ) async throws -> PluginDescriptor {
        let resolvedURL: URL
        if let baseStr = store?.resolvedRegistryURL, let baseURL = URL(string: baseStr),
           let rel = URL(string: item.downloadURL, relativeTo: baseURL)?.absoluteURL {
            resolvedURL = rel
        } else {
            resolvedURL = try PluginStoreSniffer.normalizeInputURL(item.downloadURL)
        }
        try PluginStoreSniffer.validateSafeScheme(resolvedURL)
        let archiveData: Data
        do {
            let (fetched, _) = try await fetcher(resolvedURL)
            archiveData = fetched
        } catch {
            if let fallbackURL = PluginStoreDefaults.bundledDemoArchiveURL(for: resolvedURL),
               let localData = try? Data(contentsOf: fallbackURL) {
                archiveData = localData
            } else {
                throw error
            }
        }
        let unpacked = try unpackArchiveSafely(archiveData: archiveData, expectedSHA256: item.sha256)
        defer { try? FileManager.default.removeItem(at: unpacked.stagingRoot) }

        let candidate = PluginSystem.loadPlugin(at: unpacked.pluginDir, snapshot: PluginStateSnapshot(), in: pluginsRoot, includeSecrets: false)
        guard candidate.isValid else {
            throw LumakeyError.pluginInvalid("插件包校验未通过：\(candidate.validationIssues.joined(separator: "；"))")
        }
        guard candidate.manifest.id == item.id else {
            throw LumakeyError.pluginInvalid("插件包内 id '\(candidate.manifest.id)' 与商店索引声明 '\(item.id)' 不一致")
        }
        let advertisedCaps = Set(item.declaredCapabilities)
        let actualCaps = Set(candidate.declaredCapabilities)
        if !actualCaps.isSubset(of: advertisedCaps) {
            let extra = actualCaps.subtracting(advertisedCaps).map(\.rawValue).sorted().joined(separator: ", ")
            throw LumakeyError.pluginInvalid("安全拦截：插件包实际申请了商店索引未声明的宿主权限 [\(extra)]")
        }
        let advertisedScopes = Set(item.declaredResourceScopes)
        let actualScopes = Set(candidate.declaredResourceScopes)
        if !actualScopes.isSubset(of: advertisedScopes) {
            let extra = actualScopes.subtracting(advertisedScopes).map(\.rawValue).sorted().joined(separator: ", ")
            throw LumakeyError.pluginInvalid("安全拦截：插件包实际申请了商店索引未声明的外部资源范围 [\(extra)]")
        }
        return try PluginSystem.importPluginDirectory(from: unpacked.pluginDir, in: pluginsRoot, overwrite: true)
    }

    @discardableResult
    public static func installSingleCandidate(
        _ candidate: SinglePluginCandidate,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) throws -> PluginDescriptor {
        defer { candidate.cleanupStagingIfNeeded() }
        return try PluginSystem.importPluginDirectory(from: candidate.stagingBundleDirectory, in: pluginsRoot, overwrite: true)
    }
}
