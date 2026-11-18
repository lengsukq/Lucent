import Darwin
import Foundation

public struct PluginContextInfo: Sendable, Equatable {
    public let kind: String
    public let source: String
    public let text: String?
    public let url: String?
    public let filePaths: [String]

    public init(kind: String, source: String, text: String? = nil, url: String? = nil, filePaths: [String] = []) {
        self.kind = kind
        self.source = source
        self.text = text
        self.url = url
        self.filePaths = filePaths
    }

    public var primaryFilePath: String? {
        filePaths.first { !$0.isEmpty }
    }
}

public struct PluginInput: @unchecked Sendable {
    public let rawJSON: [String: Any]
    public let query: String
    public let mode: String
    public let locale: String
    public let theme: String
    public let config: [String: String]
    public let clipboard: String
    public let dataDir: String
    public let context: PluginContextInfo?
    public let bridgeSocket: String
    public let bridgeToken: String
    public let grantedCapabilities: Set<String>
    public let arguments: [String]

    public var isEnglish: Bool {
        locale.lowercased().hasPrefix("en")
    }

    public init(
        rawJSON: [String: Any] = [:],
        query: String = "",
        mode: String = "view",
        locale: String = "zh-Hans",
        theme: String = "liquidGlass",
        config: [String: String] = [:],
        clipboard: String = "",
        dataDir: String = "",
        context: PluginContextInfo? = nil,
        bridgeSocket: String = "",
        bridgeToken: String = "",
        grantedCapabilities: Set<String> = [],
        arguments: [String] = []
    ) {
        self.rawJSON = rawJSON
        self.query = query
        self.mode = mode
        self.locale = locale
        self.theme = theme
        self.config = config
        self.clipboard = clipboard
        self.dataDir = dataDir
        self.context = context
        self.bridgeSocket = bridgeSocket
        self.bridgeToken = bridgeToken
        self.grantedCapabilities = grantedCapabilities
        self.arguments = arguments
    }

    public static func read(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        stdinData: Data? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PluginInput {
        let data: Data
        if let stdinData {
            data = stdinData
        } else if Darwin.isatty(STDIN_FILENO) != 0 {
            data = Data()
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }

        let top: [String: Any]
        if !data.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            top = parsed
        } else {
            top = [:]
        }

        let query = (top["query"] as? String) ?? ""
        let mode = (top["mode"] as? String) ?? "view"
        let locale = (top["locale"] as? String)
            ?? environment["LUMAKEY_LOCALE"]
            ?? "zh-Hans"
        let theme = (top["theme"] as? String)
            ?? environment["LUMAKEY_THEME"]
            ?? "liquidGlass"

        var cfg: [String: String] = [:]
        if let rawCfg = top["config"] as? [String: Any] {
            for (k, v) in rawCfg {
                if let s = v as? String {
                    cfg[k] = s
                } else if let n = v as? NSNumber {
                    cfg[k] = n.stringValue
                }
            }
        }

        let clipboard = (top["clipboard"] as? String) ?? ""
        let dataDir = (top["dataDir"] as? String)
            ?? environment["LUMAKEY_DATA_DIR"]
            ?? ""

        var ctxInfo: PluginContextInfo? = nil
        if let rawCtx = top["context"] as? [String: Any] {
            let paths = (rawCtx["filePaths"] as? [String]) ?? []
            ctxInfo = PluginContextInfo(
                kind: (rawCtx["kind"] as? String) ?? "",
                source: (rawCtx["source"] as? String) ?? "",
                text: rawCtx["text"] as? String,
                url: rawCtx["url"] as? String,
                filePaths: paths
            )
        }

        let rawBridge = top["bridge"] as? [String: Any]
        let sock = (rawBridge?["socket"] as? String)
            ?? environment["LUMAKEY_BRIDGE_SOCK"]
            ?? ""
        let tok = (rawBridge?["token"] as? String)
            ?? environment["LUMAKEY_BRIDGE_TOKEN"]
            ?? ""
        let caps = Set((rawBridge?["grantedCapabilities"] as? [String]) ?? [])

        return PluginInput(
            rawJSON: top,
            query: query,
            mode: mode,
            locale: locale,
            theme: theme,
            config: cfg,
            clipboard: clipboard,
            dataDir: dataDir,
            context: ctxInfo,
            bridgeSocket: sock,
            bridgeToken: tok,
            grantedCapabilities: caps,
            arguments: arguments
        )
    }

    public func pick(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    public func cfgString(_ key: String, default defaultValue: String = "") -> String {
        guard let v = config[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            return defaultValue
        }
        return v
    }

    public func cfgBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let raw = config[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return defaultValue
        }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return defaultValue
    }

    public func cfgInt(_ key: String, default defaultValue: Int = 0, min minVal: Int? = nil, max maxVal: Int? = nil) -> Int {
        var val = config[key].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? config[key].flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)).map(Int.init) }
            ?? defaultValue
        if let minVal { val = Swift.max(minVal, val) }
        if let maxVal { val = Swift.min(maxVal, val) }
        return val
    }

    public func cfgDouble(_ key: String, default defaultValue: Double = 0, min minVal: Double? = nil, max maxVal: Double? = nil) -> Double {
        var val = config[key].flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? defaultValue
        if let minVal { val = Swift.max(minVal, val) }
        if let maxVal { val = Swift.min(maxVal, val) }
        return val
    }

    public func cfgExpandedPath(_ key: String, default defaultValue: String = "") -> String {
        let raw = cfgString(key, default: defaultValue)
        guard !raw.isEmpty else { return "" }
        return (raw as NSString).expandingTildeInPath
    }

    public func hasFlag(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    public func optionValue(after flag: String) -> String? {
        guard let idx = arguments.firstIndex(of: flag), idx + 1 < arguments.count else {
            return nil
        }
        return arguments[idx + 1]
    }
}
