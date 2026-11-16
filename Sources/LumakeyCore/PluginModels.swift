import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable, CaseIterable {
    case script, view
}

public enum PluginKind: String, Codable, Sendable, Hashable {
    case builtin, external
}

public enum PluginCapability: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case clipboard, selection, audio, ocr, everythingSearch, displayInfo, systemControl, lumaLinkStatus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clipboard: L10n.pick("剪贴板读写", "Clipboard Read/Write")
        case .selection: L10n.pick("跨应用选中文本读取", "Frontmost Text Selection")
        case .audio: L10n.pick("宿主音频与语音朗读", "Host Audio & Speech")
        case .ocr: L10n.pick("离线 Vision OCR", "Offline Vision OCR")
        case .everythingSearch: L10n.pick("全盘文件索引检索", "Disk File Index Search")
        case .displayInfo: L10n.pick("显示器与分辨率信息", "Display & Resolution Info")
        case .systemControl: L10n.pick("系统音量与防休眠控制", "Volume & Caffeine Control")
        case .lumaLinkStatus: L10n.pick("LumaLink 远控状态", "LumaLink Status")
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: L10n.pick("通过宿主桥读取或写入系统剪贴板文本", "Read or write system clipboard text via Host Bridge")
        case .selection: L10n.pick("复用宿主辅助功能权限读取当前前台应用选中的文本", "Read selected text in the frontmost app via host Accessibility")
        case .audio: L10n.pick("复用宿主音频引擎播放本地音频文件或执行系统语音朗读", "Play local audio files or run macOS speech synthesis")
        case .ocr: L10n.pick("复用宿主 VisionService 离线识别图片中英文字与条码", "Offline CJK/English OCR & barcode detection via VisionService")
        case .everythingSearch: L10n.pick("复用宿主内存索引按 DSL 极速检索全盘与外置盘文件", "Query the in-memory file index across local & external drives")
        case .displayInfo: L10n.pick("读取活跃显示器列表、当前模式与支持的分辨率", "Inspect active displays, current modes & supported resolutions")
        case .systemControl: L10n.pick("读取音量/静音/防休眠状态并执行安全级调节", "Inspect and adjust system volume, mute & sleep-prevention")
        case .lumaLinkStatus: L10n.pick("读取 LumaLink 监听端口、连接数与 RDP 引擎状态（脱敏）", "Read redacted LumaLink port, connection count & RDP state")
        }
    }

    public var symbolName: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .selection: "text.cursor"
        case .audio: "speaker.wave.3.fill"
        case .ocr: "text.viewfinder"
        case .everythingSearch: "magnifyingglass"
        case .displayInfo: "display"
        case .systemControl: "speaker.wave.2.fill"
        case .lumaLinkStatus: "ipad.and.iphone"
        }
    }

    public var tccNote: String {
        L10n.pick("经临时 Host Bridge 复用 Lumakey 宿主权限 · 默认关闭", "Reuses Lumakey host permissions via ephemeral Host Bridge · Off by default")
    }
}

public struct BuiltinPluginMetadata: Sendable, Hashable {
    public let categoryBadge: String
    public let requiredPermissions: [LumakeyPermission]
    public let settingsTarget: String
    public let statusSummary: String

    public var requiredTCCPermissions: [String] { requiredPermissions.map(\.title) }

    public init(
        categoryBadge: String = "BUILTIN",
        requiredPermissions: [LumakeyPermission],
        settingsTarget: String,
        statusSummary: String
    ) {
        self.categoryBadge = categoryBadge; self.requiredPermissions = requiredPermissions
        self.settingsTarget = settingsTarget; self.statusSummary = statusSummary
    }
}

public enum PluginConfigFieldType: String, Codable, Sendable, Hashable, CaseIterable {
    case text, secret, boolean, select, number, path, directory, tags
}

