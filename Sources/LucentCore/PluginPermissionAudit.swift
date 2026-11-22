import LucentFoundation
import LucentSystem
import Foundation

public enum LucentPermissionCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case systemTCC
    case systemKernel
    case hostBridge
    case resourceScope

    public var title: String {
        switch self {
        case .systemTCC: L10n.pick("macOS 系统隐私权限", "macOS Privacy Permissions")
        case .systemKernel: L10n.pick("只读硬件采样", "Hardware Telemetry")
        case .hostBridge: L10n.pick("插件扩展能力", "Plugin Capabilities")
        case .resourceScope: L10n.pick("网络 / 文件 / 命令行", "Network / Files / CLI")
        }
    }
}

public enum LucentPermission: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case accessibility, screenRecording, systemNotifications, localNetwork, microphoneAndAudio
    case telemetrySampling
    case clipboard, selection, window, floatingWindow, screenCapture, notifications, audio, ocr, everythingSearch, displayInfo, systemControl, lumaLinkStatus, fileShelf, audioDevices, windowControl, contextRouter
    case networkAccess, filesystemWrite, subprocessExec

    public var id: String { rawValue }

    public var category: LucentPermissionCategory {
        switch self {
        case .accessibility, .screenRecording, .systemNotifications, .localNetwork, .microphoneAndAudio: .systemTCC
        case .telemetrySampling: .systemKernel
        case .clipboard, .selection, .window, .floatingWindow, .screenCapture, .notifications, .audio, .ocr, .everythingSearch, .displayInfo, .systemControl, .lumaLinkStatus, .fileShelf, .audioDevices, .windowControl, .contextRouter: .hostBridge
        case .networkAccess, .filesystemWrite, .subprocessExec: .resourceScope
        }
    }

    public var capability: PluginCapability? { PluginCapability(rawValue: rawValue) }

    public var tccKind: PluginSystemTCCKind? {
        switch self {
        case .accessibility: .accessibility
        case .screenRecording: .screenRecording
        case .systemNotifications: .notifications
        case .microphoneAndAudio: .microphone
        default: capability.flatMap(PluginHostTCCBroker.requiredTCC(for:))
        }
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
        case .window: self = .window
        case .floatingWindow: self = .floatingWindow
        case .screenCapture: self = .screenCapture
        case .notifications: self = .notifications
        case .audio: self = .audio
        case .ocr: self = .ocr
        case .everythingSearch: self = .everythingSearch
        case .displayInfo: self = .displayInfo
        case .systemControl: self = .systemControl
        case .lumaLinkStatus: self = .lumaLinkStatus
        case .fileShelf: self = .fileShelf
        case .audioDevices: self = .audioDevices
        case .windowControl: self = .windowControl
        case .contextRouter: self = .contextRouter
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
        case .systemNotifications: return L10n.pick("系统通知 (Notifications)", "System Notifications")
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
        case .accessibility: return L10n.pick("由宿主统一代申，用于全局滚轮平滑、窗口分屏布局、跨应用划词读取、原窗口粘贴回填与远控输入", "Host-brokered Accessibility for window layouts, selection read, paste-back & input")
        case .screenRecording: return L10n.pick("由宿主统一代申，用于选区截图、取色、GIF 录制、离线识字与插件视觉采样", "Host-brokered Screen Recording for capture, color picking & OCR")
        case .systemNotifications: return L10n.pick("由宿主统一代申，代外部插件投递原生 macOS 横幅与声音提醒", "Host-brokered macOS Notification Center banners for plugins")
        case .localNetwork: return L10n.pick("用于 Bonjour 局域网服务广播与 LumaLink 设备配对通信", "Bonjour LAN service discovery & LumaLink device pairing")
        case .microphoneAndAudio: return L10n.pick("由宿主统一代申，用于远控双向音频捕获与实时音频流透传", "Host-brokered microphone & system audio capture")
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
        case .systemNotifications: return "bell.badge.fill"
        case .localNetwork: return "wifi"
        case .microphoneAndAudio: return "mic.fill"
        case .telemetrySampling: return "waveform.path.ecg"
        default: return "shield.fill"
        }
    }

    public var systemPreferencesURL: String? {
        if let kind = tccKind, category == .systemTCC {
            return kind.systemSettingsURLString
        }
        return nil
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
        permissionRaw: String, pluginID: String, pluginName: String,
        kind: PluginKind, isPluginEnabled: Bool, isAuthorized: Bool, roleNote: String
    ) {
        self.permissionRaw = permissionRaw; self.pluginID = pluginID; self.pluginName = pluginName
        self.kind = kind; self.isPluginEnabled = isPluginEnabled; self.isAuthorized = isAuthorized
        self.roleNote = roleNote
    }
}

