import Foundation

public struct KeyValue: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct PromptField: Codable, Sendable, Equatable {
    public var key: String
    public var label: String
    public var type: String?
    public var defaultValue: String?
    public var placeholder: String?
    public var options: [String]?
    public var required: Bool?

    public init(
        key: String,
        label: String,
        type: String? = nil,
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

public struct ViewAction: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var style: String?
    public var commandArgs: [String]
    public var confirmMessage: String?
    public var promptFields: [PromptField]?

    public init(
        id: String,
        label: String,
        style: String? = nil,
        commandArgs: [String],
        confirmMessage: String? = nil,
        promptFields: [PromptField]? = nil
    ) {
        self.id = id
        self.label = label
        self.style = style
        self.commandArgs = commandArgs
        self.confirmMessage = confirmMessage
        self.promptFields = promptFields
    }
}

public struct ViewItem: Codable, Sendable, Equatable {
    public var id: String?
    public var title: String
    public var subtitle: String?
    public var icon: String?
    public var tintColor: String?
    public var badge: String?
    public var copyText: String?
    public var openURL: String?
    public var commandArgs: [String]?
    public var actions: [ViewAction]?

    public init(
        id: String? = nil,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tintColor: String? = nil,
        badge: String? = nil,
        copyText: String? = nil,
        openURL: String? = nil,
        commandArgs: [String]? = nil,
        actions: [ViewAction]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tintColor = tintColor
        self.badge = badge
        self.copyText = copyText
        self.openURL = openURL
        self.commandArgs = commandArgs
        self.actions = actions
    }
}

public struct ViewPayload: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var title: String
    public var subtitle: String?
    public var badge: String?
    public var markdown: String?
    public var metrics: [KeyValue]?
    public var items: [ViewItem]?
    public var effect: PostActionEffect?

    public init(
        schemaVersion: Int = 2,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        markdown: String? = nil,
        metrics: [KeyValue]? = nil,
        items: [ViewItem]? = nil,
        effect: PostActionEffect? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.markdown = markdown
        self.metrics = metrics
        self.items = items
        self.effect = effect
    }
}

public enum PluginOutput {
    public static func encodeJSON<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        var fmt: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]
        if pretty { fmt.insert(.prettyPrinted); fmt.insert(.sortedKeys) }
        encoder.outputFormatting = fmt
        return try encoder.encode(value)
    }

    public static func emit(_ payload: ViewPayload) {
        guard var data = try? encodeJSON(payload) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    public static func emitJSONObject(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return
        }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    public static func writeSearchIndex(_ items: [SearchIndexItem], to dataDir: String) {
        guard !dataDir.isEmpty else { return }
        let dirURL = URL(fileURLWithPath: dataDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let outURL = dirURL.appendingPathComponent("search-index.json")
        if let data = try? encodeJSON(SearchIndexEnvelope(items: items)) {
            try? data.write(to: outURL, options: .atomic)
        }
    }

    public static func writeRuntimeStatus(summary: String, badge: String? = nil, to dataDir: String) {
        guard !dataDir.isEmpty else { return }
        let dirURL = URL(fileURLWithPath: dataDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let outURL = dirURL.appendingPathComponent("status.json")
        if let data = try? encodeJSON(RuntimeStatusFile(summary: summary, badge: badge)) {
            try? data.write(to: outURL, options: .atomic)
        }
    }
}
