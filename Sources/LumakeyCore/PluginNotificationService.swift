import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation
import UserNotifications

public struct PluginNotificationRecord: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let pluginID: String
    public let pluginName: String
    public let payload: PluginNotificationPayload
    public let createdAt: Date
    public let deliveredToSystemCenter: Bool

    public init(
        id: String = UUID().uuidString,
        pluginID: String,
        pluginName: String,
        payload: PluginNotificationPayload,
        createdAt: Date = Date(),
        deliveredToSystemCenter: Bool
    ) {
        self.id = id
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.payload = payload
        self.createdAt = createdAt
        self.deliveredToSystemCenter = deliveredToSystemCenter
    }
}

private final class ForegroundNotificationBannerDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ForegroundNotificationBannerDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

/// 宿主级外部插件系统原生通知服务（`UNUserNotificationCenter`）。
/// 在 `.app` 捆绑包运行态下投递真实 macOS 横幅通知（前台活跃时仍显示横幅），
/// 在命令行单测 / `lumakey-check` 无 `.app` Bundle 环境下自动安全降级至内存审计队列，避免 `UNUserNotificationCenter` 崩溃。
public final class PluginNotificationService: @unchecked Sendable {
    public static let shared = PluginNotificationService()

    private let lock = NSLock()
    private var history: [PluginNotificationRecord] = []
    private var delegateInstalled = false
    private let maxHistoryCount = 64

    private init() {}

    public static var isSystemNotificationCenterAvailable: Bool {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.lowercased() == "app",
              let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    @discardableResult
    public func post(
        _ rawPayload: PluginNotificationPayload,
        pluginID: String,
        pluginName: String
    ) -> PluginNotificationRecord? {
        let cleanTitle = String(rawPayload.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let cleanBody = String(rawPayload.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty else { return nil }

        let resolvedTitle = cleanTitle.isEmpty ? pluginName : cleanTitle
        let rawSub = rawPayload.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedSubtitle: String? = if !rawSub.isEmpty {
            String(rawSub.prefix(120))
        } else if resolvedTitle != pluginName && !pluginName.isEmpty {
            pluginName
        } else {
            nil
        }

        let normalized = PluginNotificationPayload(
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            body: cleanBody,
            sound: rawPayload.sound
        )
        let canDeliverSystem = Self.isSystemNotificationCenterAvailable
        let record = PluginNotificationRecord(
            pluginID: pluginID,
            pluginName: pluginName,
            payload: normalized,
            deliveredToSystemCenter: canDeliverSystem
        )

        lock.withLock {
            history.insert(record, at: 0)
            if history.count > maxHistoryCount {
                history.removeLast(history.count - maxHistoryCount)
            }
        }

        if canDeliverSystem {
            deliverToUserNotificationCenter(record)
        }
        return record
    }

    public func recentRecords(limit: Int = 20) -> [PluginNotificationRecord] {
        lock.withLock {
            Array(history.prefix(max(1, limit)))
        }
    }

    public func clearHistory() {
        lock.withLock {
            history.removeAll()
        }
    }

    private func deliverToUserNotificationCenter(_ record: PluginNotificationRecord) {
        let center = UNUserNotificationCenter.current()
        lock.withLock {
            if !delegateInstalled {
                center.delegate = ForegroundNotificationBannerDelegate.shared
                delegateInstalled = true
            }
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = record.payload.title
            if let sub = record.payload.subtitle, !sub.isEmpty {
                content.subtitle = sub
            }
            content.body = record.payload.body
            content.threadIdentifier = "lumakey.plugin.\(record.pluginID)"
            if record.payload.sound ?? true {
                content.sound = .default
            }
            let req = UNNotificationRequest(
                identifier: "lk-plug-\(record.pluginID)-\(record.id)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }
}
