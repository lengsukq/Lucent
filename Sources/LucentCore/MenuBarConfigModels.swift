import LucentFoundation
import LucentSystem
import Foundation

public extension Notification.Name {
    static let lucentMenuBarConfigDidChange = Notification.Name(LucentIdentifiers.scoped("menuBarConfigDidChange"))
}

public enum MenuBarPreset: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case compact
    case balanced
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: L10n.pick("精简核心", "Compact")
        case .balanced: L10n.pick("效率常用", "Balanced")
        case .full: L10n.pick("完整全量", "Full")
        }
    }

    public var subtitle: String {
        switch self {
        case .compact: L10n.pick("仅保留搜索与截图核心入口（约 6 项）", "Search & capture essentials (~6 items)")
        case .balanced: L10n.pick("常用功能置顶，低频维护收纳进二级菜单", "Common actions + folded maintenance submenu")
        case .full: L10n.pick("一级菜单平铺展示全部功能入口", "Show all built-in items at top level")
        }
    }
}

public enum MenuBarItemGroup: String, Codable, Sendable, Hashable, CaseIterable {
    case launcher
    case capture
    case monitor
    case workspaceAndTools
    case system

    public var title: String {
        switch self {
        case .launcher: L10n.pick("搜索与唤起", "Search & Launcher")
        case .capture: L10n.pick("截图、录屏与窗口清理", "Capture & Cleanup")
        case .monitor: L10n.pick("性能脉搏与网络监控", "Telemetry & Network")
        case .workspaceAndTools: L10n.pick("工作台与系统维护", "Workspace & Maintenance")
        case .system: L10n.pick("设置与退出（常驻锁定）", "Settings & Quit (Locked)")
        }
    }
}

