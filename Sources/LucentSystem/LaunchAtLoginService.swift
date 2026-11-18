import AppKit
import Foundation
import LucentFoundation
import ServiceManagement

public enum LaunchAtLoginStatus: String, Sendable, Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    public var isEnabledOrPending: Bool {
        self == .enabled || self == .requiresApproval
    }

    public var localizedBadge: String {
        switch self {
        case .enabled:
            L10n.pick("已开启", "Enabled")
        case .notRegistered:
            L10n.pick("未开启", "Off")
        case .requiresApproval:
            L10n.pick("需系统设置批准", "Requires Approval")
        case .notFound:
            L10n.pick("需放入应用程序目录", "Move to Applications")
        }
    }

    public var localizedGuidance: String {
        switch self {
        case .enabled:
            L10n.pick(
                "已注册至 macOS 原生登录项（零 launchd 后台守护进程），登录系统时将自动拉起 Lucent。",
                "Registered via native macOS Login Items (zero launchd daemons). Lucent starts automatically when you log in."
            )
        case .notRegistered:
            L10n.pick(
                "通过 macOS 原生登录项随系统启动，不安装任何常驻守护进程；推荐配合「启动时静默驻留状态栏」使用。",
                "Uses native macOS Login Items with zero background daemons. Recommended alongside silent menu-bar launch."
            )
        case .requiresApproval:
            L10n.pick(
                "登录项已在「系统设置 - 通用 - 登录项」中被关闭或等待批准，点击右侧按钮前往允许即可生效。",
                "Disabled or awaiting approval in System Settings - General - Login Items. Click to open Login Items and enable Lucent."
            )
        case .notFound:
            L10n.pick(
                "当前运行包尚未被系统登录项服务识别，请先将 Lucent.app 移入 /Applications 后再开启开机自启。",
                "App bundle is not indexed by LaunchServices yet. Move Lucent.app into /Applications before enabling Launch at Login."
            )
        }
    }
}

public enum LaunchAtLoginService {
    public static func currentStatus() -> LaunchAtLoginStatus {
        mapStatus(SMAppService.mainApp.status)
    }

    public static func isInstalledInApplications(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let std = bundleURL.standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        return std.hasPrefix("/Applications/") || std.hasPrefix(userApps + "/")
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
        return currentStatus()
    }

    @MainActor
    public static func openSystemLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }
}
