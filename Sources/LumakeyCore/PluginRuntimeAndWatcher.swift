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
        var result = loadStateSnapshot(in: rootDir).plugins[id]?.configValues ?? [:]
        if let secretKeys = secretFieldKeys(id: id, in: rootDir), !secretKeys.isEmpty {
            let service = PluginDataPaths.keychainService(forPluginsRoot: rootDir)
            for key in secretKeys {
                if let sec = try? PluginKeychainStore.loadSecret(pluginID: id, fieldKey: key, service: service) {
                    result[key] = sec
                }
            }
        }
        return result
    }

    public static func updatePluginConfig(id: String, values: [String: String], in rootDir: URL = defaultPluginsDirectory()) throws {
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
        let secretKeys = secretFieldKeys(id: id, in: rootDir) ?? []
        let service = PluginDataPaths.keychainService(forPluginsRoot: rootDir)
        var nonSecretValues: [String: String] = [:]
        for (k, v) in values {
            if secretKeys.contains(k) {
                try PluginKeychainStore.saveSecret(v, pluginID: id, fieldKey: k, service: service)
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
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else { return nil }
        return Set((manifest.config ?? []).filter { $0.type == .secret }.map(\.key))
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
        dataDirectoryURL: URL? = nil,
        configOverrides: [String: String]? = nil,
        in rootDir: URL? = nil
    ) throws -> Data {
        let stateRoot = rootDir ?? descriptor.directoryURL.deletingLastPathComponent()
        let stored = pluginConfig(id: descriptor.id, in: stateRoot)
        var mergedConfig = resolvedConfig(
            for: descriptor.manifest,
            stored: descriptor.userConfig.merging(stored) { _, new in new },
            pluginsRoot: stateRoot
        )
        if let configOverrides {
            for (k, v) in configOverrides { mergedConfig[k] = v }
        }
        let gatedClipboard = grantedCapabilities.contains(.clipboard) ? clipboardText : ""
        var payload: [String: Any] = [
            "query": query,
            "mode": descriptor.manifest.mode.rawValue,
            "config": mergedConfig,
            "clipboard": gatedClipboard
        ]
        if let dataDirectoryURL {
            payload["dataDir"] = dataDirectoryURL.path
        }
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
        try runExternalPlugin(
            descriptor,
            context: PluginExecutionContext(
                query: query,
                arguments: arguments,
                clipboardText: clipboardText,
                hostContext: hostContext,
                pluginsRoot: rootDir,
                timeoutSeconds: timeoutSeconds
            )
        )
    }

    static func runExternalPlugin(
        _ descriptor: PluginDescriptor,
        context: PluginExecutionContext
    ) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LumakeyError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        if descriptor.isBuiltin {
            return try BuiltinPluginProvider().execute(descriptor, context: context).execution
        }
        let stateRoot = context.pluginsRoot ?? descriptor.directoryURL.deletingLastPathComponent()
        let enabledNow = descriptor.isEnabled && isPluginEnabled(id: descriptor.id, in: stateRoot)
        guard enabledNow else {
            throw LumakeyError.pluginExecutionFailed("插件 '\(descriptor.manifest.name)' 当前已禁用")
        }
        let latestGrants = descriptor.grantedCapabilities.union(grantedCapabilities(id: descriptor.id, in: stateRoot))
            .intersection(Set(descriptor.declaredCapabilities))
        var bridgeServer: PluginHostBridgeServer?
        var env: [String: String] = [:]
        if let dataDir = PluginDataPaths.ensureDataDirectory(for: descriptor.id, pluginsRoot: stateRoot) {
            env["LUMAKEY_DATA_DIR"] = dataDir.path
        }
        if !descriptor.declaredCapabilities.isEmpty {
            let server = try PluginHostBridgeServer(descriptor: descriptor, grantedCapabilities: latestGrants, hostContext: context.hostContext)
            bridgeServer = server
            env["LUMAKEY_BRIDGE_SOCK"] = server.socketPath
            env["LUMAKEY_BRIDGE_TOKEN"] = server.token
        }
        defer { bridgeServer?.stop() }

        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let dataDir = PluginDataPaths.dataDirectory(for: descriptor.id, pluginsRoot: stateRoot)
        let inputData = try buildStdinContextData(
            for: descriptor,
            query: context.query,
            clipboardText: context.clipboardText,
            bridgeSocketPath: bridgeServer?.socketPath,
            bridgeToken: bridgeServer?.token,
            grantedCapabilities: latestGrants,
            dataDirectoryURL: dataDir,
            configOverrides: context.configOverrides,
            in: stateRoot
        )
        let result = try ProcessSupervisor.shared.run(
            executableURL: entryURL,
            arguments: context.arguments,
            currentDirectoryURL: descriptor.directoryURL,
            environment: env.isEmpty ? nil : env,
            stdinData: inputData,
            timeoutSeconds: context.timeoutSeconds,
            maxOutputBytes: 131_072,
            cancellationHandle: context.cancellationHandle
        )
        if result.wasCancelled {
            if descriptor.declaredCapabilities.contains(.audio) {
                _ = PluginAudioBridgePlayer.shared.stop()
            }
            throw CancellationError()
        }
        if result.timedOut {
            throw LumakeyError.pluginExecutionFailed("插件进程执行超时（\(Int(context.timeoutSeconds))s）已被自动终止")
        }
        return PluginExecutionResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, durationMs: result.durationMs)
    }

    public static func runPluginSync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        configOverrides: [String: String]? = nil,
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginResolvedOutput {
        let context = PluginExecutionContext(
            query: query, arguments: arguments, clipboardText: clipboardText,
            configOverrides: configOverrides, hostContext: hostContext,
            pluginsRoot: rootDir, timeoutSeconds: timeoutSeconds
        )
        let providers: [any PluginExecutionProvider] = [BuiltinPluginProvider(), ExternalScriptPluginProvider()]
        guard let provider = providers.first(where: { $0.supports(descriptor) }) else {
            throw LumakeyError.pluginInvalid("无可用插件执行器：\(descriptor.id)")
        }
        return try provider.execute(descriptor, context: context)
    }

    public static func runPluginAsync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        configOverrides: [String: String]? = nil,
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) async throws -> PluginResolvedOutput {
        let cancelHandle = ProcessCancellationHandle()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let context = PluginExecutionContext(
                    query: query, arguments: arguments, clipboardText: clipboardText,
                    configOverrides: configOverrides, hostContext: hostContext,
                    pluginsRoot: rootDir, timeoutSeconds: timeoutSeconds,
                    cancellationHandle: cancelHandle
                )
                let providers: [any PluginExecutionProvider] = [BuiltinPluginProvider(), ExternalScriptPluginProvider()]
                guard let provider = providers.first(where: { $0.supports(descriptor) }) else {
                    throw LumakeyError.pluginInvalid("无可用插件执行器：\(descriptor.id)")
                }
                return try provider.execute(descriptor, context: context)
            }.value
        } onCancel: {
            cancelHandle.cancel()
        }
    }
}