public struct PluginConfigField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let type: PluginConfigFieldType
    public let control: PluginConfigControlStyle?
    public let defaultValue: String?
    public let placeholder: String?
    public let options: [String]?
    public let required: Bool?
    public let section: String?
    public let helpText: String?
    public let minValue: Double?
    public let maxValue: Double?
    public let stepValue: Double?

    public init(
        key: String, label: String, type: PluginConfigFieldType = .text,
        control: PluginConfigControlStyle? = nil, defaultValue: String? = nil,
        placeholder: String? = nil, options: [String]? = nil, required: Bool? = nil,
        section: String? = nil, helpText: String? = nil,
        minValue: Double? = nil, maxValue: Double? = nil, stepValue: Double? = nil
    ) {
        self.key = key; self.label = label; self.type = type; self.control = control
        self.defaultValue = defaultValue; self.placeholder = placeholder
        self.options = options; self.required = required
        self.section = section; self.helpText = helpText
        self.minValue = minValue; self.maxValue = maxValue; self.stepValue = stepValue
    }
}

public struct PluginManifest: Codable, Sendable, Hashable {
    public let schemaVersion: Int?
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let mode: PluginMode
    public let keywords: [String]
    public let entry: String
    public let author: String?
    public let icon: String?
    public let accentColor: String?
    public let categoryTag: String?
    public let hotkey: String?
    public let config: [PluginConfigField]?
    public let capabilities: [String]?
    public let resourceScopes: [String]?
    public let accepts: [String]?
    public let refreshIntervalSeconds: Int?
    public let commands: [PluginCommandSpec]?
    public let locales: [String: PluginLocaleStrings]?

    public var declaredCapabilities: [PluginCapability] {
        var seen = Set<PluginCapability>()
        return (capabilities ?? []).compactMap { raw in
            guard let cap = PluginCapability(rawValue: raw), seen.insert(cap).inserted else { return nil }
            return cap
        }
    }

    public var declaredResourceScopes: [PluginResourceScope] {
        var seen = Set<PluginResourceScope>()
        return (resourceScopes ?? []).compactMap { raw in
            guard let scope = PluginResourceScope(rawValue: raw), seen.insert(scope).inserted else { return nil }
            return scope
        }
    }

    public var declaredContextKinds: [PluginContextKind] {
        var seen = Set<PluginContextKind>()
        return (accepts ?? []).compactMap { raw in
            guard let kind = PluginContextKind(rawValue: raw), seen.insert(kind).inserted else { return nil }
            return kind
        }
    }

    public init(
        schemaVersion: Int? = nil, id: String, name: String, version: String, description: String,
        mode: PluginMode, keywords: [String], entry: String, author: String? = nil,
        icon: String? = nil, accentColor: String? = nil, categoryTag: String? = nil,
        hotkey: String? = nil, config: [PluginConfigField]? = nil,
        capabilities: [String]? = nil, resourceScopes: [String]? = nil,
        accepts: [String]? = nil, refreshIntervalSeconds: Int? = nil,
        commands: [PluginCommandSpec]? = nil, locales: [String: PluginLocaleStrings]? = nil
    ) {
        self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.version = version; self.description = description; self.mode = mode
        self.keywords = keywords; self.entry = entry; self.author = author; self.icon = icon
        self.accentColor = accentColor; self.categoryTag = categoryTag; self.hotkey = hotkey
        self.config = config; self.capabilities = capabilities; self.resourceScopes = resourceScopes
        self.accepts = accepts; self.refreshIntervalSeconds = refreshIntervalSeconds
        self.commands = commands; self.locales = locales
    }
}

public struct PluginInstanceState: Codable, Sendable, Hashable, Equatable {
    public var isEnabled: Bool
    public var configValues: [String: String]
    public var grantedCapabilities: [String]
    public var overrides: PluginUserOverrides

    enum CodingKeys: String, CodingKey { case isEnabled, configValues, grantedCapabilities, overrides }

    public init(
        isEnabled: Bool = true, configValues: [String: String] = [:],
        grantedCapabilities: [String] = [], overrides: PluginUserOverrides = PluginUserOverrides()
    ) {
        self.isEnabled = isEnabled; self.configValues = configValues
        self.grantedCapabilities = grantedCapabilities; self.overrides = overrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.configValues = try c.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
        self.grantedCapabilities = try c.decodeIfPresent([String].self, forKey: .grantedCapabilities) ?? []
        self.overrides = try c.decodeIfPresent(PluginUserOverrides.self, forKey: .overrides) ?? PluginUserOverrides()
    }
}

