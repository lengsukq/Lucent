import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

public enum HomeLaunchTarget: Codable, Sendable, Hashable, Equatable {
    case builtin(HomeBuiltinActionID)
    case nativeApp(path: String, bundleID: String? = nil)
    case plugin(pluginID: String, behavior: HomePluginLaunchBehavior = .auto)
    case pluginCommand(pluginID: String, commandID: String, arguments: [String]? = nil)
    case script(scriptID: String)
    case bookmark(url: String, browserAppPath: String? = nil, sourcePluginID: String? = nil)
    case localPath(path: String)
    case queryChip(query: String, filter: String? = nil)

    private enum KindKey: String, Codable {
        case builtin, nativeApp, plugin, pluginCommand, script, bookmark, localPath, queryChip
    }

    private enum CodingKeys: String, CodingKey {
        case kind, builtinID, path, bundleID, pluginID, behavior
        case commandID, arguments, scriptID, url, browserAppPath, sourcePluginID, query, filter
    }

    public var kindName: String {
        switch self {
        case .builtin: "builtin"
        case .nativeApp: "nativeApp"
        case .plugin: "plugin"
        case .pluginCommand: "pluginCommand"
        case .script: "script"
        case .bookmark: "bookmark"
        case .localPath: "localPath"
        case .queryChip: "queryChip"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(KindKey.self, forKey: .kind) {
        case .builtin:
            self = .builtin(try c.decode(HomeBuiltinActionID.self, forKey: .builtinID))
        case .nativeApp:
            self = .nativeApp(
                path: try c.decode(String.self, forKey: .path),
                bundleID: try c.decodeIfPresent(String.self, forKey: .bundleID)
            )
        case .plugin:
            self = .plugin(
                pluginID: try c.decode(String.self, forKey: .pluginID),
                behavior: try c.decodeIfPresent(HomePluginLaunchBehavior.self, forKey: .behavior) ?? .auto
            )
        case .pluginCommand:
            self = .pluginCommand(
                pluginID: try c.decode(String.self, forKey: .pluginID),
                commandID: try c.decode(String.self, forKey: .commandID),
                arguments: try c.decodeIfPresent([String].self, forKey: .arguments)
            )
        case .script:
            self = .script(scriptID: try c.decode(String.self, forKey: .scriptID))
        case .bookmark:
            self = .bookmark(
                url: try c.decode(String.self, forKey: .url),
                browserAppPath: try c.decodeIfPresent(String.self, forKey: .browserAppPath),
                sourcePluginID: try c.decodeIfPresent(String.self, forKey: .sourcePluginID)
            )
        case .localPath:
            self = .localPath(path: try c.decode(String.self, forKey: .path))
        case .queryChip:
            self = .queryChip(
                query: try c.decode(String.self, forKey: .query),
                filter: try c.decodeIfPresent(String.self, forKey: .filter)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtin(let id):
            try c.encode(KindKey.builtin, forKey: .kind); try c.encode(id, forKey: .builtinID)
        case .nativeApp(let path, let bundleID):
            try c.encode(KindKey.nativeApp, forKey: .kind); try c.encode(path, forKey: .path)
            try c.encodeIfPresent(bundleID, forKey: .bundleID)
        case .plugin(let pluginID, let behavior):
            try c.encode(KindKey.plugin, forKey: .kind); try c.encode(pluginID, forKey: .pluginID)
            if behavior != .auto { try c.encode(behavior, forKey: .behavior) }
        case .pluginCommand(let pluginID, let commandID, let arguments):
            try c.encode(KindKey.pluginCommand, forKey: .kind); try c.encode(pluginID, forKey: .pluginID)
            try c.encode(commandID, forKey: .commandID); try c.encodeIfPresent(arguments, forKey: .arguments)
        case .script(let scriptID):
            try c.encode(KindKey.script, forKey: .kind); try c.encode(scriptID, forKey: .scriptID)
        case .bookmark(let url, let browserAppPath, let sourcePluginID):
            try c.encode(KindKey.bookmark, forKey: .kind); try c.encode(url, forKey: .url)
            try c.encodeIfPresent(browserAppPath, forKey: .browserAppPath)
            try c.encodeIfPresent(sourcePluginID, forKey: .sourcePluginID)
        case .localPath(let path):
            try c.encode(KindKey.localPath, forKey: .kind); try c.encode(path, forKey: .path)
        case .queryChip(let query, let filter):
            try c.encode(KindKey.queryChip, forKey: .kind); try c.encode(query, forKey: .query)
            try c.encodeIfPresent(filter, forKey: .filter)
        }
    }
}

public struct HomeLaunchItem: Codable, Sendable, Hashable, Identifiable, Equatable {
    public var id: String
    public var target: HomeLaunchTarget
    public var customTitle: String?
    public var customSubtitle: String?
    public var customIcon: String?
    public var accentColor: String?
    public var hotkeyHint: String?

    public init(
        id: String,
        target: HomeLaunchTarget,
        customTitle: String? = nil,
        customSubtitle: String? = nil,
        customIcon: String? = nil,
        accentColor: String? = nil,
        hotkeyHint: String? = nil
    ) {
        self.id = id
        self.target = target
        self.customTitle = Self.cleanOptional(customTitle, maxLength: 60)
        self.customSubtitle = Self.cleanOptional(customSubtitle, maxLength: 90)
        self.customIcon = Self.cleanOptional(customIcon, maxLength: 64)
        self.accentColor = Self.cleanOptional(accentColor, maxLength: 24)
        self.hotkeyHint = Self.cleanOptional(hotkeyHint, maxLength: 16)
    }

    private static func cleanOptional(_ raw: String?, maxLength: Int) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.count <= maxLength ? trimmed : String(trimmed.prefix(maxLength))
    }
}

public enum HomeLaunchSecurity {
    public static let allowedBookmarkSchemes: Set<String> = [
        "http", "https", "lumakey", "mailto", "vscode", "vscode-insiders",
        "cursor", "zed", "obsidian", "notion", "raycast", "things", "bear",
        "x-apple.systempreferences"
    ]

