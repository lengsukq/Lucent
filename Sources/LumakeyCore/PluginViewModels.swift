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
    public let explicitID: String?
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let badge: String?
    public let copyText: String?
    public let openURL: String?
    public let commandArgs: [String]?
    public let actions: [PluginViewAction]?

    public var id: String {
        if let explicitID, !explicitID.isEmpty { return explicitID }
        let cmdPart = (commandArgs ?? []).joined(separator: ",")
        let actPart = (actions ?? []).map { "\($0.id):\($0.commandArgs.joined(separator: ","))" }.joined(separator: ";")
        return "\(title)|\(subtitle ?? "")|\(badge ?? "")|\(copyText ?? "")|\(openURL ?? "")|\(cmdPart)|\(actPart)"
    }

    enum CodingKeys: String, CodingKey {
        case explicitID = "id"
        case title, subtitle, icon, badge, copyText, openURL, commandArgs, actions
    }

    public init(
        explicitID: String? = nil,
        title: String, subtitle: String? = nil, icon: String? = nil, badge: String? = nil,
        copyText: String? = nil, openURL: String? = nil, commandArgs: [String]? = nil,
        actions: [PluginViewAction]? = nil
    ) {
        self.explicitID = explicitID
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.badge = badge
        self.copyText = copyText; self.openURL = openURL
        self.commandArgs = commandArgs; self.actions = actions
    }
}

public struct PluginViewPayload: Codable, Sendable, Equatable, Hashable {
    public let schemaVersion: Int?
    public let title: String
    public let subtitle: String?
    public let badge: String?
    public let markdown: String?
    public let metrics: [PluginKeyValue]?
    public let items: [PluginViewItem]?
    public let effect: PluginPostActionEffect?

    public init(
        schemaVersion: Int? = nil,
        title: String, subtitle: String? = nil, badge: String? = nil,
        markdown: String? = nil, metrics: [PluginKeyValue]? = nil,
        items: [PluginViewItem]? = nil, effect: PluginPostActionEffect? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.title = title; self.subtitle = subtitle; self.badge = badge
        self.markdown = markdown; self.metrics = metrics
        self.items = items; self.effect = effect
    }

    public static func parse(from rawOutput: String) -> PluginViewPayload? {
        parseDetailed(from: rawOutput).payload
    }

    public static func parseDetailed(from rawOutput: String) -> PluginViewParseResult {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .plainText(reason: "stdout 输出为空", raw: rawOutput)
        }
        guard trimmed.first == "{", trimmed.last == "}" else {
            return .plainText(reason: "stdout 包含非 JSON 前/后缀文本，已降级为纯文本展示", raw: rawOutput)
        }
        guard let data = trimmed.data(using: .utf8) else {
            return .plainText(reason: "stdout UTF-8 编码无效", raw: rawOutput)
        }
        do {
            let payload = try JSONDecoder().decode(PluginViewPayload.self, from: data)
            guard !payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .plainText(reason: "view JSON 缺少非空 title 字段", raw: rawOutput)
            }
            return .structured(payload)
        } catch {
            return .plainText(reason: "view JSON 解析失败：\(error.localizedDescription)", raw: rawOutput)
        }
    }
}

public struct PluginResolvedOutput: Sendable, Equatable, Hashable {
    public let pluginID: String
    public let pluginName: String
    public let mode: PluginMode
    public let execution: PluginExecutionResult
    public let viewPayload: PluginViewPayload?
    public let viewParseDiagnostic: String?
    public let plainText: String
    public var isStructuredView: Bool { viewPayload != nil }

    public init(descriptor: PluginDescriptor, execution: PluginExecutionResult) {
        self.pluginID = descriptor.id
        self.pluginName = descriptor.manifest.name
        self.mode = descriptor.manifest.mode
        self.execution = execution
        if execution.exitCode == 0 {
            switch PluginViewPayload.parseDetailed(from: execution.stdout) {
            case .structured(let parsed):
                self.viewPayload = parsed
                self.viewParseDiagnostic = nil
                self.plainText = Self.summarize(parsed)
            case .plainText(let reason, _):
                self.viewPayload = nil
                self.viewParseDiagnostic = descriptor.manifest.mode == .view ? reason : nil
                self.plainText = execution.stdout.isEmpty ? execution.stderr : execution.stdout
            }
        } else {
            self.viewPayload = nil
            self.viewParseDiagnostic = nil
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
