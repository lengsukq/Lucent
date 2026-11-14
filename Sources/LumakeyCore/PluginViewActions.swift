import Foundation

public enum PluginActionStyle: String, Codable, Sendable, Hashable {
    case primary
    case secondary
    case destructive
}

public struct PluginActionPromptField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let type: PluginConfigFieldType?
    public let defaultValue: String?
    public let placeholder: String?
    public let options: [String]?
    public let required: Bool?

    public init(
        key: String,
        label: String,
        type: PluginConfigFieldType? = nil,
        defaultValue: String? = nil,
        placeholder: String? = nil,
        options: [String]? = nil,
        required: Bool? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.options = options
        self.required = required
    }
}

public struct PluginViewAction: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let style: PluginActionStyle?
    public let commandArgs: [String]
    public let confirmMessage: String?
    public let promptFields: [PluginActionPromptField]?

    public init(
        id: String,
        label: String,
        style: PluginActionStyle? = nil,
        commandArgs: [String],
        confirmMessage: String? = nil,
        promptFields: [PluginActionPromptField]? = nil
    ) {
        self.id = id
        self.label = label
        self.style = style
        self.commandArgs = commandArgs
        self.confirmMessage = confirmMessage
        self.promptFields = promptFields
    }
}

public struct PluginPostActionEffect: Codable, Sendable, Hashable {
    public let toast: String?
    public let closeOverlay: Bool?
    public let reloadSearchIndex: Bool?

    public init(toast: String? = nil, closeOverlay: Bool? = nil, reloadSearchIndex: Bool? = nil) {
        self.toast = toast
        self.closeOverlay = closeOverlay
        self.reloadSearchIndex = reloadSearchIndex
    }
}

public enum PluginViewParseResult: Sendable, Hashable {
    case structured(PluginViewPayload)
    case plainText(reason: String, raw: String)

    public var payload: PluginViewPayload? {
        if case .structured(let p) = self { return p }
        return nil
    }

    public var diagnosticReason: String? {
        if case .plainText(let reason, _) = self { return reason }
        return nil
    }
}
