import Foundation

extension BackupArchiveService {
    static func collectScriptFiles(in scriptsDir: URL) -> [BackupPluginFileRecord] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: scriptsDir.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let rootStd = scriptsDir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: scriptsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }

        var records: [BackupPluginFileRecord] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == ".DS_Store" || fileURL.lastPathComponent.hasPrefix(".") { continue }
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  vals.isSymbolicLink != true, vals.isRegularFile == true else { continue }
            let fileStd = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard fileStd.hasPrefix(rootStd + "/") else { continue }
            let rel = String(fileStd.dropFirst(rootStd.count + 1))
            guard isSafeRelativePluginPath(rel),
                  let data = try? Data(contentsOf: fileURL),
                  data.count <= 512 * 1024 else { continue }
            let perms = ((try? fm.attributesOfItem(atPath: fileStd)[.posixPermissions]) as? Int) ?? 0o755
            let exec = (perms & 0o111) != 0 || fm.isExecutableFile(atPath: fileStd)
            records.append(BackupPluginFileRecord(
                relativePath: rel,
                contentBase64: data.base64EncodedString(),
                posixPermissions: perms & 0o777,
                isExecutable: exec
            ))
        }
        return records.sorted { $0.relativePath < $1.relativePath }
    }

    static func validateScriptFiles(_ files: [BackupPluginFileRecord], scriptsDirectory: URL) throws {
        let rootStd = scriptsDirectory.standardizedFileURL.path
        for file in files {
            guard isSafeRelativePluginPath(file.relativePath) else {
                throw BackupArchiveError.unsafePath("Scripts/\(file.relativePath)")
            }
            let dest = scriptsDirectory.appendingPathComponent(file.relativePath, isDirectory: false).standardizedFileURL
            guard dest.path.hasPrefix(rootStd + "/") else {
                throw BackupArchiveError.unsafePath("Scripts/\(file.relativePath)")
            }
            guard Data(base64Encoded: file.contentBase64) != nil else {
                throw BackupArchiveError.corruptedArchive("脚本归档文件 Scripts/\(file.relativePath) Base64 无效")
            }
        }
    }

    static func restoreScriptFiles(_ files: [BackupPluginFileRecord], in scriptsDir: URL, overwrite: Bool) throws {
        guard !files.isEmpty else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        for file in files {
            let destURL = scriptsDir.appendingPathComponent(file.relativePath, isDirectory: false).standardizedFileURL
            if fm.fileExists(atPath: destURL.path) && !overwrite { continue }
            guard let content = Data(base64Encoded: file.contentBase64) else {
                throw BackupArchiveError.corruptedArchive("脚本文件解码失败：Scripts/\(file.relativePath)")
            }
            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: destURL, options: .atomic)
            let isSvg = destURL.pathExtension.lowercased() == "svg" || destURL.pathExtension.lowercased() == "png"
            let mode = (!isSvg && (file.isExecutable || (file.posixPermissions & 0o111) != 0)) ? 0o755 : 0o644
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: destURL.path)
        }
    }
}