public enum MenuBarBuiltinItemID: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case launcherAll
    case filesFilter
    case clipboardFilter
    case systemPulseWidget
    case systemPulseSnapEdge
    case menuBarTelemetryReadout
    case networkMonitor
    case screenshotPin
    case screenshotOCR
    case gifRecord
    case videoRecord
    case closeAllPins
    case closeAllPluginWindows
    case fileWorkspace
    case lumaLinkConsole
    case mosSettings
    case backupSync
    case cacheCleanup
    case reclaimMemory
    case switchLanguage
    case checkForUpdates
    case settingsCenter
    case quitApp

    public var id: String { rawValue }
    public var isLockedVisible: Bool { self == .settingsCenter || self == .quitApp }

    public var isMaintenanceItem: Bool {
        switch self {
        case .mosSettings, .backupSync, .cacheCleanup, .reclaimMemory, .switchLanguage, .checkForUpdates: true
        default: false
        }
    }

    public var isContextualDynamicItem: Bool {
        switch self {
        case .closeAllPins, .closeAllPluginWindows, .systemPulseSnapEdge, .lumaLinkConsole: true
        default: false
        }
    }

    public var group: MenuBarItemGroup {
        switch self {
        case .launcherAll, .filesFilter, .clipboardFilter: .launcher
        case .screenshotPin, .screenshotOCR, .gifRecord, .videoRecord, .closeAllPins, .closeAllPluginWindows: .capture
        case .systemPulseWidget, .systemPulseSnapEdge, .menuBarTelemetryReadout, .networkMonitor: .monitor
        case .fileWorkspace, .lumaLinkConsole, .mosSettings, .backupSync, .cacheCleanup, .reclaimMemory, .switchLanguage, .checkForUpdates: .workspaceAndTools
        case .settingsCenter, .quitApp: .system
        }
    }

    public var associatedHotKeyAction: HotKeyActionID? {
        switch self {
        case .launcherAll: .launcher
        case .filesFilter: .files
        case .clipboardFilter: .clipboard
        case .screenshotPin: .screenshotPin
        case .screenshotOCR: .screenshotOCR
        case .gifRecord: .gifRecord
        case .videoRecord: .videoRecord
        case .fileWorkspace: .workspace
        case .systemPulseWidget: .systemPulse
        case .networkMonitor: .networkMonitor
        case .backupSync: .quickBackup
        default: nil
        }
    }

    public var symbolName: String {
        switch self {
        case .launcherAll: "sparkles"
        case .filesFilter: "magnifyingglass"
        case .clipboardFilter: "doc.on.clipboard"
        case .systemPulseWidget: "waveform.path.ecg"
        case .systemPulseSnapEdge: "sidebar.right"
        case .menuBarTelemetryReadout: "speedometer"
        case .networkMonitor: "network"
        case .screenshotPin: "camera.viewfinder"
        case .screenshotOCR: "text.viewfinder"
        case .gifRecord: "record.circle"
        case .videoRecord: "video.circle"
        case .closeAllPins: "pin.slash"
        case .closeAllPluginWindows: "xmark.rectangle.portrait"
        case .fileWorkspace: "externaldrive"
        case .lumaLinkConsole: "ipad.and.iphone"
        case .mosSettings: "computermouse"
        case .backupSync: "externaldrive.badge.icloud"
        case .cacheCleanup: "internaldrive"
        case .reclaimMemory: "memorychip"
        case .switchLanguage: "globe"
        case .checkForUpdates: "arrow.triangle.2.circlepath.circle"
        case .settingsCenter: "gearshape"
        case .quitApp: "power"
        }
    }

    public var rawMenuTitle: String {
        switch self {
        case .launcherAll: "呼出统一搜索快捷台"
        case .filesFilter: "文件极速过滤"
        case .clipboardFilter: "剪贴板历史过滤"
        case .systemPulseWidget: "系统脉搏监控悬浮窗"
        case .systemPulseSnapEdge: "系统脉搏：立即贴边自动隐藏"
        case .menuBarTelemetryReadout: "菜单栏显示实时功耗与网速"
        case .networkMonitor: "本机网络流量与去向监控"
        case .screenshotPin: "选区截图钉屏"
        case .screenshotOCR: "选区截图离线识字"
        case .gifRecord: "区域 GIF 动图录制"
        case .videoRecord: L10n.pick("区域视频录像", "Region Video Recording")
        case .closeAllPins: "关闭全部钉图"
        case .closeAllPluginWindows: "关闭全部插件自由窗口"
        case .fileWorkspace: "文件与外置磁盘工作台 · 附加"
        case .lumaLinkConsole: "流光随行手机远控与极速 RDP"
        case .mosSettings: "鼠标平滑与滚轮反转"
        case .backupSync: "导出、备份与 WebDAV 云同步"
        case .cacheCleanup: "应用缓存与存储清理"
        case .reclaimMemory: "立即释放空闲内存"
        case .switchLanguage: "切换界面语言"
        case .checkForUpdates: "检查应用与插件更新"
        case .settingsCenter: "设置与插件 MCP 中心"
        case .quitApp: "退出 流光 Lucent"
        }
    }

    public var localizedTitle: String { L10n.translate(rawMenuTitle) }
}

public struct MenuBarRuntimeContext: Sendable, Hashable, Equatable {
    public var activePinCount: Int
    public var activePluginWindowCount: Int
    public var isSystemPulseFloatingVisible: Bool
    public var isLumaLinkAvailableOrEnabled: Bool
    public var availableAppUpdateVersion: String?
    public var availablePluginUpdateCount: Int

    public init(
        activePinCount: Int = 0,
        activePluginWindowCount: Int = 0,
        isSystemPulseFloatingVisible: Bool = false,
        isLumaLinkAvailableOrEnabled: Bool = false,
        availableAppUpdateVersion: String? = nil,
        availablePluginUpdateCount: Int = 0
    ) {
        self.activePinCount = max(0, activePinCount)
        self.activePluginWindowCount = max(0, activePluginWindowCount)
        self.isSystemPulseFloatingVisible = isSystemPulseFloatingVisible
        self.isLumaLinkAvailableOrEnabled = isLumaLinkAvailableOrEnabled
        self.availableAppUpdateVersion = availableAppUpdateVersion
        self.availablePluginUpdateCount = max(0, availablePluginUpdateCount)
    }
}

public struct MenuBarResolvedLayout: Sendable, Hashable, Equatable {
    public let topLevelItems: [MenuBarBuiltinItemID]
    public let maintenanceSubmenuItems: [MenuBarBuiltinItemID]
    public let systemTailItems: [MenuBarBuiltinItemID]
}
