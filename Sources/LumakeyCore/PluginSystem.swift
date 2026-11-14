import Foundation

public enum PluginSystem {
    static let stateLock = NSLock()

    public static func defaultPluginsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Lumakey", isDirectory: true).appendingPathComponent("Plugins", isDirectory: true)
    }

    public static func stateFileURL(for rootDir: URL = defaultPluginsDirectory()) -> URL {
        let standardized = rootDir.standardizedFileURL
        if standardized.lastPathComponent == "Plugins" {
            return standardized.deletingLastPathComponent().appendingPathComponent("plugin-state.json")
        }
        return standardized.appendingPathComponent("plugin-state.json")
    }

    public static func isSafePluginID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
    }

    public static func resolvedConfig(for manifest: PluginManifest, stored: [String: String]) -> [String: String] {
        var merged: [String: String] = [:]
        for field in manifest.config ?? [] {
            if let def = field.defaultValue { merged[field.key] = def }
        }
        for (k, v) in stored { merged[k] = v }
        return merged
    }

    public static func listPlugins(
        in rootDir: URL = defaultPluginsDirectory(),
        includeDisabled: Bool = true,
        includeBuiltin: Bool = false
    ) -> [PluginDescriptor] {
        var results: [PluginDescriptor] = []
        if includeBuiltin {
            let builtins = PluginBuiltinRegistry.descriptors()
            results.append(contentsOf: includeDisabled ? builtins : builtins.filter(\.isEnabled))
        }
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return results }

        let snapshot = loadStateSnapshot(in: rootDir)
        let externals = folders.compactMap { folder -> PluginDescriptor? in
            let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let desc = loadPlugin(at: folder, snapshot: snapshot)
            return (!includeDisabled && !desc.isEnabled) ? nil : desc
        }.sorted { $0.id < $1.id }
        return results + externals
    }

    public static func loadPlugin(at directoryURL: URL, in rootDir: URL? = nil) -> PluginDescriptor {
        let resolvedRoot = rootDir ?? directoryURL.deletingLastPathComponent()
        return loadPlugin(at: directoryURL, snapshot: loadStateSnapshot(in: resolvedRoot))
    }

    static func loadPlugin(at directoryURL: URL, snapshot: PluginStateSnapshot) -> PluginDescriptor {
        let folderName = directoryURL.lastPathComponent
        let manifestURL = directoryURL.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else {
            let fallback = PluginManifest(id: folderName, name: folderName, version: "0.0.0", description: "无效清单", mode: .script, keywords: [], entry: "")
            return PluginDescriptor(id: folderName, directoryURL: directoryURL, manifest: fallback, validationIssues: ["缺少或无法解析 plugin.json"])
        }
        let issues = validate(manifest: manifest, in: directoryURL)
        let inst = snapshot.plugins[manifest.id] ?? PluginInstanceState()
        let config = resolvedConfig(for: manifest, stored: inst.configValues)
        let granted = Set(inst.grantedCapabilities.compactMap { PluginCapability(rawValue: $0) })
        return PluginDescriptor(
            id: manifest.id, directoryURL: directoryURL, manifest: manifest,
            validationIssues: issues, isEnabled: inst.isEnabled, userConfig: config,
            kind: .external, grantedCapabilities: granted
        )
    }

    public static func validate(manifest: PluginManifest, in directoryURL: URL) -> [String] {
        var issues: [String] = []
        if !isSafePluginID(manifest.id) { issues.append("id 仅允许小写字母、数字与连字符") }
        if PluginBuiltinRegistry.isBuiltin(id: manifest.id) { issues.append("id '\(manifest.id)' 为内置插件保留前缀") }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("name 不能为空") }
        if manifest.keywords.isEmpty { issues.append("keywords 至少包含一个触发词") }
        let entryURL = directoryURL.appendingPathComponent(manifest.entry).standardizedFileURL
        let rootPath = directoryURL.standardizedFileURL.path
        if manifest.entry.isEmpty || !entryURL.path.hasPrefix(rootPath + "/") {
            issues.append("entry 路径不合法或试图逃逸插件目录")
        } else if !FileManager.default.fileExists(atPath: entryURL.path) {
            issues.append("入口文件不存在：\(manifest.entry)")
        } else if !FileManager.default.isExecutableFile(atPath: entryURL.path) {
            issues.append("插件入口缺少可执行权限：\(manifest.entry)")
        }
        for field in manifest.config ?? [] {
            if field.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("config 存在空的 key 字段")
            }
            if field.type == .select && (field.options ?? []).isEmpty {
                issues.append("config 下拉项 '\(field.key)' 缺少 options 候选列表")
            }
        }
        if manifest.capabilities == nil {
            issues.append("注册时必须显式声明 capabilities 权限列表（无需宿主权限请写 []）")
        }
        for rawCap in manifest.capabilities ?? [] where PluginCapability(rawValue: rawCap) == nil {
            issues.append("未知 capability 声明：'\(rawCap)'")
        }
        return issues
    }
}
