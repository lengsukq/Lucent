import Foundation

public struct PluginStarterTemplate: Identifiable, Sendable, Hashable, Equatable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let description: String
    public let mode: PluginMode
    public let icon: String
    public let keywords: [String]
    public let config: [PluginConfigField]
    public let capabilities: [PluginCapability]
    public let resourceScopes: [PluginResourceScope]
    public let accepts: [PluginContextKind]
    public let commands: [PluginCommandSpec]
    public let scriptBody: String

    public init(
        id: String, name: String, subtitle: String, description: String,
        mode: PluginMode, icon: String, keywords: [String],
        config: [PluginConfigField], capabilities: [PluginCapability] = [],
        resourceScopes: [PluginResourceScope] = [],
        accepts: [PluginContextKind] = [],
        commands: [PluginCommandSpec] = [],
        scriptBody: String
    ) {
        self.id = id; self.name = name; self.subtitle = subtitle; self.description = description
        self.mode = mode; self.icon = icon; self.keywords = keywords
        self.config = config; self.capabilities = capabilities
        self.resourceScopes = resourceScopes; self.accepts = accepts
        self.commands = commands; self.scriptBody = scriptBody
    }
}

public enum PluginStarterGallery {
    public static func template(id: String) -> PluginStarterTemplate? {
        templates.first { $0.id == id }
    }

    public static func isInstalled(templateID: String, in rootDir: URL = PluginSystem.defaultPluginsDirectory()) -> Bool {
        FileManager.default.fileExists(atPath: rootDir.appendingPathComponent(templateID).appendingPathComponent("plugin.json").path)
    }

    @discardableResult
    public static func install(
        templateID: String,
        in rootDir: URL = PluginSystem.defaultPluginsDirectory(),
        overwrite: Bool = true
    ) throws -> PluginDescriptor {
        guard let tpl = template(id: templateID) else {
            throw LumakeyError.pluginInvalid("未知精选插件模板：\(templateID)")
        }
        let pluginDir = rootDir.appendingPathComponent(tpl.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: pluginDir.path) {
            guard overwrite else { throw LumakeyError.pluginInvalid("插件 '\(tpl.id)' 已安装") }
            try FileManager.default.removeItem(at: pluginDir)
        }
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let entryName = "run.sh"
        let scriptURL = pluginDir.appendingPathComponent(entryName)
        try tpl.scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let manifest = PluginManifest(
            schemaVersion: 3,
            id: tpl.id, name: tpl.name, version: "1.0.0", description: tpl.description,
            mode: tpl.mode, keywords: tpl.keywords, entry: entryName,
            author: "Lumakey Official", icon: tpl.icon, config: tpl.config,
            capabilities: tpl.capabilities.map(\.rawValue),
            resourceScopes: tpl.resourceScopes.map(\.rawValue),
            accepts: tpl.accepts.isEmpty ? nil : tpl.accepts.map(\.rawValue),
            commands: tpl.commands.isEmpty ? nil : tpl.commands
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: pluginDir.appendingPathComponent("plugin.json"), options: .atomic)
        return PluginSystem.loadPlugin(at: pluginDir, in: rootDir)
    }
}
