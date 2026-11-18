import CryptoKit
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
        key: String, label: String, type: PluginConfigFieldType? = nil,
        defaultValue: String? = nil, placeholder: String? = nil,
        options: [String]? = nil, required: Bool? = nil
    ) {
        self.key = key; self.label = label; self.type = type
        self.defaultValue = defaultValue; self.placeholder = placeholder
        self.options = options; self.required = required
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
        id: String, label: String, style: PluginActionStyle? = nil,
        commandArgs: [String], confirmMessage: String? = nil,
        promptFields: [PluginActionPromptField]? = nil
    ) {
        self.id = id; self.label = label; self.style = style
        self.commandArgs = commandArgs; self.confirmMessage = confirmMessage
        self.promptFields = promptFields
    }
}

public struct PluginNotificationPayload: Codable, Sendable, Hashable, Equatable {
    public let title: String
    public let subtitle: String?
    public let body: String
    public let sound: Bool?

    public init(title: String, subtitle: String? = nil, body: String, sound: Bool? = nil) {
        self.title = title; self.subtitle = subtitle; self.body = body; self.sound = sound
    }
}

public struct PluginFloatingPanelRequest: Codable, Sendable, Hashable, Equatable {
    public let pluginID: String
    public let pinOnTop: Bool
    public let refreshIntervalSeconds: Int
    public let arguments: [String]
    public let query: String

    public init(
        pluginID: String,
        pinOnTop: Bool = true,
        refreshIntervalSeconds: Int = 30,
        arguments: [String] = [],
        query: String = ""
    ) {
        self.pluginID = pluginID
        self.pinOnTop = pinOnTop
        self.refreshIntervalSeconds = Self.clampInterval(refreshIntervalSeconds)
        self.arguments = arguments
        self.query = query
    }

    public static func clampInterval(_ raw: Int?) -> Int {
        guard let raw else { return 30 }
        if raw <= 0 { return 0 }
        return min(max(raw, 5), 3600)
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
    public let openFloatingPanel: Bool?
    public let floatingPanelPinOnTop: Bool?
    public let floatingPanelIntervalSeconds: Int?
    public let floatingPanelArgs: [String]?
    public let openWindow: PluginWindowLaunchEffect?
    public let pasteText: String?
    public let notification: PluginNotificationPayload?

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
        openWindow: PluginWindowLaunchEffect? = nil,
        pasteText: String? = nil,
        notification: PluginNotificationPayload? = nil
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

public enum PluginDeepLinkTarget: Sendable, Hashable, Equatable {
    case settingsSection(String)
    case pluginSettings(String)
    case pluginPanel(PluginFloatingPanelRequest)
    case pluginCustomWindow(PluginCustomWindowSpec)
    case documentReader(URL)
    case imageViewer(URL, pinOnTop: Bool)
    case pinImage(URL)
}

public enum PluginDeepLinkParser {
    public static func parse(_ url: URL) -> PluginDeepLinkTarget? {
        guard url.scheme?.lowercased() == "lucent", let host = url.host?.lowercased() else {
            return nil
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []
        var queryMap: [String: String] = [:]
        for item in items {
            if let val = item.value, !val.isEmpty, queryMap[item.name] == nil {
                queryMap[item.name] = val
            }
        }

        switch host {
        case "settings":
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0] == "plugin" {
                return .pluginSettings(parts[1])
            }
            return .settingsSection(parts.first ?? "general")

        case "panel":
            let pathID = url.path.split(separator: "/").first.map(String.init)
            guard let rawID = (pathID ?? queryMap["id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                  PluginSystem.isSafePluginID(rawID) else {
                return nil
            }
            let rawPin = queryMap["pin"]?.lowercased()
            let pin = (rawPin == nil) ? true : (rawPin != "0" && rawPin != "false")
            let interval = PluginFloatingPanelRequest.clampInterval(queryMap["interval"].flatMap(Int.init))
            let repeatedArgs = items.filter { $0.name == "arg" }.compactMap { $0.value }.filter { !$0.isEmpty }
            return .pluginPanel(PluginFloatingPanelRequest(
                pluginID: rawID, pinOnTop: pin, refreshIntervalSeconds: interval,
                arguments: repeatedArgs, query: queryMap["query"] ?? ""
            ))

        case "window":
            guard let spec = PluginCustomWindowSpec.parseDeepLink(url: url, queryMap: queryMap) else {
                return nil
            }
            return .pluginCustomWindow(spec)

        case "reader":
            return parseReaderTarget(url: url, queryMap: queryMap)

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

    private static func parseReaderTarget(url: URL, queryMap: [String: String]) -> PluginDeepLinkTarget? {
        if let rawPath = queryMap["path"] ?? (url.path.count > 1 ? url.path : nil) {
            let target = URL(fileURLWithPath: rawPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: target.path) else { return nil }
            return .documentReader(target)
        }
        guard let md = queryMap["markdown"], !md.isEmpty else { return nil }
        let filtered = (queryMap["title"] ?? "plugin-note").unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
        let safeStem = String(String.UnicodeScalarView(filtered).prefix(48))
        let stem = safeStem.isEmpty ? "plugin-note" : safeStem
        let digest = SHA256.hash(data: Data(md.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("lucent-plugin-docs", isDirectory: true)
        if let vals = try? tmpDir.resourceValues(forKeys: [.isSymbolicLinkKey]), vals.isSymbolicLink == true {
            return nil
        }
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tmpDir.path)
        let fileURL = tmpDir.appendingPathComponent("\(stem)-\(digest).md", isDirectory: false)
        guard (try? Data(md.utf8).write(to: fileURL, options: .atomic)) != nil else { return nil }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return .documentReader(fileURL)
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
