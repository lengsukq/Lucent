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

public struct NotificationSpec: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var body: String
    public var sound: Bool?

    public init(title: String, subtitle: String? = nil, body: String, sound: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.sound = sound
    }
}

public struct WindowLaunchSpec: Codable, Sendable, Equatable {
    public var windowID: String?
    public var title: String?
    public var htmlPath: String?
    public var html: String?
    public var width: Int?
    public var height: Int?
    public var minWidth: Int?
    public var minHeight: Int?
    public var resizable: Bool?
    public var chrome: String?
    public var transparent: Bool?
    public var pinOnTop: Bool?
    public var clickThrough: Bool?
    public var opacity: Double?
    public var x: Int?
    public var y: Int?
    public var initialStateJSON: String?

    public init(
        windowID: String? = nil,
        title: String? = nil,
        htmlPath: String? = nil,
        html: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        resizable: Bool? = nil,
        chrome: String? = nil,
        transparent: Bool? = nil,
        pinOnTop: Bool? = nil,
        clickThrough: Bool? = nil,
        opacity: Double? = nil,
        x: Int? = nil,
        y: Int? = nil,
        initialStateJSON: String? = nil
    ) {
        self.windowID = windowID
        self.title = title
        self.htmlPath = htmlPath
        self.html = html
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.resizable = resizable
        self.chrome = chrome
        self.transparent = transparent
        self.pinOnTop = pinOnTop
        self.clickThrough = clickThrough
        self.opacity = opacity
        self.x = x
        self.y = y
        self.initialStateJSON = initialStateJSON
    }
}

public struct PostActionEffect: Codable, Sendable, Equatable {
    public var toast: String?
    public var closeOverlay: Bool?
    public var reloadSearchIndex: Bool?
    public var statusSummary: String?
    public var statusBadge: String?
    public var openReaderPath: String?
    public var openImagePath: String?
    public var pinImagePath: String?
    public var openFloatingPanel: Bool?
    public var floatingPanelPinOnTop: Bool?
    public var floatingPanelIntervalSeconds: Int?
    public var floatingPanelArgs: [String]?
    public var openWindow: WindowLaunchSpec?
    public var pasteText: String?
    public var notification: NotificationSpec?

    public init(
        toast: String? = nil,
        closeOverlay: Bool? = nil,
        reloadSearchIndex: Bool? = nil,
        statusSummary: String? = nil,
        statusBadge: String? = nil,
        openReaderPath: String? = nil,
        openImagePath: String? = nil,
        pinImagePath: String? = nil,
        openFloatingPanel: Bool? = nil,
        floatingPanelPinOnTop: Bool? = nil,
        floatingPanelIntervalSeconds: Int? = nil,
        floatingPanelArgs: [String]? = nil,
        openWindow: WindowLaunchSpec? = nil,
        pasteText: String? = nil,
        notification: NotificationSpec? = nil
    ) {
        self.toast = toast
        self.closeOverlay = closeOverlay
        self.reloadSearchIndex = reloadSearchIndex
        self.statusSummary = statusSummary
        self.statusBadge = statusBadge
        self.openReaderPath = openReaderPath
        self.openImagePath = openImagePath
        self.pinImagePath = pinImagePath
        self.openFloatingPanel = openFloatingPanel
        self.floatingPanelPinOnTop = floatingPanelPinOnTop
        self.floatingPanelIntervalSeconds = floatingPanelIntervalSeconds
        self.floatingPanelArgs = floatingPanelArgs
        self.openWindow = openWindow
        self.pasteText = pasteText
        self.notification = notification
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

public struct SearchIndexItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var url: String?
    public var copyText: String?
    public var icon: String?
    public var tintColor: String?
    public var badge: String?
    public var tags: [String]?
    public var pinned: Bool?
    public var priority: Int?
    public var commandArgs: [String]?
    public var includeInGlobalSearch: Bool?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        url: String? = nil,
        copyText: String? = nil,
        icon: String? = nil,
        tintColor: String? = nil,
        badge: String? = nil,
        tags: [String]? = nil,
        pinned: Bool? = nil,
        priority: Int? = nil,
        commandArgs: [String]? = nil,
        includeInGlobalSearch: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.copyText = copyText
        self.icon = icon
        self.tintColor = tintColor
        self.badge = badge
        self.tags = tags
        self.pinned = pinned
        self.priority = priority
        self.commandArgs = commandArgs
        self.includeInGlobalSearch = includeInGlobalSearch
    }
}

public struct SearchIndexEnvelope: Codable, Sendable, Equatable {
    public var items: [SearchIndexItem]

    public init(items: [SearchIndexItem]) {
        self.items = items
    }
}

public struct RuntimeStatusFile: Codable, Sendable, Equatable {
    public var summary: String
    public var badge: String?

    public init(summary: String, badge: String? = nil) {
        self.summary = summary
        self.badge = badge
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
