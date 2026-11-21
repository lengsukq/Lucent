import AppKit
import Combine
import Foundation
import LucentCore

extension Notification.Name {
    static let lucentThemeDidChange = Notification.Name("app.lucent.themeDidChange")
}

private struct ThemeRuntimeSnapshot: Sendable, Equatable {
    var selectedTheme: AppThemeID
    var followSystemAppearance: Bool
    var resolvedIsDark: Bool

    var effectiveTheme: AppThemeID {
        resolvedIsDark ? .prismPulse : .pureFrost
    }
}

private final class ThemeSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ThemeRuntimeSnapshot

    init(_ initial: ThemeRuntimeSnapshot) {
        self.value = initial
    }

    func get() -> ThemeRuntimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ next: ThemeRuntimeSnapshot) {
        lock.lock()
        value = next
        lock.unlock()
    }
}

private func detectInitialSystemDark() -> Bool {
    UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
}

private let globalThemeSnapshotBox: ThemeSnapshotBox = {
    let cfg = AppThemeConfig.load()
    let isDark = cfg.followSystemAppearance ? detectInitialSystemDark() : (cfg.selectedTheme == .prismPulse)
    return ThemeSnapshotBox(
        ThemeRuntimeSnapshot(
            selectedTheme: cfg.selectedTheme,
            followSystemAppearance: cfg.followSystemAppearance,
            resolvedIsDark: isDark
        )
    )
}()

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    nonisolated static var currentSnapshot: AppThemeID {
        globalThemeSnapshotBox.get().effectiveTheme
    }

    nonisolated static var resolvedIsDarkSnapshot: Bool {
        globalThemeSnapshotBox.get().resolvedIsDark
    }

    @Published private(set) var current: AppThemeID
    @Published private(set) var followSystemAppearance: Bool
    @Published private(set) var resolvedIsDark: Bool

    private var appearanceObservation: NSKeyValueObservation?
    private var hasBootstrapped = false

    var effectiveTheme: AppThemeID {
        resolvedIsDark ? .prismPulse : .pureFrost
    }

    private init() {
        let initial = globalThemeSnapshotBox.get()
        self.current = initial.selectedTheme
        self.followSystemAppearance = initial.followSystemAppearance
        self.resolvedIsDark = initial.resolvedIsDark
    }

    func bootstrapAppearance() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        applyNSApplicationAppearance()
        installEffectiveAppearanceObserver()
        syncResolvedAppearance(notify: false)
    }

    func apply(_ theme: AppThemeID, persist: Bool = true) {
        let shouldPersistChange = persist
        if current != theme { current = theme }
        if followSystemAppearance { followSystemAppearance = false }
        applyNSApplicationAppearance()
        syncResolvedAppearance(notify: true)
        if shouldPersistChange {
            AppThemeConfig(selectedTheme: current, followSystemAppearance: followSystemAppearance).save()
        }
    }

    func setFollowSystemAppearance(_ enabled: Bool, persist: Bool = true) {
        if followSystemAppearance != enabled {
            followSystemAppearance = enabled
        }
        applyNSApplicationAppearance()
        syncResolvedAppearance(notify: true)
        if persist {
            AppThemeConfig(selectedTheme: current, followSystemAppearance: followSystemAppearance).save()
        }
    }

    func cycle() -> AppThemeID {
        let next = effectiveTheme.next
        apply(next, persist: true)
        return next
    }

    func reloadFromDisk() {
        let loaded = AppThemeConfig.load()
        if current != loaded.selectedTheme { current = loaded.selectedTheme }
        if followSystemAppearance != loaded.followSystemAppearance {
            followSystemAppearance = loaded.followSystemAppearance
        }
        applyNSApplicationAppearance()
        syncResolvedAppearance(notify: true)
    }

    private func applyNSApplicationAppearance() {
        guard let app = NSApp else { return }
        if followSystemAppearance {
            app.appearance = nil
        } else {
            app.appearance = NSAppearance(named: current == .prismPulse ? .darkAqua : .aqua)
        }
    }

    private func installEffectiveAppearanceObserver() {
        guard appearanceObservation == nil, let app = NSApp else { return }
        appearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.followSystemAppearance else { return }
                self.handleSystemAppearanceDidChange()
            }
        }
    }

    private func handleSystemAppearanceDidChange() {
        let nextDark = resolveCurrentDarkMode()
        guard nextDark != resolvedIsDark else { return }
        syncResolvedAppearance(notify: true)
    }

    private func resolveCurrentDarkMode() -> Bool {
        if !followSystemAppearance {
            return current == .prismPulse
        }
        if let app = NSApp {
            return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        return detectInitialSystemDark()
    }

    private func syncResolvedAppearance(notify: Bool) {
        let nextDark = resolveCurrentDarkMode()
        let nextSnapshot = ThemeRuntimeSnapshot(
            selectedTheme: current,
            followSystemAppearance: followSystemAppearance,
            resolvedIsDark: nextDark
        )
        globalThemeSnapshotBox.set(nextSnapshot)
        if resolvedIsDark != nextDark {
            resolvedIsDark = nextDark
        }
        if notify {
            NotificationCenter.default.post(name: .lucentThemeDidChange, object: nextSnapshot.effectiveTheme)
        }
    }
}
