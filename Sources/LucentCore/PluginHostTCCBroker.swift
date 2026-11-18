import LucentFoundation
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import UserNotifications

public enum PluginSystemTCCKind: String, Codable, Sendable, Hashable, CaseIterable {
    case accessibility
    case screenRecording
    case notifications
    case microphone

    public var title: String {
        switch self {
        case .accessibility: L10n.pick("辅助功能", "Accessibility")
        case .screenRecording: L10n.pick("屏幕录制", "Screen Recording")
        case .notifications: L10n.pick("系统通知", "Notifications")
        case .microphone: L10n.pick("麦克风", "Microphone")
        }
    }

    public var systemSettingsURLString: String {
        switch self {
        case .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .microphone: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }

    public var systemSettingsURL: URL? {
        URL(string: systemSettingsURLString)
    }
}

public enum PluginTCCGrantStatus: String, Codable, Sendable, Hashable {
    case granted
    case notGranted
    case unavailableInCLI

    public var isGranted: Bool { self == .granted }
}

/// 宿主统一 TCC 权限代理器（「macOS 认宿主，宿主审插件」）。
/// 外部插件运行在 `sandbox-exec` 沙盒或 `WKWebView` 容器中，不直接申请系统高危权限；
/// 当插件获用户放行后，由 `Lucent.app` 宿主统一检测、代弹 macOS 系统授权请求或引导打开隐私设置页。
public enum PluginHostTCCBroker {
    public static var isInteractiveAppBundleRuntime: Bool {
        PluginNotificationService.isSystemNotificationCenterAvailable
    }

    public static func requiredTCC(for capability: PluginCapability) -> PluginSystemTCCKind? {
        switch capability {
        case .selection: .accessibility
        case .screenCapture: .screenRecording
        case .notifications: .notifications
        default: nil
        }
    }

    public static func status(for kind: PluginSystemTCCKind) -> PluginTCCGrantStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .granted : .notGranted
        case .notifications:
            guard isInteractiveAppBundleRuntime else { return .unavailableInCLI }
            let sem = DispatchSemaphore(value: 0)
            let box = LockedStatusBox(.notGranted)
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                box.set(ok ? .granted : .notGranted)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + .milliseconds(250))
            return box.get()
        }
    }

    @discardableResult
    public static func requestAccessOnBehalfOfPlugin(
        _ kind: PluginSystemTCCKind,
        allowSystemPrompt: Bool? = nil
    ) -> PluginTCCGrantStatus {
        let current = status(for: kind)
        if current == .granted { return .granted }

        let shouldPrompt = allowSystemPrompt ?? isInteractiveAppBundleRuntime
        guard shouldPrompt else { return current }

        switch kind {
        case .accessibility:
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts) ? .granted : .notGranted
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            let sem = DispatchSemaphore(value: 0)
            let box = LockedStatusBox(.notGranted)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                box.set(granted ? .granted : .notGranted)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + .seconds(2))
            return box.get()
        case .notifications:
            guard isInteractiveAppBundleRuntime else { return .unavailableInCLI }
            let sem = DispatchSemaphore(value: 0)
            let box = LockedStatusBox(.notGranted)
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                box.set(granted ? .granted : .notGranted)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + .seconds(2))
            return box.get()
        }
    }

    public static func statusPayload(for kind: PluginSystemTCCKind) -> [String: Any] {
        let st = status(for: kind)
        return [
            "tcc": kind.rawValue,
            "title": kind.title,
            "status": st.rawValue,
            "granted": st.isGranted,
            "settingsURL": kind.systemSettingsURLString
        ]
    }

    public static func allTCCSnapshot() -> [[String: Any]] {
        PluginSystemTCCKind.allCases.map { statusPayload(for: $0) }
    }
}

private final class LockedStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PluginTCCGrantStatus
    init(_ initial: PluginTCCGrantStatus) { self.value = initial }
    func set(_ next: PluginTCCGrantStatus) { lock.withLock { value = next } }
    func get() -> PluginTCCGrantStatus { lock.withLock { value } }
}