public struct PluginStateSnapshot: Codable, Sendable, Hashable, Equatable {
    public var schemaVersion: Int
    public var plugins: [String: PluginInstanceState]

    public init(schemaVersion: Int = 3, plugins: [String: PluginInstanceState] = [:]) {
        self.schemaVersion = schemaVersion; self.plugins = plugins
    }
}

public struct PluginDescriptor: Identifiable, Sendable, Hashable {
    public let id: String
    public let directoryURL: URL
    public let manifest: PluginManifest
    public let validationIssues: [String]
    public let nameLowercased: String
    public let descriptionLowercased: String
    public let localizedSearchPoolLowercased: String
    public let keywordsLowercased: [String]
    public let effectiveKeywords: [String]
    public let effectiveKeywordsLowercased: [String]
    public let isEnabled: Bool
    public let userConfig: [String: String]
    public let kind: PluginKind
    public let grantedCapabilities: Set<PluginCapability>
    public let overrides: PluginUserOverrides
    public let builtinMetadata: BuiltinPluginMetadata?
    public let runtimeStatus: PluginRuntimeStatus?

    public var isValid: Bool { validationIssues.isEmpty }
    public var isBuiltin: Bool { kind == .builtin }
    public var declaredCapabilities: [PluginCapability] { manifest.declaredCapabilities }
    public var declaredResourceScopes: [PluginResourceScope] { manifest.declaredResourceScopes }
    public var declaredContextKinds: [PluginContextKind] { manifest.declaredContextKinds }
    public var declaredCommands: [PluginCommandSpec] { manifest.commands ?? [] }
    public var declaredPermissions: [LumakeyPermission] { PluginPermissionAudit.declaredPermissions(for: self) }
    public var isPureSandbox: Bool { declaredPermissions.isEmpty }
    public var pinnedInOverlay: Bool { overrides.pinnedInOverlay }
    public var includeInGlobalSearch: Bool { overrides.includeInGlobalSearch }
    public var showInSettingsSidebar: Bool { overrides.showInSettingsSidebar }
    public var effectiveRankingBoost: Int { overrides.usageScoreBoost() }
    public var effectiveHotKey: String? {
        if let custom = overrides.customHotKey { return custom.isEmpty ? nil : custom }
        return manifest.hotkey
    }
    public func isCapabilityGranted(_ capability: PluginCapability) -> Bool {
        declaredCapabilities.contains(capability) && grantedCapabilities.contains(capability)
    }

    public init(
        id: String, directoryURL: URL, manifest: PluginManifest, validationIssues: [String],
        isEnabled: Bool = true, userConfig: [String: String] = [:], kind: PluginKind = .external,
        grantedCapabilities: Set<PluginCapability> = [], overrides: PluginUserOverrides = PluginUserOverrides(),
        builtinMetadata: BuiltinPluginMetadata? = nil, runtimeStatus: PluginRuntimeStatus? = nil
    ) {
        let resolvedKws = (overrides.customKeywords?.filter { !$0.isEmpty }).flatMap { $0.isEmpty ? nil : $0 } ?? manifest.keywords
        self.id = id; self.directoryURL = directoryURL; self.manifest = manifest; self.validationIssues = validationIssues
        self.nameLowercased = manifest.name.lowercased(); self.descriptionLowercased = manifest.description.lowercased()
        let extraNames = (manifest.locales?.values.compactMap { [$0.name, $0.description].compactMap { $0 }.joined(separator: " ") } ?? []).joined(separator: " ")
        self.localizedSearchPoolLowercased = "\(manifest.name) \(manifest.description) \(extraNames)".lowercased()
        self.keywordsLowercased = manifest.keywords.map { $0.lowercased() }
        self.effectiveKeywords = resolvedKws; self.effectiveKeywordsLowercased = resolvedKws.map { $0.lowercased() }
        self.isEnabled = isEnabled; self.userConfig = userConfig; self.kind = kind
        self.grantedCapabilities = grantedCapabilities; self.overrides = overrides
        self.builtinMetadata = builtinMetadata; self.runtimeStatus = runtimeStatus
    }
}

public struct PluginExecutionResult: Sendable, Hashable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Int

    public init(exitCode: Int32, stdout: String, stderr: String, durationMs: Int) {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr; self.durationMs = durationMs
    }
}
