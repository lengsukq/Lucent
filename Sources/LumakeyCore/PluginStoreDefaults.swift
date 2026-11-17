import LumakeyFoundation
import Foundation

public enum PluginStoreDefaults {
    public static let officialDemoStoreID = "lumakey-demo-store"
    public static let officialDemoSourceURL = "https://github.com/lengsukq/Lumakey/tree/main/plugin-demo"
    public static let officialDemoRegistryURL = "https://raw.githubusercontent.com/lengsukq/Lumakey/main/plugin-demo/lumakey-registry.json"
    public static let officialDemoRawBaseURL = "https://raw.githubusercontent.com/lengsukq/Lumakey/main/plugin-demo/"

    public static func bundledDemoDirectory(
        bundle: Bundle = .main
    ) -> URL? {
        if let resDir = bundle.resourceURL?.appendingPathComponent("plugin-demo", isDirectory: true),
           FileManager.default.fileExists(atPath: resDir.appendingPathComponent(PluginStoreRegistryManifest.defaultFileName).path) {
            return resDir
        }
        return nil
    }

    public static func bundledDemoArchiveURL(
        for resolvedURL: URL,
        bundledDirectory: URL? = bundledDemoDirectory()
    ) -> URL? {
        guard let dir = bundledDirectory else { return nil }
        let rawStr = resolvedURL.absoluteString
        let relPath: String
        if rawStr.hasPrefix(officialDemoRawBaseURL) {
            relPath = String(rawStr.dropFirst(officialDemoRawBaseURL.count))
        } else if resolvedURL.isFileURL,
                  resolvedURL.path.hasPrefix(dir.standardizedFileURL.path + "/") {
            relPath = String(resolvedURL.path.dropFirst(dir.standardizedFileURL.path.count + 1))
        } else {
            return nil
        }
        guard BackupArchiveService.isSafeRelativePluginPath(relPath) else { return nil }
        let localURL = dir.appendingPathComponent(relPath, isDirectory: false).standardizedFileURL
        guard localURL.path.hasPrefix(dir.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: localURL.path) else {
            return nil
        }
        return localURL
    }

    @discardableResult
    public static func ensureDefaultDemoStoreSeeded(
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory(),
        bundledDirectory: URL? = bundledDemoDirectory()
    ) -> PluginStoreCatalogSnapshot {
        var catalog = PluginStoreService.loadCatalog(appSupportDirectory: appSupportDirectory)
        let alreadySeeded = catalog.seededDefaultStoreIDs?.contains(officialDemoStoreID) == true
        let alreadyPresent = catalog.stores.contains { $0.id == officialDemoStoreID }
        if alreadySeeded || alreadyPresent {
            return catalog
        }

        guard let demoDir = bundledDirectory else {
            return catalog
        }
        let regFile = demoDir.appendingPathComponent(PluginStoreRegistryManifest.defaultFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: regFile),
              let manifest = try? JSONDecoder().decode(PluginStoreRegistryManifest.self, from: data),
              manifest.validate().isEmpty else {
            return catalog
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let subscription = PluginStoreSubscription(
            sourceURL: officialDemoSourceURL,
            resolvedRegistryURL: officialDemoRegistryURL,
            addedAtISO8601: now,
            lastSyncedAtISO8601: manifest.updatedAt ?? now,
            manifest: manifest
        )
        catalog.stores.append(subscription)
        var seeded = catalog.seededDefaultStoreIDs ?? []
        if !seeded.contains(officialDemoStoreID) {
            seeded.append(officialDemoStoreID)
        }
        catalog.seededDefaultStoreIDs = seeded
        try? PluginStoreService.saveCatalog(catalog, appSupportDirectory: appSupportDirectory)
        return catalog
    }
}
