import LucentFoundation
import Foundation

public struct MenuBarConfig: Codable, Sendable, Hashable, Equatable {
    public static let fileName = "menubar-config.json"

    public var schemaVersion: Int
    public var orderedItems: [MenuBarBuiltinItemID]
    public var hiddenItems: Set<MenuBarBuiltinItemID>
    public var hideContextualItemsWhenIdle: Bool
    public var foldMaintenanceIntoSubmenu: Bool
    public var showPinnedPluginsSection: Bool

    public init(
        schemaVersion: Int = 1,
        orderedItems: [MenuBarBuiltinItemID] = MenuBarBuiltinItemID.allCases,
        hiddenItems: Set<MenuBarBuiltinItemID> = Self.defaultBalancedHiddenItems,
        hideContextualItemsWhenIdle: Bool = true,
        foldMaintenanceIntoSubmenu: Bool = true,
        showPinnedPluginsSection: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.orderedItems = Self.normalizeOrder(orderedItems)
        self.hiddenItems = hiddenItems.filter { !$0.isLockedVisible }
        self.hideContextualItemsWhenIdle = hideContextualItemsWhenIdle
        self.foldMaintenanceIntoSubmenu = foldMaintenanceIntoSubmenu
        self.showPinnedPluginsSection = showPinnedPluginsSection
    }

    public static let defaultBalancedHiddenItems: Set<MenuBarBuiltinItemID> = [
        .filesFilter, .systemPulseSnapEdge, .networkMonitor, .lumaLinkConsole, .mosSettings
    ]

    public static let compactHiddenItems: Set<MenuBarBuiltinItemID> = [
        .filesFilter, .clipboardFilter, .systemPulseWidget, .systemPulseSnapEdge,
        .menuBarTelemetryReadout, .networkMonitor, .fileWorkspace, .lumaLinkConsole,
        .mosSettings, .backupSync, .cacheCleanup, .reclaimMemory, .switchLanguage, .checkForUpdates
    ]

    public static func preset(_ preset: MenuBarPreset) -> MenuBarConfig {
        switch preset {
        case .compact:
            MenuBarConfig(
                orderedItems: MenuBarBuiltinItemID.allCases,
                hiddenItems: compactHiddenItems,
                hideContextualItemsWhenIdle: true,
                foldMaintenanceIntoSubmenu: true,
                showPinnedPluginsSection: true
            )
        case .balanced:
            MenuBarConfig()
        case .full:
            MenuBarConfig(
                orderedItems: MenuBarBuiltinItemID.allCases,
                hiddenItems: [],
                hideContextualItemsWhenIdle: false,
                foldMaintenanceIntoSubmenu: false,
                showPinnedPluginsSection: true
            )
        }
    }

    public var matchingPreset: MenuBarPreset? {
        for candidate in MenuBarPreset.allCases where Self.preset(candidate) == self {
            return candidate
        }
        return nil
    }

    public func isItemEnabled(_ item: MenuBarBuiltinItemID) -> Bool {
        item.isLockedVisible || !hiddenItems.contains(item)
    }

    public mutating func setItemEnabled(_ item: MenuBarBuiltinItemID, enabled: Bool) {
        guard !item.isLockedVisible else { return }
        if enabled { hiddenItems.remove(item) } else { hiddenItems.insert(item) }
    }

    public mutating func moveItem(_ item: MenuBarBuiltinItemID, offset: Int) {
        guard !item.isLockedVisible else { return }
        var editable = orderedItems.filter { !$0.isLockedVisible }
        guard let idx = editable.firstIndex(of: item) else { return }
        let dest = min(max(0, idx + offset), editable.count - 1)
        guard dest != idx else { return }
        editable.remove(at: idx)
        editable.insert(item, at: dest)
        orderedItems = Self.normalizeOrder(editable + [.settingsCenter, .quitApp])
    }

    public func resolvedLayout(context: MenuBarRuntimeContext = MenuBarRuntimeContext()) -> MenuBarResolvedLayout {
        let hasPendingUpdates = context.availableAppUpdateVersion != nil || context.availablePluginUpdateCount > 0
        let active = orderedItems.filter { item in
            if item == .checkForUpdates && hasPendingUpdates { return true }
            guard isItemEnabled(item) else { return false }
            if hideContextualItemsWhenIdle {
                switch item {
                case .closeAllPins: if context.activePinCount == 0 { return false }
                case .closeAllPluginWindows: if context.activePluginWindowCount == 0 { return false }
                case .systemPulseSnapEdge: if !context.isSystemPulseFloatingVisible { return false }
                case .lumaLinkConsole: if !context.isLumaLinkAvailableOrEnabled { return false }
                default: break
                }
            }
            return true
        }
        let tail = active.filter(\.isLockedVisible)
        let body = active.filter { !$0.isLockedVisible }
        if foldMaintenanceIntoSubmenu {
            return MenuBarResolvedLayout(
                topLevelItems: body.filter { !$0.isMaintenanceItem || ($0 == .checkForUpdates && hasPendingUpdates) },
                maintenanceSubmenuItems: body.filter { $0.isMaintenanceItem && !($0 == .checkForUpdates && hasPendingUpdates) },
                systemTailItems: tail
            )
        }
        return MenuBarResolvedLayout(topLevelItems: body, maintenanceSubmenuItems: [], systemTailItems: tail)
    }

    public static func defaultConfigURL(appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> MenuBarConfig {
        guard let decoded = AtomicJSONStore.decode(MenuBarConfig.self, from: url) else {
            return MenuBarConfig()
        }
        return MenuBarConfig(
            schemaVersion: decoded.schemaVersion,
            orderedItems: decoded.orderedItems,
            hiddenItems: decoded.hiddenItems,
            hideContextualItemsWhenIdle: decoded.hideContextualItemsWhenIdle,
            foldMaintenanceIntoSubmenu: decoded.foldMaintenanceIntoSubmenu,
            showPinnedPluginsSection: decoded.showPinnedPluginsSection
        )
    }

    public func save(to url: URL = defaultConfigURL(), notify: Bool = true) {
        AtomicJSONStore.save(self, to: url, notification: notify ? .lucentMenuBarConfigDidChange : nil)
    }

    private static func normalizeOrder(_ raw: [MenuBarBuiltinItemID]) -> [MenuBarBuiltinItemID] {
        var seen = Set<MenuBarBuiltinItemID>()
        var nonLocked: [MenuBarBuiltinItemID] = []
        for item in raw where !item.isLockedVisible && seen.insert(item).inserted {
            nonLocked.append(item)
        }
        for item in MenuBarBuiltinItemID.allCases where !item.isLockedVisible && seen.insert(item).inserted {
            nonLocked.append(item)
        }
        return nonLocked + [.settingsCenter, .quitApp]
    }
}
