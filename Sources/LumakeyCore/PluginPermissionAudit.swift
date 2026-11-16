import Foundation

public enum LumakeyPermissionCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case systemTCC
    case systemKernel
    case hostBridge
    case resourceScope

    public var title: String {
        switch self {
        case .systemTCC: L10n.pick("系统 TCC", "System TCC")
        case .systemKernel: L10n.pick("内核采样", "Kernel Telemetry")
        case .hostBridge: L10n.pick("宿主桥接", "Host Bridge")
        case .resourceScope: L10n.pick("外部作用域", "Resource Scope")
        }
    }
}

public enum LumakeyPermission: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case localNetwork
    case microphoneAndAudio
    case telemetrySampling
    case clipboard
    case selection
    case audio
    case ocr
    case everythingSearch
    case displayInfo
    case systemControl
    case lumaLinkStatus
    case networkAccess
    case filesystemWrite
    case subprocessExec

    public var id: String { rawValue }

    public var category: LumakeyPermissionCategory {
        switch self {
        case .accessibility, .screenRecording, .localNetwork, .microphoneAndAudio:
            .systemTCC
        case .telemetrySampling:
            .systemKernel
        case .clipboard, .selection, .audio, .ocr, .everythingSearch, .displayInfo, .systemControl, .lumaLinkStatus:
            .hostBridge
        case .networkAccess, .filesystemWrite, .subprocessExec:
            .resourceScope
        }
    }

    public var capability: PluginCapability? {
        PluginCapability(rawValue: rawValue)
    }

    public var resourceScope: PluginResourceScope? {
        switch self {
        case .networkAccess: .network
        case .filesystemWrite: .filesystem
        case .subprocessExec: .subprocess
        default: nil
        }
    }

    public init(capability: PluginCapability) {
        switch capability {
        case .clipboard: self = .clipboard
        case .selection: self = .selection
        case .audio: self = .audio
        case .ocr: self = .ocr
        case .everythingSearch: self = .everythingSearch
        case .displayInfo: self = .displayInfo
        case .systemControl: self = .systemControl
        case .lumaLinkStatus: self = .lumaLinkStatus
        }
    }

    public init(resourceScope: PluginResourceScope) {
        switch resourceScope {
        case .network: self = .networkAccess
        case .filesystem: self = .filesystemWrite
        case .subprocess: self = .subprocessExec
        }
    }

    public var title: String {
        if let cap = capability { return cap.title }
        if let scope = resourceScope { return scope.title }
        switch self {
        case .accessibility: return L10n.pick("辅助功能 (Accessibility)", "Accessibility")
        case .screenRecording: return L10n.pick("屏幕录制 (Screen Recording)", "Screen Recording")
        case .localNetwork: return L10n.pick("本地网络 (Local Network)", "Local Network")
        case .microphoneAndAudio: return L10n.pick("麦克风与系统音频", "Microphone & System Audio")
        case .telemetrySampling: return L10n.pick("IOKit / Mach 硬件采样", "IOKit / Mach Hardware Telemetry")
        default: return rawValue
        }
    }

    public var summary: String {
        if let cap = capability { return cap.summary }
        if let scope = resourceScope { return scope.summary }
        switch self {
        case .accessibility: return L10n.pick("用于全局鼠标/键盘事件捕获与远程控制键鼠输入注入", "Global mouse wheel smoothing, text selection & remote input injection")
        case .screenRecording: return L10n.pick("用于截图采集、远控桌面镜像捕获与光学文字识别输入", "Screenshot capture, GIF recording, Vision OCR & remote screen sharing")
        case .localNetwork: return L10n.pick("用于 Bonjour 局域网服务广播与 LumaLink 设备配对通信", "Bonjour LAN service discovery & LumaLink device pairing")
        case .microphoneAndAudio: return L10n.pick("用于远控双向音频捕获与实时音频流透传", "Two-way audio capture & real-time system audio streaming")
        case .telemetrySampling: return L10n.pick("只读采样 CPU/DVFS 频率、内存、功耗与网速（免 TCC 弹窗）", "Read-only CPU/DVFS, memory, power & network sampling (no TCC prompt)")
        default: return ""
        }
    }

    public var symbolName: String {
        if let cap = capability { return cap.symbolName }
        if let scope = resourceScope { return scope.symbolName }
        switch self {
        case .accessibility: return "hand.raised.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .localNetwork: return "wifi"
        case .microphoneAndAudio: return "mic.fill"
        case .telemetrySampling: return "waveform.path.ecg"
        default: return "shield.fill"
        }
    }

    public var systemPreferencesURL: String? {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphoneAndAudio:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        default:
            nil
        }
    }
}

