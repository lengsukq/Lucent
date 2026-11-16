import Foundation

extension PluginSystem {
    public static func isValidAnyPluginID(_ id: String) -> Bool {
        PluginBuiltinRegistry.isBuiltin(id: id) || isSafePluginID(id)
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
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法")
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
        next.priorityBoost = min(max(next.priorityBoost, -200), 300)
        next.quickButtonCommandIDs = deduplicateIDs(next.quickButtonCommandIDs)
        next.disabledCommandIDs = deduplicateIDs(next.disabledCommandIDs)
        inst.overrides = next
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func setPluginCommandHotKey(
        pluginID: String,
        commandID: String,
        hotKey: String?,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LumakeyError.pluginInvalid("子功能 id '\(commandID)' 不合法")
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
        pluginID: String,
        commandID: String,
        enabled: Bool,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LumakeyError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if enabled {
                if !ov.quickButtonCommandIDs.contains(commandID) {
                    ov.quickButtonCommandIDs.append(commandID)
                }
            } else {
                ov.quickButtonCommandIDs.removeAll { $0 == commandID }
            }
        }
    }

    public static func setPluginCommandSearchEnabled(
        pluginID: String,
        commandID: String,
        enabled: Bool,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard PluginCommandRegistry.isSafeCommandID(commandID) else {
            throw LumakeyError.pluginInvalid("子功能 id '\(commandID)' 不合法")
        }
        try updatePluginOverrides(id: pluginID, in: rootDir) { ov in
            if enabled {
                ov.disabledCommandIDs.removeAll { $0 == commandID }
            } else if !ov.disabledCommandIDs.contains(commandID) {
                ov.disabledCommandIDs.append(commandID)
            }
        }
    }

    public static func resetPluginOverrides(
        id: String,
        in rootDir: URL = defaultPluginsDirectory()
    ) throws {
        guard isValidAnyPluginID(id) else {
            throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法")
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
        id: String,
        at now: Date = Date(),
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