    public static func isSafeIdentifier(_ id: String, maxLength: Int = 64) -> Bool {
        guard !id.isEmpty, id.count <= maxLength else { return false }
        return id.allSatisfy {
            ($0 >= "a" && $0 <= "z") || ($0 >= "A" && $0 <= "Z")
                || ($0 >= "0" && $0 <= "9") || $0 == "-" || $0 == "_" || $0 == ":" || $0 == "."
        }
    }

    public static func validateItem(_ item: HomeLaunchItem) -> String? {
        guard isSafeIdentifier(item.id) else {
            return "Invalid item id '\(item.id)' (use alphanumeric, '-', '_', ':', '.')."
        }
        return validateTarget(item.target)
    }

    public static func validateTarget(_ target: HomeLaunchTarget) -> String? {
        switch target {
        case .builtin:
            return nil
        case .nativeApp(let path, _):
            let std = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            guard std.hasPrefix("/"), std.lowercased().hasSuffix(".app"), !std.contains("\0") else {
                return "nativeApp path must be an absolute '.app' bundle path."
            }
            return nil
        case .plugin(let pluginID, _):
            guard PluginBuiltinRegistry.isBuiltin(id: pluginID) || PluginSystem.isSafePluginID(pluginID) else {
                return "Invalid pluginID '\(pluginID)'."
            }
            return nil
        case .pluginCommand(let pluginID, let commandID, let args):
            guard PluginBuiltinRegistry.isBuiltin(id: pluginID) || PluginSystem.isSafePluginID(pluginID) else {
                return "Invalid pluginID '\(pluginID)'."
            }
            guard PluginCommandRegistry.isSafeCommandID(commandID) else {
                return "Invalid commandID '\(commandID)'."
            }
            if let args, args.count > 12 || args.contains(where: { $0.count > 256 || $0.contains("\0") }) {
                return "pluginCommand arguments exceed safety bounds."
            }
            return nil
        case .script(let scriptID):
            guard ScriptHeaderParser.isSafeScriptID(scriptID) else {
                return "Invalid scriptID '\(scriptID)'."
            }
            return nil
        case .bookmark(let rawURL, let browserPath, _):
            let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= 2_048,
                  let parsed = URL(string: trimmed),
                  let scheme = parsed.scheme?.lowercased(),
                  allowedBookmarkSchemes.contains(scheme) else {
                return "Bookmark URL scheme is not in the allowed safe whitelist."
            }
            if (scheme == "http" || scheme == "https"), (parsed.host ?? "").isEmpty {
                return "HTTP(S) bookmark URL must contain a valid host."
            }
            if let browserPath, !browserPath.isEmpty {
                let std = URL(fileURLWithPath: (browserPath as NSString).expandingTildeInPath).standardizedFileURL.path
                guard std.hasPrefix("/"), std.lowercased().hasSuffix(".app") else {
                    return "browserAppPath must be an absolute '.app' bundle path."
                }
            }
            return nil
        case .localPath(let path):
            let std = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
            guard std.hasPrefix("/"), std.count <= 1_024, !std.contains("\0") else {
                return "localPath must be a valid local path."
            }
            return nil
        case .queryChip(let query, let filter):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 160 else {
                return "queryChip query must be 1..160 characters."
            }
            if let filter, !filter.isEmpty, OmniFilter(rawValue: filter) == nil {
                return "queryChip filter must be one of: all, files, clipboard, plugins."
            }
            return nil
        }
    }
}
