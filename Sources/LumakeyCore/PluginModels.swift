import Foundation

public enum PluginMode: String, Codable, Sendable, Hashable, CaseIterable {
    case script, view
}

public enum PluginKind: String, Codable, Sendable, Hashable {
    case builtin, external
}

public enum PluginCapability: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case clipboard
    case selection
    case audio
    case ocr
    case everythingSearch
    case displayInfo
    case systemControl
    case lumaLinkStatus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clipboard: "剪贴板读写"
        case .selection: "跨应用选中文本读取"
        case .audio: "宿主音频与语音朗读"
        case .ocr: "离线 Vision OCR"
        case .everythingSearch: "Everything 文件检索"
        case .displayInfo: "显示器与分辨率信息"
        case .systemControl: "系统音量与防休眠控制"
        case .lumaLinkStatus: "LumaLink 远控状态"
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: "通过宿主桥读取或写入系统剪贴板文本"
        case .selection: "复用宿主辅助功能权限读取当前前台应用选中的文本"
        case .audio: "复用宿主音频引擎播放本地音频文件或执行系统语音朗读"
        case .ocr: "复用宿主 VisionService 离线识别图片中英文字与条码"
        case .everythingSearch: "复用宿主内存索引按 DSL 极速检索全盘与外置盘文件"
        case .displayInfo: "读取活跃显示器列表、当前模式与支持的分辨率"
        case .systemControl: "读取音量/静音/防休眠状态并执行安全级调节"
        case .lumaLinkStatus: "读取 LumaLink 监听端口、连接数与 RDP 引擎状态（脱敏）"
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
        "经临时 Host Bridge 复用 Lumakey 宿主权限 · 默认关闭"
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
        self.categoryBadge = categoryBadge
        self.requiredPermissions = requiredPermissions
        self.settingsTarget = settingsTarget
        self.statusSummary = statusSummary
    }
}

public enum PluginConfigFieldType: String, Codable, Sendable, Hashable, CaseIterable {
    case text, secret, boolean, select
}

public struct PluginConfigField: Codable, Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let type: PluginConfigFieldType
    public let defaultValue: String?
    public let placeholder: String?
    public let options: [String]?
    public let required: Bool?

    public init(
        key: String, label: String, type: PluginConfigFieldType = .text,
        defaultValue: String? = nil, placeholder: String? = nil,
        options: [String]? = nil, required: Bool? = nil
    ) {
        self.key = key; self.label = label; self.type = type
        self.defaultValue = defaultValue; self.placeholder = placeholder
        self.options = options; self.required = required
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
    public let hotkey: String?
    public let config: [PluginConfigField]?
    public let capabilities: [String]?
    public let resourceScopes: [String]?
    public let refreshIntervalSeconds: Int?

    public var declaredCapabilities: [PluginCapability] {
        var seen = Set<PluginCapability>()
        var result: [PluginCapability] = []
        for raw in capabilities ?? [] {
            if let cap = PluginCapability(rawValue: raw), seen.insert(cap).inserted {
                result.append(cap)
            }
        }
        return result
    }

    public var declaredResourceScopes: [PluginResourceScope] {
        var seen = Set<PluginResourceScope>()
        var result: [PluginResourceScope] = []
        for raw in resourceScopes ?? [] {
            if let scope = PluginResourceScope(rawValue: raw), seen.insert(scope).inserted {
                result.append(scope)
            }
        }
        return result
    }

    public init(
        schemaVersion: Int? = nil,
        id: String, name: String, version: String, description: String,
        mode: PluginMode, keywords: [String], entry: String,
        author: String? = nil, icon: String? = nil,
        hotkey: String? = nil, config: [PluginConfigField]? = nil,
        capabilities: [String]? = nil,
        resourceScopes: [String]? = nil,
        refreshIntervalSeconds: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id; self.name = name; self.version = version; self.description = description
        self.mode = mode; self.keywords = keywords; self.entry = entry
        self.author = author; self.icon = icon; self.hotkey = hotkey
        self.config = config; self.capabilities = capabilities
        self.resourceScopes = resourceScopes
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }
}

public struct PluginInstanceState: Codable, Sendable, Hashable, Equatable {
    public var isEnabled: Bool
    public var configValues: [String: String]
    public var grantedCapabilities: [String]

    enum CodingKeys: String, CodingKey {
        case isEnabled, configValues, grantedCapabilities
    }

    public init(isEnabled: Bool = true, configValues: [String: String] = [:], grantedCapabilities: [String] = []) {
        self.isEnabled = isEnabled; self.configValues = configValues; self.grantedCapabilities = grantedCapabilities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.configValues = try c.decodeIfPresent([String: String].self, forKey: .configValues) ?? [:]
        self.grantedCapabilities = try c.decodeIfPresent([String].self, forKey: .grantedCapabilities) ?? []
    }
}

public struct PluginStateSnapshot: Codable, Sendable, Hashable, Equatable {
    public var schemaVersion: Int
    public var plugins: [String: PluginInstanceState]

    public init(schemaVersion: Int = 2, plugins: [String: PluginInstanceState] = [:]) {
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
    public let keywordsLowercased: [String]
    public let isEnabled: Bool
    public let userConfig: [String: String]
    public let kind: PluginKind
    public let grantedCapabilities: Set<PluginCapability>
    public let builtinMetadata: BuiltinPluginMetadata?

    public var isValid: Bool { validationIssues.isEmpty }
    public var isBuiltin: Bool { kind == .builtin }
    public var declaredCapabilities: [PluginCapability] { manifest.declaredCapabilities }
    public var declaredResourceScopes: [PluginResourceScope] { manifest.declaredResourceScopes }
    public var declaredPermissions: [LumakeyPermission] { PluginPermissionAudit.declaredPermissions(for: self) }
    public var isPureSandbox: Bool { declaredPermissions.isEmpty }
    public func isCapabilityGranted(_ capability: PluginCapability) -> Bool {
        declaredCapabilities.contains(capability) && grantedCapabilities.contains(capability)
    }

    public init(
        id: String, directoryURL: URL, manifest: PluginManifest,
        validationIssues: [String], isEnabled: Bool = true,
        userConfig: [String: String] = [:], kind: PluginKind = .external,
        grantedCapabilities: Set<PluginCapability> = [],
        builtinMetadata: BuiltinPluginMetadata? = nil
    ) {
        self.id = id; self.directoryURL = directoryURL; self.manifest = manifest
        self.validationIssues = validationIssues
        self.nameLowercased = manifest.name.lowercased()
        self.descriptionLowercased = manifest.description.lowercased()
        self.keywordsLowercased = manifest.keywords.map { $0.lowercased() }
        self.isEnabled = isEnabled; self.userConfig = userConfig
        self.kind = kind; self.grantedCapabilities = grantedCapabilities
        self.builtinMetadata = builtinMetadata
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
