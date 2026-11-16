import AppKit
import Combine
import Foundation
import LumakeyCore

extension Notification.Name {
    static let lumakeyThemeDidChange = Notification.Name("app.lumakey.themeDidChange")
}

private final class ThemeSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AppThemeID

    init(_ initial: AppThemeID) {
        self.value = initial
    }

    func get() -> AppThemeID {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ next: AppThemeID) {
        lock.lock()
        value = next
        lock.unlock()
    }
}

private let globalThemeSnapshotBox = ThemeSnapshotBox(AppThemeConfig.load().selectedTheme)

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    nonisolated static var currentSnapshot: AppThemeID {
        globalThemeSnapshotBox.get()
    }

    @Published private(set) var current: AppThemeID

    private init() {
        let initial = globalThemeSnapshotBox.get()
        self.current = initial
    }

    func apply(_ theme: AppThemeID, persist: Bool = true) {
        globalThemeSnapshotBox.set(theme)
        if current != theme {
            current = theme
        }
        if persist {
            AppThemeConfig(selectedTheme: theme).save()
        }
        NotificationCenter.default.post(name: .lumakeyThemeDidChange, object: theme)
    }

    func cycle() -> AppThemeID {
        let next = current.next
        apply(next, persist: true)
        return next
    }

    func reloadFromDisk() {
        let loaded = AppThemeConfig.load().selectedTheme
        apply(loaded, persist: false)
    }
}
