import Foundation

public struct PluginExecutionContext: @unchecked Sendable {
    public let query: String
    public let arguments: [String]
    public let clipboardText: String
    public let contextPayload: PluginContextPayload?
    public let configOverrides: [String: String]?
    public let hostContext: PluginBridgeHostContext
    public let pluginsRoot: URL?
    public let timeoutSeconds: Double
    public let cancellationHandle: ProcessCancellationHandle?

    public init(
        query: String,
        arguments: [String] = [],
        clipboardText: String = "",
        contextPayload: PluginContextPayload? = nil,
        configOverrides: [String: String]? = nil,
        hostContext: PluginBridgeHostContext = .default,
        pluginsRoot: URL? = nil,
        timeoutSeconds: Double = 8.0,
        cancellationHandle: ProcessCancellationHandle? = nil
    ) {
        self.query = query
        self.arguments = arguments
        self.clipboardText = clipboardText
        self.contextPayload = contextPayload
        self.configOverrides = configOverrides
        self.hostContext = hostContext
        self.pluginsRoot = pluginsRoot
        self.timeoutSeconds = timeoutSeconds
        self.cancellationHandle = cancellationHandle
    }
}

public protocol PluginExecutionProvider: Sendable {
    func supports(_ descriptor: PluginDescriptor) -> Bool
    func execute(_ descriptor: PluginDescriptor, context: PluginExecutionContext) throws -> PluginResolvedOutput
}

public struct BuiltinPluginProvider: PluginExecutionProvider {
    public init() {}

    public func supports(_ descriptor: PluginDescriptor) -> Bool {
        descriptor.isBuiltin
    }

    public func execute(_ descriptor: PluginDescriptor, context: PluginExecutionContext) throws -> PluginResolvedOutput {
        guard let resolved = PluginBuiltinRegistry.runBuiltin(
            id: descriptor.id,
            query: context.query,
            arguments: context.arguments
        ) else {
            throw LumakeyError.pluginInvalid("未知内置插件：\(descriptor.id)")
        }
        return resolved
    }
}

public struct ExternalScriptPluginProvider: PluginExecutionProvider {
    public init() {}

    public func supports(_ descriptor: PluginDescriptor) -> Bool {
        !descriptor.isBuiltin
    }

    public func execute(_ descriptor: PluginDescriptor, context: PluginExecutionContext) throws -> PluginResolvedOutput {
        let exec = try PluginSystem.runExternalPlugin(descriptor, context: context)
        return PluginResolvedOutput(descriptor: descriptor, execution: exec)
    }
}
