import Foundation

extension PluginSystem {
    public static func loadStateSnapshot(in rootDir: URL = defaultPluginsDirectory()) -> PluginStateSnapshot {
        stateLock.withLock {
            let url = stateFileURL(for: rootDir)
            guard let data = try? Data(contentsOf: url),
                  let snap = try? JSONDecoder().decode(PluginStateSnapshot.self, from: data)
            else { return PluginStateSnapshot() }
            return snap
        }
    }

    public static func saveStateSnapshot(_ snapshot: PluginStateSnapshot, in rootDir: URL = defaultPluginsDirectory()) throws {
        try stateLock.withLock {
            let url = stateFileURL(for: rootDir)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        }
    }

    public static func isPluginEnabled(id: String, in rootDir: URL = defaultPluginsDirectory()) -> Bool {
        loadStateSnapshot(in: rootDir).plugins[id]?.isEnabled ?? true
    }

    public static func setPluginEnabled(id: String, isEnabled: Bool, in rootDir: URL = defaultPluginsDirectory()) throws {
        if PluginBuiltinRegistry.setBuiltinEnabled(id: id, isEnabled: isEnabled) { return }
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.isEnabled = isEnabled
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func pluginConfig(id: String, in rootDir: URL = defaultPluginsDirectory()) -> [String: String] {
        loadStateSnapshot(in: rootDir).plugins[id]?.configValues ?? [:]
    }

    public static func updatePluginConfig(id: String, values: [String: String], in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.configValues = values
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
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
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        var snap = loadStateSnapshot(in: rootDir)
        var inst = snap.plugins[id] ?? PluginInstanceState()
        inst.grantedCapabilities = capabilities.map(\.rawValue).sorted()
        snap.plugins[id] = inst
        try saveStateSnapshot(snap, in: rootDir)
    }

    public static func buildStdinContextData(
        for descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        bridgeSocketPath: String? = nil,
        bridgeToken: String? = nil,
        grantedCapabilities: Set<PluginCapability> = [],
        in rootDir: URL? = nil
    ) throws -> Data {
        let stateRoot = rootDir ?? descriptor.directoryURL.deletingLastPathComponent()
        let stored = pluginConfig(id: descriptor.id, in: stateRoot)
        let mergedConfig = resolvedConfig(for: descriptor.manifest, stored: descriptor.userConfig.merging(stored) { _, new in new })
        var payload: [String: Any] = [
            "query": query,
            "mode": descriptor.manifest.mode.rawValue,
            "config": mergedConfig,
            "clipboard": clipboardText
        ]
        if let bridgeSocketPath, let bridgeToken {
            payload["bridge"] = [
                "socket": bridgeSocketPath,
                "token": bridgeToken,
                "grantedCapabilities": grantedCapabilities.map(\.rawValue).sorted()
            ]
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func runScriptPlugin(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LumakeyError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        if descriptor.isBuiltin {
            if let resolved = PluginBuiltinRegistry.runBuiltin(id: descriptor.id, query: query) {
                return resolved.execution
            }
            throw LumakeyError.pluginInvalid("未知内置插件：\(descriptor.id)")
        }
        let stateRoot = rootDir ?? descriptor.directoryURL.deletingLastPathComponent()
        let enabledNow = descriptor.isEnabled && isPluginEnabled(id: descriptor.id, in: stateRoot)
        guard enabledNow else {
            throw LumakeyError.pluginExecutionFailed("插件 '\(descriptor.manifest.name)' 当前已禁用")
        }
        let latestGrants = descriptor.grantedCapabilities.union(grantedCapabilities(id: descriptor.id, in: stateRoot))
            .intersection(Set(descriptor.declaredCapabilities))
        var bridgeServer: PluginHostBridgeServer?
        var bridgeEnv: [String: String]?
        if !descriptor.declaredCapabilities.isEmpty {
            let server = try PluginHostBridgeServer(descriptor: descriptor, grantedCapabilities: latestGrants, hostContext: hostContext)
            bridgeServer = server
            bridgeEnv = ["LUMAKEY_BRIDGE_SOCK": server.socketPath, "LUMAKEY_BRIDGE_TOKEN": server.token]
        }
        defer { bridgeServer?.stop() }

        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let inputData = try buildStdinContextData(
            for: descriptor, query: query, clipboardText: clipboardText,
            bridgeSocketPath: bridgeServer?.socketPath, bridgeToken: bridgeServer?.token,
            grantedCapabilities: latestGrants, in: stateRoot
        )
        let result = try ProcessSupervisor.shared.run(
            executableURL: entryURL, arguments: arguments, currentDirectoryURL: descriptor.directoryURL,
            environment: bridgeEnv, stdinData: inputData, timeoutSeconds: timeoutSeconds, maxOutputBytes: 131_072
        )
        if result.timedOut {
            throw LumakeyError.pluginExecutionFailed("插件进程执行超时（\(Int(timeoutSeconds))s）已被自动终止")
        }
        return PluginExecutionResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, durationMs: result.durationMs)
    }

    public static func runPluginSync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginResolvedOutput {
        if descriptor.isBuiltin, let resolved = PluginBuiltinRegistry.runBuiltin(id: descriptor.id, query: query) {
            return resolved
        }
        let exec = try runScriptPlugin(
            descriptor, query: query, clipboardText: clipboardText, arguments: arguments,
            hostContext: hostContext, in: rootDir, timeoutSeconds: timeoutSeconds
        )
        return PluginResolvedOutput(descriptor: descriptor, execution: exec)
    }

    public static func runPluginAsync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) async throws -> PluginResolvedOutput {
        try await Task.detached(priority: .userInitiated) {
            try runPluginSync(
                descriptor, query: query, clipboardText: clipboardText, arguments: arguments,
                hostContext: hostContext, in: rootDir, timeoutSeconds: timeoutSeconds
            )
        }.value
    }
}