public struct AppPermissionAuditEntry: Identifiable, Sendable, Hashable {
    public var id: String { permission.rawValue }
    public let permission: LucentPermission
    public let plugins: [PluginPermissionUsage]

    public var declaredPluginCount: Int { plugins.count }
    public var activePluginCount: Int { plugins.filter { $0.isPluginEnabled && $0.isAuthorized }.count }

    public init(permission: LucentPermission, plugins: [PluginPermissionUsage]) {
        self.permission = permission; self.plugins = plugins
    }
}

public enum PluginPermissionAudit {
    public static func declaredPermissions(for plugin: PluginDescriptor) -> [LucentPermission] {
        if plugin.isBuiltin {
            return plugin.builtinMetadata?.requiredPermissions ?? []
        }
        var result: [LucentPermission] = []
        for cap in plugin.declaredCapabilities {
            result.append(LucentPermission(capability: cap))
            switch cap {
            case .selection, .windowControl: if !result.contains(.accessibility) { result.append(.accessibility) }
            case .screenCapture: if !result.contains(.screenRecording) { result.append(.screenRecording) }
            case .notifications: if !result.contains(.systemNotifications) { result.append(.systemNotifications) }
            default: break
            }
        }
        result.append(contentsOf: plugin.declaredResourceScopes.map(LucentPermission.init(resourceScope:)))
        return result
    }

    public static func buildAudit(
        plugins: [PluginDescriptor],
        accessibilityGranted: Bool = MosEngine.shared.isAccessibilityTrusted
    ) -> [AppPermissionAuditEntry] {
        LucentPermission.allCases.map { permission in
            var usages: [PluginPermissionUsage] = []
            for plugin in plugins {
                guard declaredPermissions(for: plugin).contains(permission) else { continue }
                let (authorized, note) = evaluateUsage(plugin: plugin, permission: permission, accessibilityGranted: accessibilityGranted)
                usages.append(PluginPermissionUsage(
                    permissionRaw: permission.rawValue, pluginID: plugin.id, pluginName: plugin.manifest.name,
                    kind: plugin.kind, isPluginEnabled: plugin.isEnabled, isAuthorized: authorized, roleNote: note
                ))
            }
            usages.sort { ($0.kind != $1.kind) ? ($0.kind == .builtin) : ($0.pluginID < $1.pluginID) }
            return AppPermissionAuditEntry(permission: permission, plugins: usages)
        }
    }

    private static func evaluateUsage(
        plugin: PluginDescriptor,
        permission: LucentPermission,
        accessibilityGranted: Bool
    ) -> (Bool, String) {
        if plugin.isBuiltin {
            let ok = (permission == .accessibility) ? accessibilityGranted : true
            let note = plugin.isEnabled
                ? (ok ? L10n.pick("内置原生 · 宿主共享中", "Built-in · Shared") : L10n.pick("内置原生 · 待授系统权限", "Built-in · Grant TCC"))
                : L10n.pick("内置原生 · 插件已关闭（零消耗）", "Built-in · Off (0% CPU)")
            return (ok, note)
        }
        if permission.category == .systemTCC, let tcc = permission.tccKind {
            let tccOK = (tcc == .accessibility) ? accessibilityGranted : PluginHostTCCBroker.status(for: tcc).isGranted
            return (
                tccOK,
                tccOK
                    ? L10n.pick("宿主 TCC 已就绪 · 按插件开关分发", "Host TCC Ready · Per-Plugin Gated")
                    : L10n.pick("待宿主代申 macOS 系统权限", "Host TCC Pending")
            )
        }
        if let cap = permission.capability {
            let ok = plugin.isCapabilityGranted(cap)
            return (ok, ok ? L10n.pick("Host Bridge · 已放行", "Host Bridge · Granted") : L10n.pick("Host Bridge · 默认关闭（未授权）", "Host Bridge · Denied"))
        }
        if let scope = permission.resourceScope {
            let ok = plugin.isResourceScopeGranted(scope)
            return (ok, ok ? L10n.pick("OS 沙箱 · 已按声明放行", "OS Sandbox · Allowed") : L10n.pick("OS 沙箱 · 已强制拦截", "OS Sandbox · Blocked"))
        }
        return (false, L10n.pick("声明权限", "Declared"))
    }

    public static func sandboxOnlyPlugins(in plugins: [PluginDescriptor]) -> [PluginDescriptor] {
        plugins.filter { declaredPermissions(for: $0).isEmpty }
    }
}
