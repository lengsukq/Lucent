import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension BackupArchiveService {
    public static let defaultMaxPluginDataBytesPerPlugin: Int = 10 * 1024 * 1024
    public static let defaultMaxExternalFileBytes: Int = 5 * 1024 * 1024

    public static func isSafeHomeRelativeBackupPath(_ path: String) -> Bool {
        guard isSafeRelativePluginPath(path) else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return false }
        if parts.contains(where: { $0.hasPrefix(".") }) { return false }
        let lower = path.lowercased()
        let forbiddenPrefixes = [
            "library/keychains",
            "library/application support/lumakey/.vault",
            "library/cookies",
            "library/passwords"
        ]
        return !forbiddenPrefixes.contains(where: { lower == $0 || lower.hasPrefix($0 + "/") })
    }

    static func shouldSkipPluginDataRelativePath(_ relPath: String, customExcludes: [String]) -> Bool {
        let parts = relPath.split(separator: "/").map(String.init)
        guard let last = parts.last else { return true }
        if last == ".DS_Store" { return true }
        if parts.contains(where: { $0.hasPrefix(".tmp-") || $0.hasPrefix(".") || $0.lowercased() == "cache" || $0.lowercased() == "caches" }) {
            return true
        }
        let lowerLast = last.lowercased()
        if lowerLast.hasSuffix(".log") || lowerLast.hasSuffix(".sock") || lowerLast.hasSuffix(".tmp") {
            return true
        }
        for rawPattern in customExcludes {
            let pat = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pat.isEmpty else { continue }
            if pat.hasSuffix("/*") {
                let prefix = String(pat.dropLast(1))
                if relPath.hasPrefix(prefix) { return true }
            } else if pat.hasPrefix("*.") {
                let suffix = String(pat.dropFirst(1)).lowercased()
                if lowerLast.hasSuffix(suffix) { return true }
            } else if relPath == pat || relPath.hasPrefix(pat + "/") {
                return true
            }
        }
        return false
    }

    static func collectPluginDataBundles(
        in pluginsDir: URL,
        maxBytesPerPlugin: Int = defaultMaxPluginDataBytesPerPlugin
    ) -> [BackupPluginDataBundle] {
        let fm = FileManager.default
        let dataRoot = PluginDataPaths.dataRoot(forPluginsRoot: pluginsDir)
        guard let folders = try? fm.contentsOfDirectory(
            at: dataRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let manifestsByID: [String: PluginManifest] = Dictionary(
            uniqueKeysWithValues: PluginSystem.listPlugins(in: pluginsDir, includeDisabled: true, includeBuiltin: false, includeSecrets: false)
                .map { ($0.id, $0.manifest) }
        )

        var out: [BackupPluginDataBundle] = []
        for folder in folders {
            let id = folder.lastPathComponent
            guard PluginSystem.isSafePluginID(id),
                  let vals = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isDirectory == true, vals.isSymbolicLink != true else { continue }

            let customExcludes = manifestsByID[id]?.backupExclude ?? []
            let rootStd = folder.resolvingSymlinksInPath().standardizedFileURL.path
            guard let enumerator = fm.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: []
            ) else { continue }

            var files: [BackupPluginFileRecord] = []
            var accumulatedBytes = 0
            var skippedLarge = 0
            for case let fileURL as URL in enumerator {
                guard let fVals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      fVals.isSymbolicLink != true, fVals.isRegularFile == true else { continue }
                let fileStd = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard fileStd.hasPrefix(rootStd + "/") else { continue }
                let rel = String(fileStd.dropFirst(rootStd.count + 1))
                guard isSafeRelativePluginPath(rel), !shouldSkipPluginDataRelativePath(rel, customExcludes: customExcludes) else {
                    continue
                }
                let size = fVals.fileSize ?? 0
                if size > maxBytesPerPlugin || (accumulatedBytes + size) > maxBytesPerPlugin {
                    skippedLarge += 1
                    continue
                }
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                accumulatedBytes += data.count
                let perms = ((try? fm.attributesOfItem(atPath: fileStd)[.posixPermissions]) as? Int) ?? 0o644
                files.append(BackupPluginFileRecord(
                    relativePath: rel,
                    contentBase64: data.base64EncodedString(),
                    posixPermissions: perms & 0o777,
                    isExecutable: false
                ))
            }
            files.sort { $0.relativePath < $1.relativePath }
            if !files.isEmpty || skippedLarge > 0 {
                out.append(BackupPluginDataBundle(id: id, files: files, skippedLargeFileCount: skippedLarge))
            }
        }
        return out.sorted { $0.id < $1.id }
    }

    static func restorePluginDataBundles(
        _ bundles: [BackupPluginDataBundle],
        in pluginsDir: URL,
        overwrite: Bool
    ) throws -> [String] {
        let fm = FileManager.default
        var restoredIDs: [String] = []
        for bundle in bundles {
            guard let targetDir = PluginDataPaths.ensureDataDirectory(for: bundle.id, pluginsRoot: pluginsDir) else {
                continue
            }
            for file in bundle.files {
                guard let content = Data(base64Encoded: file.contentBase64) else {
                    throw BackupArchiveError.corruptedArchive("插件数据文件解码失败：\(bundle.id)/\(file.relativePath)")
                }
                let destURL = targetDir.appendingPathComponent(file.relativePath, isDirectory: false).standardizedFileURL
                if fm.fileExists(atPath: destURL.path) && !overwrite { continue }
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: destURL, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destURL.path)
            }
            if !bundle.files.isEmpty { restoredIDs.append(bundle.id) }
        }
        return restoredIDs
    }

    static func collectExternalPluginFiles(
        in pluginsDir: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        maxFileBytes: Int = defaultMaxExternalFileBytes
    ) -> [BackupExternalPathFile] {
        let homeStd = homeDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let plugins = PluginSystem.listPlugins(in: pluginsDir, includeDisabled: true, includeBuiltin: false, includeSecrets: false)
        var records: [BackupExternalPathFile] = []

        for plugin in plugins where PluginSystem.isSafePluginID(plugin.id) {
            let backupFields = (plugin.manifest.config ?? []).filter { $0.type == .path && $0.includeInBackup == true }
            for field in backupFields {
                guard let rawVal = plugin.userConfig[field.key] ?? field.defaultValue else { continue }
                let trimmed = rawVal.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let expandedURL: URL
                if trimmed == "~" {
                    continue
                } else if trimmed.hasPrefix("~/") {
                    expandedURL = homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2)), isDirectory: false)
                } else {
                    expandedURL = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: false)
                }
                guard let vals = try? expandedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      vals.isRegularFile == true, vals.isSymbolicLink != true,
                      let size = vals.fileSize, size >= 0, size <= maxFileBytes else { continue }

                let resolvedPath = expandedURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolvedPath.hasPrefix(homeStd + "/") else { continue }
                let relHome = String(resolvedPath.dropFirst(homeStd.count + 1))
                guard isSafeHomeRelativeBackupPath(relHome), let data = try? Data(contentsOf: expandedURL) else { continue }
                records.append(BackupExternalPathFile(
                    pluginID: plugin.id,
                    configKey: field.key,
                    homeRelativePath: relHome,
                    contentBase64: data.base64EncodedString()
                ))
            }
        }
        return records.sorted { ($0.pluginID, $0.configKey) < ($1.pluginID, $1.configKey) }
    }

    static func restoreExternalPluginFiles(
        _ records: [BackupExternalPathFile],
        in pluginsDir: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        overwrite: Bool
    ) throws -> Int {
        guard !records.isEmpty else { return 0 }
        let fm = FileManager.default
        let homeStd = homeDirectory.standardizedFileURL.path
        var snap = PluginSystem.loadStateSnapshot(in: pluginsDir)
        var snapMutated = false
        var count = 0

        for rec in records {
            guard let content = Data(base64Encoded: rec.contentBase64) else {
                throw BackupArchiveError.corruptedArchive("外部路径文件解码失败：\(rec.homeRelativePath)")
            }
            let targetURL = homeDirectory.appendingPathComponent(rec.homeRelativePath, isDirectory: false).standardizedFileURL
            guard targetURL.path.hasPrefix(homeStd + "/") else {
                throw BackupArchiveError.unsafePath(rec.homeRelativePath)
            }
            if !fm.fileExists(atPath: targetURL.path) || overwrite {
                try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: targetURL, options: .atomic)
                count += 1
            }
            let portablePath = "~/\(rec.homeRelativePath)"
            if var inst = snap.plugins[rec.pluginID], let existing = inst.configValues[rec.configKey],
               existing.hasPrefix("/Users/"), existing != targetURL.path {
                inst.configValues[rec.configKey] = portablePath
                snap.plugins[rec.pluginID] = inst
                snapMutated = true
            }
        }
        if snapMutated {
            try? PluginSystem.saveStateSnapshot(snap, in: pluginsDir)
        }
        return count
    }

    static func writePreRestoreSafetySnapshot(
        appSupportDirectory: URL,
        pluginsDirectory: URL
    ) -> URL? {
        let fm = FileManager.default
        let mosExists = fm.fileExists(atPath: appSupportDirectory.appendingPathComponent("mos-config.json").path)
        let stateExists = fm.fileExists(atPath: appSupportDirectory.appendingPathComponent("plugin-state.json").path)
        guard mosExists || stateExists else { return nil }
        guard let snapData = try? exportBackupData(
            appSupportDirectory: appSupportDirectory,
            pluginsDirectory: pluginsDirectory,
            compress: true
        ) else { return nil }
        let backupDir = appSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let targetURL = backupDir.appendingPathComponent("pre-restore-latest.\(BackupEnvelope.fileExtension)")
        do {
            try snapData.write(to: targetURL, options: .atomic)
            return targetURL
        } catch {
            return nil
        }
    }
}
