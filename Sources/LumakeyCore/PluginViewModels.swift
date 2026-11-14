import Foundation

public struct PluginKeyValue: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(key):\(value)" }
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key; self.value = value
    }

    private enum CodingKeys: String, CodingKey { case key, label, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = (try? c.decode(String.self, forKey: .key))
            ?? (try? c.decode(String.self, forKey: .label))
            ?? ""
        self.value = try c.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(value, forKey: .value)
    }
}

public struct PluginViewItem: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(title)|\(subtitle ?? "")|\(copyText ?? "")|\(openURL ?? "")" }
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let badge: String?
    public let copyText: String?
    public let openURL: String?
    public let commandArgs: [String]?

    public init(
        title: String, subtitle: String? = nil, icon: String? = nil, badge: String? = nil,
        copyText: String? = nil, openURL: String? = nil, commandArgs: [String]? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.badge = badge
        self.copyText = copyText; self.openURL = openURL; self.commandArgs = commandArgs
    }
}

public struct PluginViewPayload: Codable, Sendable, Equatable, Hashable {
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let markdown: String?
    public let metrics: [PluginKeyValue]?
    public let items: [PluginViewItem]?

    public init(
        title: String, subtitle: String? = nil, badge: String? = nil,
        markdown: String? = nil, metrics: [PluginKeyValue]? = nil, items: [PluginViewItem]? = nil
    ) {
        self.title = title; self.subtitle = subtitle; self.badge = badge
        self.markdown = markdown; self.metrics = metrics; self.items = items
    }

    public static func parse(from rawOutput: String) -> PluginViewPayload? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}",
              let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PluginViewPayload.self, from: data),
              !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return payload
    }
}

public struct PluginResolvedOutput: Sendable, Equatable, Hashable {
    public let pluginID: String
    public let pluginName: String
    public let mode: PluginMode
    public let execution: PluginExecutionResult
    public let viewPayload: PluginViewPayload?
    public let plainText: String
    public var isStructuredView: Bool { viewPayload != nil }

    public init(descriptor: PluginDescriptor, execution: PluginExecutionResult) {
        self.pluginID = descriptor.id
        self.pluginName = descriptor.manifest.name
        self.mode = descriptor.manifest.mode
        self.execution = execution
        if execution.exitCode == 0, let parsed = PluginViewPayload.parse(from: execution.stdout) {
            self.viewPayload = parsed
            self.plainText = Self.summarize(parsed)
        } else {
            self.viewPayload = nil
            self.plainText = execution.stdout.isEmpty ? execution.stderr : execution.stdout
        }
    }

    private static func summarize(_ payload: PluginViewPayload) -> String {
        var lines: [String] = [payload.title]
        if let sub = payload.subtitle, !sub.isEmpty { lines.append(sub) }
        for m in payload.metrics ?? [] { lines.append("\(m.key): \(m.value)") }
        for item in payload.items ?? [] {
            lines.append("• \(item.title)" + (item.subtitle.map { " — \($0)" } ?? ""))
        }
        if let md = payload.markdown, !md.isEmpty { lines.append(md) }
        return lines.joined(separator: "\n")
    }
}
