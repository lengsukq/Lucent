import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
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
        guard isSafePluginID(id) else { throw LumakeyError.pluginInvalid("插件 id '\(id)' 不合法") }
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
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else { return nil }
        return Set((manifest.config ?? []).filter { $0.type == .secret }.map(\.key))
    }

    public static func buildStdinContextData(
        for descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        contextPayload: PluginContextPayload? = nil,
        bridgeSocketPath: String? = nil,
        bridgeToken: String? = nil,
        grantedCapabilities: Set<PluginCapability> = [],
        dataDirectoryURL: URL? = nil,
        configOverrides: [String: String]? = nil,
        locale: AppLanguageID = L10n.current,
        theme: AppThemeID? = nil,
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
        let resolvedTheme = (theme ?? AppThemeConfig.load().selectedTheme).rawValue
        var payload: [String: Any] = [
            "query": query,
            "mode": descriptor.manifest.mode.rawValue,
            "locale": locale.rawValue,
            "theme": resolvedTheme,
            "config": mergedConfig,
            "clipboard": gatedClipboard
        ]
        if let contextPayload { payload["context"] = contextPayload.toJSONObject() }
        if let dataDirectoryURL { payload["dataDir"] = dataDirectoryURL.path }
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
        contextPayload: PluginContextPayload? = nil,
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginExecutionResult {
        try runExternalPlugin(
            descriptor,
            context: PluginExecutionContext(
                query: query, arguments: arguments, clipboardText: clipboardText,
                contextPayload: contextPayload, hostContext: hostContext,
                pluginsRoot: rootDir, timeoutSeconds: timeoutSeconds
            )
        )
    }

    static func runExternalPlugin(_ descriptor: PluginDescriptor, context: PluginExecutionContext) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LumakeyError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        if descriptor.isBuiltin {
            return try BuiltinPluginProvider().execute(descriptor, context: context).execution
        }
        let stateRoot = context.pluginsRoot ?? descriptor.directoryURL.deletingLastPathComponent()
        guard descriptor.isEnabled && isPluginEnabled(id: descriptor.id, in: stateRoot) else {
            throw LumakeyError.pluginExecutionFailed("插件 '\(descriptor.displayName)' 当前已禁用")
        }
        let latestGrants = descriptor.grantedCapabilities.union(grantedCapabilities(id: descriptor.id, in: stateRoot))
            .intersection(Set(descriptor.declaredCapabilities))
        let latestRevokedScopes = descriptor.revokedResourceScopes.union(revokedResourceScopes(id: descriptor.id, in: stateRoot))
        let effectiveScopes = Set(descriptor.declaredResourceScopes).subtracting(latestRevokedScopes)

        var bridgeServer: PluginHostBridgeServer?
        let activeLocale = L10n.current
        let activeTheme = AppThemeConfig.load().selectedTheme
        let dataDir = PluginDataPaths.ensureDataDirectory(for: descriptor.id, pluginsRoot: stateRoot)
        let isolatedTmpDir = PluginDataPaths.ensureIsolatedTmpDirectory(for: descriptor.id, pluginsRoot: stateRoot)
        defer { try? FileManager.default.removeItem(at: isolatedTmpDir) }

        var pluginVars: [String: String] = [
            "LUMAKEY_LOCALE": activeLocale.rawValue,
            "LUMAKEY_THEME": activeTheme.rawValue
        ]
        if let dataDir { pluginVars["LUMAKEY_DATA_DIR"] = dataDir.path }
        if !descriptor.declaredCapabilities.isEmpty {
            let server = try PluginHostBridgeServer(descriptor: descriptor, grantedCapabilities: latestGrants, hostContext: context.hostContext)
            bridgeServer = server
            pluginVars["LUMAKEY_BRIDGE_SOCK"] = server.socketPath
            pluginVars["LUMAKEY_BRIDGE_TOKEN"] = server.token
        }
        defer { bridgeServer?.stop() }

        let entryURL = descriptor.directoryURL.appendingPathComponent(descriptor.manifest.entry).standardizedFileURL
        let inputData = try buildStdinContextData(
            for: descriptor, query: context.query, clipboardText: context.clipboardText,
            contextPayload: context.contextPayload, bridgeSocketPath: bridgeServer?.socketPath,
            bridgeToken: bridgeServer?.token, grantedCapabilities: latestGrants,
            dataDirectoryURL: dataDir, configOverrides: context.configOverrides,
            locale: activeLocale, theme: activeTheme, in: stateRoot
        )
        let cleanEnv = PluginSandboxProfileBuilder.sanitizedEnvironment(
            pluginVariables: pluginVars, isolatedTmpDirectory: isolatedTmpDir
        )
        let execCmd = PluginSandboxProfileBuilder.prepareExecutionCommand(
            entryURL: entryURL, arguments: context.arguments, descriptor: descriptor,
            grantedScopes: effectiveScopes, dataDirectory: dataDir, isolatedTmpDirectory: isolatedTmpDir,
            stateRoot: stateRoot, bridgeSocketPath: bridgeServer?.socketPath
        )
        let result = try ProcessSupervisor.shared.run(
            executableURL: execCmd.executableURL, arguments: execCmd.arguments,
            currentDirectoryURL: descriptor.directoryURL, environment: cleanEnv,
            inheritHostEnvironment: false, stdinData: inputData,
            timeoutSeconds: context.timeoutSeconds, maxOutputBytes: 131_072,
            cancellationHandle: context.cancellationHandle
        )
        if result.wasCancelled {
            if descriptor.declaredCapabilities.contains(.audio) { _ = PluginAudioBridgePlayer.shared.stop() }
            throw CancellationError()
        }
        if result.timedOut {
            throw LumakeyError.pluginExecutionFailed("插件进程执行超时（\(Int(context.timeoutSeconds))s）已被自动终止")
        }
        if result.exitCode == 0,
           let parsed = PluginViewPayload.parse(from: result.stdout),
           let summary = parsed.effect?.statusSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            PluginDataInspector.saveRuntimeStatus(
                PluginRuntimeStatus(summary: summary, badge: parsed.effect?.statusBadge),
                for: descriptor.id, in: stateRoot
            )
        }
        return PluginExecutionResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, durationMs: result.durationMs)
    }

    public static func runPluginSync(
        _ descriptor: PluginDescriptor,
        query: String,
        clipboardText: String = "",
        arguments: [String] = [],
        contextPayload: PluginContextPayload? = nil,
        configOverrides: [String: String]? = nil,
        hostContext: PluginBridgeHostContext = .default,
        in rootDir: URL? = nil,
        timeoutSeconds: Double = 8.0
    ) throws -> PluginResolvedOutput {
        let context = PluginExecutionContext(
            query: query, arguments: arguments, clipboardText: clipboardText,
            contextPayload: contextPayload, configOverrides: configOverrides,
            hostContext: hostContext, pluginsRoot: rootDir, timeoutSeconds: timeoutSeconds
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
        contextPayload: PluginContextPayload? = nil,
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
                    contextPayload: contextPayload, configOverrides: configOverrides,
                    hostContext: hostContext, pluginsRoot: rootDir,
                    timeoutSeconds: timeoutSeconds, cancellationHandle: cancelHandle
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
