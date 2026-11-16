import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Darwin
import Foundation

public enum PluginDataPaths {
    public static func dataRoot(forPluginsRoot pluginsRoot: URL) -> URL {
        let standardized = pluginsRoot.standardizedFileURL
        if standardized.lastPathComponent == "Plugins" {
            return standardized.deletingLastPathComponent().appendingPathComponent("PluginData", isDirectory: true)
        }
        return standardized.appendingPathComponent(".lumakey-plugin-data", isDirectory: true)
    }

    public static func keychainService(forPluginsRoot pluginsRoot: URL) -> String {
        let defaultPath = PluginSystem.defaultPluginsDirectory().standardizedFileURL.path
        let currentPath = pluginsRoot.standardizedFileURL.path
        if currentPath == defaultPath {
            return PluginKeychainStore.defaultService
        }
        var hash: UInt64 = 14695981039346656037
        for byte in currentPath.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "\(PluginKeychainStore.defaultService).sandbox.\(String(hash, radix: 16))"
    }

    public static func scopedVaultFileURL(forPluginsRoot pluginsRoot: URL) -> URL? {
        let defaultPath = PluginSystem.defaultPluginsDirectory().standardizedFileURL.path
        let standardized = pluginsRoot.standardizedFileURL
        if standardized.path == defaultPath {
            return nil
        }
        let baseDir = standardized.lastPathComponent == "Plugins"
            ? standardized.deletingLastPathComponent()
            : standardized
        return LocalSecretVault.defaultVaultFileURL(in: baseDir)
    }

    public static func dataDirectory(for pluginID: String, pluginsRoot: URL) -> URL? {
        guard PluginSystem.isSafePluginID(pluginID) else { return nil }
        return dataRoot(forPluginsRoot: pluginsRoot).appendingPathComponent(pluginID, isDirectory: true)
    }

    public static func searchIndexURL(for pluginID: String, pluginsRoot: URL) -> URL? {
        dataDirectory(for: pluginID, pluginsRoot: pluginsRoot)?
            .appendingPathComponent(PluginSearchIndex.defaultIndexFileName, isDirectory: false)
    }

    public static func ensureDataDirectory(for pluginID: String, pluginsRoot: URL) -> URL? {
        guard let dir = dataDirectory(for: pluginID, pluginsRoot: pluginsRoot) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func ensureIsolatedTmpDirectory(for pluginID: String, pluginsRoot: URL) -> URL {
        let base = ensureDataDirectory(for: pluginID, pluginsRoot: pluginsRoot)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-plug-\(getuid())", isDirectory: true)
        let tmp = base.appendingPathComponent(".tmp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        ensurePrivateDirectory(tmp)
        return tmp
    }

    public static func removeDataDirectory(for pluginID: String, pluginsRoot: URL) {
        guard let dir = dataDirectory(for: pluginID, pluginsRoot: pluginsRoot),
              FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Per-user 0700 directory guaranteed to keep sun_path safely below macOS's 104-byte sockaddr_un limit.
    public static func runtimeSocketDirectory() -> URL {
        let uid = getuid()
        let baseTmp = FileManager.default.temporaryDirectory
        let preferred = baseTmp.appendingPathComponent("lk-\(uid)", isDirectory: true)
        let candidate = preferred.path.utf8.count <= 78
            ? preferred
            : URL(fileURLWithPath: "/tmp/lk-u\(uid)", isDirectory: true)
        ensurePrivateDirectory(candidate)
        return candidate
    }

    public static func cleanupStaleSocketFiles(in sockDir: URL = runtimeSocketDirectory()) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: sockDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        let now = Date()
        for url in items where url.pathExtension == "sock" {
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "-")
            if parts.count >= 3, parts[0] == "b", let ownerPID = Int32(parts[1]), ownerPID > 1 {
                if Darwin.kill(ownerPID, 0) != 0 && errno == ESRCH {
                    try? fm.removeItem(at: url)
                }
            } else if name.hasPrefix("b-"),
                      let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let mtime = vals.contentModificationDate,
                      now.timeIntervalSince(mtime) > 3600 {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func ensurePrivateDirectory(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
