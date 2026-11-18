import Foundation
import LucentFoundation

extension PluginSystem {
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
        timeoutSeconds: Double? = nil
    ) throws -> PluginExecutionResult {
        try runExternalPlugin(
            descriptor,
            context: PluginExecutionContext(
                query: query, arguments: arguments, clipboardText: clipboardText,
                contextPayload: contextPayload, hostContext: hostContext,
                pluginsRoot: rootDir,
                timeoutSeconds: timeoutSeconds ?? descriptor.manifest.effectiveTimeoutSeconds
            )
        )
    }

    static func runExternalPlugin(_ descriptor: PluginDescriptor, context: PluginExecutionContext) throws -> PluginExecutionResult {
        guard descriptor.isValid else {
            throw LucentError.pluginInvalid(descriptor.validationIssues.joined(separator: "；"))
        }
        if descriptor.isBuiltin {
            return try BuiltinPluginProvider().execute(descriptor, context: context).execution
        }
        let stateRoot = context.pluginsRoot ?? descriptor.directoryURL.deletingLastPathComponent()
        guard descriptor.isEnabled && isPluginEnabled(id: descriptor.id, in: stateRoot) else {
            throw LucentError.pluginExecutionFailed("插件 '\(descriptor.displayName)' 当前已禁用")
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
            "LUCENT_LOCALE": activeLocale.rawValue,
            "LUCENT_THEME": activeTheme.rawValue
        ]
        if let dataDir { pluginVars["LUCENT_DATA_DIR"] = dataDir.path }
        if !descriptor.declaredCapabilities.isEmpty {
            let server = try PluginHostBridgeServer(descriptor: descriptor, grantedCapabilities: latestGrants, hostContext: context.hostContext)
            bridgeServer = server
            pluginVars["LUCENT_BRIDGE_SOCK"] = server.socketPath
            pluginVars["LUCENT_BRIDGE_TOKEN"] = server.token
        } else if context.hostContext.progressReporter != nil,
                  let server = try? PluginHostBridgeServer(descriptor: descriptor, grantedCapabilities: latestGrants, hostContext: context.hostContext) {
            bridgeServer = server
            pluginVars["LUCENT_BRIDGE_SOCK"] = server.socketPath
            pluginVars["LUCENT_BRIDGE_TOKEN"] = server.token
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
            throw LucentError.pluginExecutionFailed("插件进程执行超时（\(Int(context.timeoutSeconds))s）已被自动终止")
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

    private static func resolveExecutionProvider(for descriptor: PluginDescriptor) throws -> any PluginExecutionProvider {
        let providers: [any PluginExecutionProvider] = [BuiltinPluginProvider(), ExternalScriptPluginProvider()]
        guard let provider = providers.first(where: { $0.supports(descriptor) }) else {
            throw LucentError.pluginInvalid("无可用插件执行器：\(descriptor.id)")
        }
        return provider
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
        timeoutSeconds: Double? = nil
    ) throws -> PluginResolvedOutput {
        let context = PluginExecutionContext(
            query: query, arguments: arguments, clipboardText: clipboardText,
            contextPayload: contextPayload, configOverrides: configOverrides,
            hostContext: hostContext, pluginsRoot: rootDir,
            timeoutSeconds: timeoutSeconds ?? descriptor.manifest.effectiveTimeoutSeconds
        )
        return try resolveExecutionProvider(for: descriptor).execute(descriptor, context: context)
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
        timeoutSeconds: Double? = nil
    ) async throws -> PluginResolvedOutput {
        let cancelHandle = ProcessCancellationHandle()
        let resolvedTimeout = timeoutSeconds ?? descriptor.manifest.effectiveTimeoutSeconds
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                let context = PluginExecutionContext(
                    query: query, arguments: arguments, clipboardText: clipboardText,
                    contextPayload: contextPayload, configOverrides: configOverrides,
                    hostContext: hostContext, pluginsRoot: rootDir,
                    timeoutSeconds: resolvedTimeout, cancellationHandle: cancelHandle
                )
                return try resolveExecutionProvider(for: descriptor).execute(descriptor, context: context)
            }.value
        } onCancel: {
            cancelHandle.cancel()
        }
    }
}
