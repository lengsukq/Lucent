import Foundation

public enum LumakeyPermissionCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case systemTCC
    case systemKernel
    case hostBridge

    public var title: String {
        switch self {
        case .systemTCC: "系统 TCC"
        case .systemKernel: "内核采样"
        case .hostBridge: "宿主桥接"
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
    case ocr
    case everythingSearch
    case displayInfo
    case systemControl
    case lumaLinkStatus

    public var id: String { rawValue }

    public var category: LumakeyPermissionCategory {
        switch self {
        case .accessibility, .screenRecording, .localNetwork, .microphoneAndAudio:
            .systemTCC
        case .telemetrySampling:
            .systemKernel
        case .clipboard, .ocr, .everythingSearch, .displayInfo, .systemControl, .lumaLinkStatus:
            .hostBridge
        }
    }

    public var capability: PluginCapability? {
        PluginCapability(rawValue: rawValue)
    }

    public init(capability: PluginCapability) {
        switch capability {
        case .clipboard: self = .clipboard
        case .ocr: self = .ocr
        case .everythingSearch: self = .everythingSearch
        case .displayInfo: self = .displayInfo
        case .systemControl: self = .systemControl
        case .lumaLinkStatus: self = .lumaLinkStatus
        }
    }

    public var title: String {
        if let cap = capability { return cap.title }
        switch self {
        case .accessibility: return "辅助功能 (Accessibility)"
        case .screenRecording: return "屏幕录制 (Screen Recording)"
        case .localNetwork: return "本地网络 (Local Network)"
        case .microphoneAndAudio: return "麦克风与系统音频"
        case .telemetrySampling: return "IOKit / Mach 硬件采样"
        default: return rawValue
        }
    }

    public var summary: String {
        if let cap = capability { return cap.summary }
        switch self {
        case .accessibility: return "用于全局鼠标/键盘事件捕获与远程控制键鼠输入注入"
        case .screenRecording: return "用于截图采集、远控桌面镜像捕获与光学文字识别输入"
        case .localNetwork: return "用于 Bonjour 局域网服务广播与 LumaLink 设备配对通信"
        case .microphoneAndAudio: return "用于远控双向音频捕获与实时音频流透传"
        case .telemetrySampling: return "只读采样 CPU/DVFS 频率、内存、功耗与网速（免 TCC 弹窗）"
        default: return ""
        }
    }

    public var symbolName: String {
        if let cap = capability { return cap.symbolName }
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
                        ? (authorized ? "内置原生 · 宿主共享中" : "内置原生 · 待授系统权限")
                        : "内置原生 · 插件已关闭（零消耗）"
                } else if let cap = permission.capability {
                    authorized = plugin.isCapabilityGranted(cap)
                    note = authorized ? "Host Bridge · 已授权" : "Host Bridge · 默认关闭（未授权）"
                } else {
                    authorized = false
                    note = "声明权限"
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
