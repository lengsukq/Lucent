import Foundation
import LucentFoundation

extension PluginSystem {
    public static func loadStateSnapshot(in rootDir: URL = defaultPluginsDirectory()) -> PluginStateSnapshot {
        stateLock.withLock {
            AtomicJSONStore.load(PluginStateSnapshot.self, from: stateFileURL(for: rootDir), fallback: PluginStateSnapshot())
        }
    }

    public static func saveStateSnapshot(_ snapshot: PluginStateSnapshot, in rootDir: URL = defaultPluginsDirectory()) throws {
        try stateLock.withLock {
            try AtomicJSONStore.writeThrowing(snapshot, to: stateFileURL(for: rootDir))
        }
    }

    public static func isPluginEnabled(id: String, in rootDir: URL = defaultPluginsDirectory()) -> Bool {
        loadStateSnapshot(in: rootDir).plugins[id]?.isEnabled ?? true
    }

    public static func setPluginEnabled(id: String, isEnabled: Bool, in rootDir: URL = defaultPluginsDirectory()) throws {
        if PluginBuiltinRegistry.setBuiltinEnabled(id: id, isEnabled: isEnabled) { return }
        guard isSafePluginID(id) else { throw LucentError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.isEnabled = isEnabled
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
        if !isEnabled, id == LumaLinkServer.companionPluginID,
           rootDir.standardizedFileURL.path == defaultPluginsDirectory().standardizedFileURL.path {
            var cfg = LumaLinkServer.shared.currentConfig()
            if cfg.enabled {
                cfg.enabled = false
                LumaLinkServer.shared.apply(config: cfg, persist: true)
            }
        }
    }

    public static func pluginConfig(id: String, in rootDir: URL = defaultPluginsDirectory()) -> [String: String] {
        var result = loadStateSnapshot(in: rootDir).plugins[id]?.configValues ?? [:]
        if let secretKeys = secretFieldKeys(id: id, in: rootDir), !secretKeys.isEmpty {
            let service = PluginDataPaths.keychainService(forPluginsRoot: rootDir)
            let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: rootDir)
            for key in secretKeys {
                if let sec = try? PluginKeychainStore.loadSecret(
                    pluginID: id, fieldKey: key, service: service, customVaultURL: scopedVault
                ) {
                    result[key] = sec
                }
            }
        }
        return result
    }

    public static func updatePluginConfig(id: String, values: [String: String], in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else { throw LucentError.pluginInvalid("插件 id '\(id)' 不合法") }
        let secretKeys = secretFieldKeys(id: id, in: rootDir) ?? []
        let service = PluginDataPaths.keychainService(forPluginsRoot: rootDir)
        let scopedVault = PluginDataPaths.scopedVaultFileURL(forPluginsRoot: rootDir)
        var nonSecretValues: [String: String] = [:]
        for (k, v) in values {
            if secretKeys.contains(k) {
                try PluginKeychainStore.saveSecret(
                    v, pluginID: id, fieldKey: k, service: service, customVaultURL: scopedVault
                )
            } else {
                nonSecretValues[k] = v
            }
        }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.configValues = nonSecretValues
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    static func secretFieldKeys(id: String, in rootDir: URL) -> Set<String>? {
        guard isSafePluginID(id) else { return nil }
        let manifestURL = rootDir.appendingPathComponent(id, isDirectory: true).appendingPathComponent("plugin.json")
        guard let manifest = AtomicJSONStore.decode(PluginManifest.self, from: manifestURL) else { return nil }
        return Set((manifest.config ?? []).filter { $0.type == .secret }.map(\.key))
    }
}
