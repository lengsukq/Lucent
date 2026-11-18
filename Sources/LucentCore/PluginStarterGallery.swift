import LucentFoundation
import Foundation

public struct PluginStarterTemplate: Identifiable, Sendable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let description: String
    public let mode: PluginMode
    public let icon: String
    public let accentColor: String?
    public let categoryTag: String?
    public let keywords: [String]
    public let config: [PluginConfigField]
    public let capabilities: [PluginCapability]
    public let resourceScopes: [PluginResourceScope]
    public let accepts: [PluginContextKind]
    public let commands: [PluginCommandSpec]
    public let locales: [String: PluginLocaleStrings]

    public init(
        id: String, name: String, subtitle: String, description: String,
        mode: PluginMode, icon: String, accentColor: String? = nil, categoryTag: String? = nil,
        keywords: [String], config: [PluginConfigField], capabilities: [PluginCapability] = [],
        resourceScopes: [PluginResourceScope] = [], accepts: [PluginContextKind] = [],
        commands: [PluginCommandSpec] = [], locales: [String: PluginLocaleStrings] = [:]
    ) {
        self.id = id; self.name = name; self.subtitle = subtitle; self.description = description
        self.mode = mode; self.icon = icon; self.accentColor = accentColor; self.categoryTag = categoryTag
        self.keywords = keywords; self.config = config; self.capabilities = capabilities
        self.resourceScopes = resourceScopes; self.accepts = accepts; self.commands = commands
        self.locales = locales
    }
}

public enum PluginStarterGallery {
    public static func template(id: String) -> PluginStarterTemplate? {
        templates.first { $0.id == id }
    }

    public static func isInstalled(templateID: String, in rootDir: URL = PluginSystem.defaultPluginsDirectory()) -> Bool {
        FileManager.default.fileExists(atPath: rootDir.appendingPathComponent(templateID).appendingPathComponent("plugin.json").path)
    }

    private static func bundledStarterArchiveURL(id: String, bundle: Bundle = .main) -> URL? {
        for subpath in ["plugin-demo/starters/\(id).zip", "plugin-demo/Starters/\(id).zip"] {
            if let bundled = bundle.resourceURL?.appendingPathComponent(subpath),
               FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for subpath in ["plugin-demo/Starters/\(id).zip", "plugin-demo/starters/\(id).zip"] {
            let devArchive = repoRoot.appendingPathComponent(subpath)
            if FileManager.default.fileExists(atPath: devArchive.path) {
                return devArchive
            }
        }
        return nil
    }

    private static func unpackStarterArchive(_ zipURL: URL, to pluginDir: URL, id: String) throws {
        let result = try ProcessSupervisor.shared.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", zipURL.path, pluginDir.path],
            timeoutSeconds: 10.0
        )
        guard result.exitCode == 0 else {
            throw LucentError.pluginInvalid("解压内置精选模板 '\(id)' 失败：\(result.stderr)")
        }
        let binURL = pluginDir.appendingPathComponent("bin/\(id)")
        guard FileManager.default.fileExists(atPath: binURL.path) else {
            throw LucentError.pluginInvalid("精选模板包 '\(id)' 缺少预编译可执行文件 bin/\(id)")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binURL.path)
    }

    @discardableResult
    public static func install(
        templateID: String,
        in rootDir: URL = PluginSystem.defaultPluginsDirectory(),
        overwrite: Bool = true
    ) throws -> PluginDescriptor {
        guard let tpl = template(id: templateID) else {
            throw LucentError.pluginInvalid("未知精选插件模板：\(templateID)")
        }
        guard let zipURL = bundledStarterArchiveURL(id: tpl.id) else {
            throw LucentError.pluginInvalid("未找到内置精选模板归档：\(tpl.id).zip")
        }
        let pluginDir = rootDir.appendingPathComponent(tpl.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginDir.path) {
            guard overwrite else { throw LucentError.pluginInvalid("插件 '\(tpl.id)' 已安装") }
            try FileManager.default.removeItem(at: pluginDir)
        }
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try unpackStarterArchive(zipURL, to: pluginDir, id: tpl.id)

        let manifest = PluginManifest(
            schemaVersion: 3,
            id: tpl.id, name: tpl.name, version: "2.0.0", description: tpl.description,
            mode: tpl.mode, keywords: tpl.keywords, entry: "bin/\(tpl.id)",
            author: "Lucent Official", icon: tpl.icon,
            accentColor: tpl.accentColor, categoryTag: tpl.categoryTag,
            config: tpl.config,
            capabilities: tpl.capabilities.map(\.rawValue),
            resourceScopes: tpl.resourceScopes.map(\.rawValue),
            accepts: tpl.accepts.isEmpty ? nil : tpl.accepts.map(\.rawValue),
            commands: tpl.commands.isEmpty ? nil : tpl.commands,
            locales: tpl.locales.isEmpty ? nil : tpl.locales
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return PluginSystem.loadPlugin(at: pluginDir, in: rootDir)
    }
}