public struct PluginPermissionUsage: Identifiable, Sendable, Hashable {
    public var id: String { "\(pluginID):\(permissionRaw)" }
    public let permissionRaw: String
    public let pluginID: String
    public let pluginName: String
    public let kind: PluginKind
    public let isPluginEnabled: Bool
    public let isAuthorized: Bool
    public let roleNote: String

    public init(
        permissionRaw: String,
        pluginID: String,
        pluginName: String,
        kind: PluginKind,
        isPluginEnabled: Bool,
        isAuthorized: Bool,
        roleNote: String
    ) {
        self.permissionRaw = permissionRaw
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.kind = kind
        self.isPluginEnabled = isPluginEnabled
        self.isAuthorized = isAuthorized
        self.roleNote = roleNote
    }
}

public struct AppPermissionAuditEntry: Identifiable, Sendable, Hashable {
    public var id: String { permission.rawValue }
    public let permission: LumakeyPermission
    public let plugins: [PluginPermissionUsage]

    public var declaredPluginCount: Int { plugins.count }
    public var activePluginCount: Int { plugins.filter { $0.isPluginEnabled && $0.isAuthorized }.count }

    public init(permission: LumakeyPermission, plugins: [PluginPermissionUsage]) {
        self.permission = permission
        self.plugins = plugins
    }
}

public enum PluginPermissionAudit {
    public static func declaredPermissions(for plugin: PluginDescriptor) -> [LumakeyPermission] {
        if plugin.isBuiltin {
            return plugin.builtinMetadata?.requiredPermissions ?? []
        }
        return plugin.declaredCapabilities.map(LumakeyPermission.init(capability:))
            + plugin.declaredResourceScopes.map(LumakeyPermission.init(resourceScope:))
    }

    public static func buildAudit(
        plugins: [PluginDescriptor],
        accessibilityGranted: Bool = MosEngine.shared.isAccessibilityTrusted
    ) -> [AppPermissionAuditEntry] {
        LumakeyPermission.allCases.map { permission in
            var usages: [PluginPermissionUsage] = []
            for plugin in plugins {
                let declared = declaredPermissions(for: plugin)
                guard declared.contains(permission) else { continue }
                let authorized: Bool
                let note: String
                if plugin.isBuiltin {
                    authorized = (permission == .accessibility) ? accessibilityGranted : true
                    note = plugin.isEnabled
                        ? (authorized ? L10n.pick("内置原生 · 宿主共享中", "Built-in · Shared") : L10n.pick("内置原生 · 待授系统权限", "Built-in · Grant TCC"))
                        : L10n.pick("内置原生 · 插件已关闭（零消耗）", "Built-in · Off (0% CPU)")
                } else if let cap = permission.capability {
                    authorized = plugin.isCapabilityGranted(cap)
                    note = authorized ? L10n.pick("Host Bridge · 已授权", "Host Bridge · Granted") : L10n.pick("Host Bridge · 默认关闭（未授权）", "Host Bridge · Denied")
                } else if permission.resourceScope != nil {
                    authorized = true
                    note = L10n.pick("注册声明作用域（审计可见）", "Declared Scope (Audited)")
                } else {
                    authorized = false
                    note = L10n.pick("声明权限", "Declared")
                }
                usages.append(PluginPermissionUsage(
                    permissionRaw: permission.rawValue,
                    pluginID: plugin.id,
                    pluginName: plugin.manifest.name,
                    kind: plugin.kind,
                    isPluginEnabled: plugin.isEnabled,
                    isAuthorized: authorized,
                    roleNote: note
                ))
            }
            usages.sort { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .builtin }
                return lhs.pluginID < rhs.pluginID
            }
            return AppPermissionAuditEntry(permission: permission, plugins: usages)
        }
    }

    public static func sandboxOnlyPlugins(in plugins: [PluginDescriptor]) -> [PluginDescriptor] {
        plugins.filter { declaredPermissions(for: $0).isEmpty }
    }
}
