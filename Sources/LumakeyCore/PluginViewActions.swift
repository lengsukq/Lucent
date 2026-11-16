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
    public let statusSummary: String?
    public let statusBadge: String?
    public let openReaderPath: String?
    public let openImagePath: String?
    public let pinImagePath: String?

    public init(
        toast: String? = nil,
        closeOverlay: Bool? = nil,
        reloadSearchIndex: Bool? = nil,
        statusSummary: String? = nil,
        statusBadge: String? = nil,
        openReaderPath: String? = nil,
        openImagePath: String? = nil,
        pinImagePath: String? = nil
    ) {
        self.toast = toast
        self.closeOverlay = closeOverlay
        self.reloadSearchIndex = reloadSearchIndex
        self.statusSummary = statusSummary
        self.statusBadge = statusBadge
        self.openReaderPath = openReaderPath
        self.openImagePath = openImagePath
        self.pinImagePath = pinImagePath
    }
}

public enum PluginDeepLinkTarget: Sendable, Hashable, Equatable {
    case settingsSection(String)
    case pluginSettings(String)
    case documentReader(URL)
    case imageViewer(URL, pinOnTop: Bool)
    case pinImage(URL)
}

public enum PluginDeepLinkParser {
    public static func parse(_ url: URL) -> PluginDeepLinkTarget? {
        guard url.scheme?.lowercased() == "lumakey", let host = url.host?.lowercased() else {
            return nil
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryMap = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let val = item.value, !val.isEmpty else { return nil }
            return (item.name, val)
        })

        switch host {
        case "settings":
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0] == "plugin" {
                return .pluginSettings(parts[1])
            }
            return .settingsSection(parts.first ?? "general")

        case "reader":
            if let rawPath = queryMap["path"] ?? (url.path.count > 1 ? url.path : nil) {
                let target = URL(fileURLWithPath: rawPath).standardizedFileURL
                guard FileManager.default.fileExists(atPath: target.path) else { return nil }
                return .documentReader(target)
            }
            if let md = queryMap["markdown"], !md.isEmpty {
                let rawTitle = (queryMap["title"] ?? "plugin-note")
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: "..", with: "")
                let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("lumakey-plugin-docs", isDirectory: true)
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let fileURL = tmpDir.appendingPathComponent("\(rawTitle).md")
                try? Data(md.utf8).write(to: fileURL, options: .atomic)
                return .documentReader(fileURL)
            }
            return nil

        case "image":
            guard let rawPath = queryMap["path"] ?? (url.path.count > 1 ? url.path : nil) else { return nil }
            let target = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: target.path) else { return nil }
            let pin = queryMap["pin"] == "1" || queryMap["pin"]?.lowercased() == "true"
            return .imageViewer(target, pinOnTop: pin)

        case "pin":
            guard let rawPath = queryMap["path"] ?? (url.path.count > 1 ? url.path : nil) else { return nil }
            let target = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: target.path) else { return nil }
            return .pinImage(target)

        default:
            return nil
        }
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
