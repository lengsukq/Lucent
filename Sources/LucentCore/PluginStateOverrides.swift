import LucentFoundation
import Foundation

extension PluginSystem {
    public static func isValidAnyPluginID(_ id: String) -> Bool {
        PluginBuiltinRegistry.isBuiltin(id: id) || isSafePluginID(id)
    }

    public static func grantedCapabilities(id: String, in rootDir: URL = defaultPluginsDirectory()) -> Set<PluginCapability> {
        let raw = loadStateSnapshot(in: rootDir).plugins[id]?.grantedCapabilities ?? []
        return Set(raw.compactMap { PluginCapability(rawValue: $0) })
    }

    public static func setPluginCapabilityGranted(
        id: String, capability: PluginCapability, granted: Bool, in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        var current = grantedCapabilities(id: id, in: rootDir)
        if granted { current.insert(capability) } else { current.remove(capability) }
        try setPluginCapabilities(id: id, capabilities: current, in: rootDir)
    }

    public static func setPluginCapabilities(
        id: String, capabilities: Set<PluginCapability>, in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard isSafePluginID(id) else { throw LucentError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.grantedCapabilities = capabilities.map(\.rawValue).sorted()
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func revokedResourceScopes(id: String, in rootDir: URL = defaultPluginsDirectory()) -> Set<PluginResourceScope> {
        let raw = loadStateSnapshot(in: rootDir).plugins[id]?.revokedResourceScopes ?? []
        return Set(raw.compactMap { PluginResourceScope(rawValue: $0) })
    }

    public static func setPluginResourceScopeGranted(
        id: String, scope: PluginResourceScope, granted: Bool, in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard isSafePluginID(id) else { throw LucentError.pluginInvalid("插件 id '\(id)' 不合法") }
        var revoked = revokedResourceScopes(id: id, in: rootDir)
        if granted { revoked.remove(scope) } else { revoked.insert(scope) }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.revokedResourceScopes = revoked.map(\.rawValue).sorted()
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func pluginOverrides(
        id: String,
        in rootDir: URL = defaultPluginsDirectory()
    ) -> PluginUserOverrides {
        loadStateSnapshot(in: rootDir).plugins[id]?.overrides ?? PluginUserOverrides()
    }

    public static func updatePluginOverrides(
        id: String,
        in rootDir: URL = defaultPluginsDirectory(),
        _ mutate: (inout PluginUserOverrides) -> Void
    ) throws {
        guard isValidAnyPluginID(id) else {
            throw LucentError.pluginInvalid("插件 id '\(id)' 不合法")
        }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        var next = inst.overrides
        mutate(&next)
        if let customKws = next.customKeywords {
            let cleaned = customKws
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            next.customKeywords = cleaned.isEmpty ? nil : cleaned
        }
        var cleanedCmdHKs: [String: String] = [:]
        for (cmdID, rawChord) in next.commandHotKeys where PluginCommandRegistry.isSafeCommandID(cmdID) {
            cleanedCmdHKs[cmdID] = rawChord.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        next.commandHotKeys = cleanedCmdHKs
        var cleanedCmdSearch: [String: Bool] = [:]
        for (cmdID, flag) in next.commandSearchOverrides where PluginCommandRegistry.isSafeCommandID(cmdID) {
            cleanedCmdSearch[cmdID] = flag
        }
        next.commandSearchOverrides = cleanedCmdSearch
        next.priorityBoost = min(max(next.priorityBoost, -200), 300)
        next.quickButtonCommandIDs = deduplicateIDs(next.quickButtonCommandIDs)
        next.menuBarCommandIDs = deduplicateIDs(next.menuBarCommandIDs)
        inst.overrides = next
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func setPluginCommandHotKey(
        pluginID: String, commandID: String, hotKey: String?,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LucentError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if let hotKey {
                ov.commandHotKeys[commandID] = hotKey.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                ov.commandHotKeys.removeValue(forKey: commandID)
            }
        }
    }

    public static func setPluginCommandQuickButton(
        pluginID: String, commandID: String, enabled: Bool,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LucentError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if enabled {
                if !ov.quickButtonCommandIDs.contains(commandID) { ov.quickButtonCommandIDs.append(commandID) }
            } else {
                ov.quickButtonCommandIDs.removeAll { $0 == commandID }
            }
        }
    }

    public static func setPluginCommandMenuBar(
        pluginID: String, commandID: String, enabled: Bool,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LucentError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if enabled {
                if !ov.menuBarCommandIDs.contains(commandID) { ov.menuBarCommandIDs.append(commandID) }
            } else {
                ov.menuBarCommandIDs.removeAll { $0 == commandID }
            }
        }
    }

    public static func setPluginCommandSearchEnabled(
        pluginID: String, commandID: String, enabled: Bool?,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LucentError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if let enabled { ov.commandSearchOverrides[commandID] = enabled }
            else { ov.commandSearchOverrides.removeValue(forKey: commandID) }
        }
    }

    public static func setPluginSearchIndexGlobalEnabled(
        pluginID: String, enabled: Bool?,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            ov.searchIndexGlobalOverride = enabled
        }
    }

    public static func resetPluginOverrides(
        id: String, in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard isValidAnyPluginID(id) else {
            throw LucentError.pluginInvalid("插件 id '\(id)' 不合法")
        }
        var snap = loadStateSnapshot(in: rootDir)
        guard var inst = snap.plugins[id] else { return }
        let preservedCount = inst.overrides.launchCount
        let preservedEpoch = inst.overrides.lastUsedAtEpoch
        inst.overrides = PluginUserOverrides(launchCount: preservedCount, lastUsedAtEpoch: preservedEpoch)
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func recordPluginUsage(
        id: String, at now: Date = Date(),
        in rootDir: URL = defaultPluginsDirectory()
    ) {
        guard isValidAnyPluginID(id) else { return }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.overrides.launchCount = max(0, inst.overrides.launchCount) + 1
        inst.overrides.lastUsedAtEpoch = now.timeIntervalSince1970
        snap.plugins[id] = inst
        try? saveStateSnapshot(snap, in: rootDir)
    }

    private static func deduplicateIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { item in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}
