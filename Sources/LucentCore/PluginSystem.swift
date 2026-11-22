import LucentFoundation
import Foundation

public enum PluginSystem {
    static let stateLock = NSLock()
    public static let fallbackHostAppVersion = "0.9.9.4"

    public static var currentHostAppVersion: String {
        if let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               PluginVersionComparator.compare(trimmed, fallbackHostAppVersion) != .orderedAscending {
                return trimmed
            }
        }
        return fallbackHostAppVersion
    }

    public static func defaultPluginsDirectory() -> URL {
        LucentAppPaths.defaultAppSupportDirectory().appendingPathComponent("Plugins", isDirectory: true)
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
        return id.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || ($0 == "-") }
    }

    public static func listPlugins(
        in rootDir: URL = defaultPluginsDirectory(),
        includeDisabled: Bool = true,
        includeBuiltin: Bool = false,
        includeSecrets: Bool = true
    ) -> [PluginDescriptor] {
        let snapshot = loadStateSnapshot(in: rootDir)
        var results: [PluginDescriptor] = []
        if includeBuiltin {
            let builtinOverrides = snapshot.plugins.mapValues(\.overrides)
            let builtins = PluginBuiltinRegistry.descriptors(overridesByID: builtinOverrides)
            results.append(contentsOf: includeDisabled ? builtins : builtins.filter(\.isEnabled))
        }
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return results }

        let externals = folders.compactMap { folder -> PluginDescriptor? in
            guard folder.lastPathComponent != "PluginData" else { return nil }
            let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let desc = loadPlugin(at: folder, snapshot: snapshot, in: rootDir, includeSecrets: includeSecrets)
            return (!includeDisabled && !desc.isEnabled) ? nil : desc
        }.sorted { $0.id < $1.id }
        return results + externals
    }

    public static func loadPlugin(
        at directoryURL: URL,
        in rootDir: URL? = nil,
        includeSecrets: Bool = true
    ) -> PluginDescriptor {
        let resolvedRoot = rootDir ?? directoryURL.deletingLastPathComponent()
        return loadPlugin(
            at: directoryURL,
            snapshot: loadStateSnapshot(in: resolvedRoot),
            in: resolvedRoot,
            includeSecrets: includeSecrets
        )
    }

    static func loadPlugin(
        at directoryURL: URL,
        snapshot: PluginStateSnapshot,
        in rootDir: URL? = nil,
        includeSecrets: Bool = true
    ) -> PluginDescriptor {
        let resolvedRoot = rootDir ?? directoryURL.deletingLastPathComponent()
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
        let config = resolvedConfig(
            for: manifest, stored: inst.configValues, pluginsRoot: resolvedRoot, includeSecrets: includeSecrets
        )
        let granted = Set(inst.grantedCapabilities.compactMap { PluginCapability(rawValue: $0) })
        let revokedScopes = Set(inst.revokedResourceScopes.compactMap { PluginResourceScope(rawValue: $0) })
        let rtStatus = PluginDataInspector.readRuntimeStatus(for: manifest.id, in: resolvedRoot)
        return PluginDescriptor(
            id: manifest.id, directoryURL: directoryURL, manifest: manifest,
            validationIssues: issues, isEnabled: inst.isEnabled, userConfig: config,
            kind: .external, grantedCapabilities: granted, revokedResourceScopes: revokedScopes,
            overrides: inst.overrides, runtimeStatus: rtStatus
        )
    }

    public static func resolvedConfig(
        for manifest: PluginManifest,
        stored: [String: String],
        pluginsRoot: URL? = nil,
        includeSecrets: Bool = true
    ) -> [String: String] {
        var merged: [String: String] = [:]
        let service = pluginsRoot.map { PluginDataPaths.keychainService(forPluginsRoot: $0) } ?? PluginKeychainStore.defaultService
        let scopedVault = pluginsRoot.flatMap { PluginDataPaths.scopedVaultFileURL(forPluginsRoot: $0) }
        for field in manifest.config ?? [] {
            if field.type == .secret {
                guard includeSecrets else { continue }
                if let kcValue = try? PluginKeychainStore.loadSecret(
                    pluginID: manifest.id, fieldKey: field.key,
                    service: service, customVaultURL: scopedVault
                ), !kcValue.isEmpty {
                    merged[field.key] = kcValue
                } else if let def = field.defaultValue {
                    merged[field.key] = def
                }
            } else if let def = field.defaultValue {
                merged[field.key] = def
            }
        }
        let secretKeys = Set((manifest.config ?? []).filter { $0.type == .secret }.map(\.key))
        for (k, v) in stored where !secretKeys.contains(k) {
            merged[k] = v
        }
        return merged
    }

    public static func resolvedUserConfigWithSecrets(
        for plugin: PluginDescriptor,
        in rootDir: URL? = nil
    ) -> [String: String] {
        guard !plugin.isBuiltin else { return plugin.userConfig }
        let resolvedRoot = rootDir ?? plugin.directoryURL.deletingLastPathComponent()
        let stored = loadStateSnapshot(in: resolvedRoot).plugins[plugin.id]?.configValues ?? plugin.userConfig
        return resolvedConfig(
            for: plugin.manifest, stored: stored, pluginsRoot: resolvedRoot, includeSecrets: true
        )
    }

    public static func validate(
        manifest: PluginManifest,
        in directoryURL: URL,
        hostAppVersion: String = currentHostAppVersion
    ) -> [String] {
        var issues: [String] = []
        if !isSafePluginID(manifest.id) { issues.append("id 仅允许小写字母、数字与连字符") }
        if PluginBuiltinRegistry.isBuiltin(id: manifest.id) { issues.append("id '\(manifest.id)' 为内置插件保留前缀") }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("name 不能为空") }
        if manifest.keywords.isEmpty { issues.append("keywords 至少包含一个触发词") }
        if let minVer = manifest.minAppVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !minVer.isEmpty,
           PluginVersionComparator.compare(hostAppVersion, minVer) == .orderedAscending {
            issues.append("插件要求宿主最低版本 v\(minVer)（当前 v\(hostAppVersion)）")
        }
        if let timeout = manifest.timeoutSeconds, (!timeout.isFinite || timeout < 3.0 || timeout > 30.0) {
            issues.append("timeoutSeconds 必须在 3 ~ 30 秒之间")
        }
        if let iconErr = PluginIconResolver.validateManifestIcon(manifest.icon, in: directoryURL) {
            issues.append(iconErr)
        }
        issues.append(contentsOf: PluginCustomWindowSpec.validateManifestWindowDefaults(manifest.window, in: directoryURL))
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
            if field.type == .number, let lo = field.minValue, let hi = field.maxValue, lo > hi {
                issues.append("config 数值项 '\(field.key)' 的 minValue 不能大于 maxValue")
            }
            if field.control == .slider {
                if field.type != .number || field.minValue == nil || field.maxValue == nil || (field.minValue ?? 0) >= (field.maxValue ?? 0) {
                    issues.append("config 滑块项 '\(field.key)' 必须为 number 类型且声明有效的 minValue < maxValue")
                }
            }
        }
        if manifest.capabilities == nil {
            issues.append("注册时必须显式声明 capabilities 权限列表（无需宿主权限请写 []）")
        }
        for rawCap in manifest.capabilities ?? [] where PluginCapability(rawValue: rawCap) == nil {
            issues.append("未知 capability 声明：'\(rawCap)'")
        }
        if manifest.resourceScopes == nil {
            issues.append("注册时必须显式声明 resourceScopes 资源作用域（无网络/写盘/子进程请写 []）")
        }
        for rawScope in manifest.resourceScopes ?? [] where PluginResourceScope(rawValue: rawScope) == nil {
            issues.append("未知 resourceScope 声明：'\(rawScope)'")
        }
        for rawAccept in manifest.accepts ?? [] where PluginContextKind(rawValue: rawAccept) == nil {
            issues.append("未知 accepts 上下文类型声明：'\(rawAccept)'")
        }
        for rawExt in manifest.acceptExtensions ?? [] {
            let clean = rawExt.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if clean.isEmpty || clean.contains("/") || clean.contains("..") {
                issues.append("acceptExtensions 包含非法扩展名：'\(rawExt)'")
            }
        }
        for rawHost in manifest.acceptURLHosts ?? [] {
            let clean = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.contains("/") || clean.contains(" ") {
                issues.append("acceptURLHosts 包含非法域名：'\(rawHost)'")
            }
        }
        var seenCmdIDs = Set<String>()
        for cmd in manifest.commands ?? [] {
            if !PluginCommandRegistry.isSafeCommandID(cmd.id) {
                issues.append("commands 子功能 id '\(cmd.id)' 不合法（仅允许小写字母、数字、连字符与下划线）")
            } else if !seenCmdIDs.insert(cmd.id).inserted {
                issues.append("commands 存在重复的子功能 id：'\(cmd.id)'")
            }
            if cmd.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("commands 子功能 '\(cmd.id)' 的 title 不能为空")
            }
        }
        return issues
    }
}
