import LucentFoundation
import Foundation

public extension Notification.Name {
    static let lucentHomeLayoutDidChange = Notification.Name(LucentIdentifiers.scoped("homeLayoutDidChange"))
}

public enum HomeLayoutError: Error, LocalizedError, Sendable, Equatable {
    case invalidItem(String)
    case invalidProfileID(String)
    case duplicateProfileID(String)
    case profileLimitReached
    case cannotDeleteLastProfile
    case shelfLimitReached

    public var errorDescription: String? {
        switch self {
        case .invalidItem(let reason): reason
        case .invalidProfileID(let id): "Invalid profile ID '\(id)'."
        case .duplicateProfileID(let id): "Profile '\(id)' already exists."
        case .profileLimitReached: "Maximum number of home profiles (8) reached."
        case .cannotDeleteLastProfile: "Cannot delete the last remaining home profile."
        case .shelfLimitReached: "Maximum number of pill shelves (6) reached."
        }
    }
}

public struct HomeLayoutConfig: Codable, Sendable, Hashable, Equatable {
    public static let fileName = "home-layout.json"
    public static let distributedReloadNotificationName = Notification.Name(LucentIdentifiers.scoped("homeLayoutDidChange.distributed"))

    public var schemaVersion: Int
    public var activeProfileID: String
    public var profiles: [HomeProfile]
    public var migratedLegacyPinnedApps: Bool
    public var lastUndoProfile: HomeProfile?

    public init(
        schemaVersion: Int = 1,
        activeProfileID: String = HomeProfile.defaultProfileID,
        profiles: [HomeProfile] = [HomeProfile.makePreset(.balanced)],
        migratedLegacyPinnedApps: Bool = false,
        lastUndoProfile: HomeProfile? = nil
    ) {
        self.schemaVersion = schemaVersion
        let normalized = Self.normalizeProfiles(profiles)
        self.profiles = normalized
        self.activeProfileID = normalized.contains(where: { $0.id == activeProfileID }) ? activeProfileID : normalized[0].id
        self.migratedLegacyPinnedApps = migratedLegacyPinnedApps
        self.lastUndoProfile = lastUndoProfile
    }

    public var activeProfileIndex: Int {
        profiles.firstIndex(where: { $0.id == activeProfileID }) ?? 0
    }

    public var activeProfile: HomeProfile {
        get { profiles[activeProfileIndex] }
        set {
            let idx = activeProfileIndex
            lastUndoProfile = profiles[idx]
            var updated = newValue
            updated.id = profiles[idx].id
            profiles[idx] = updated
        }
    }

    @discardableResult
    public mutating func selectProfile(id: String) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        activeProfileID = id
        return true
    }

    @discardableResult
    public mutating func createProfile(
        id: String? = nil,
        name: String,
        symbol: String = "sparkles",
        preset: HomeLayoutPreset = .balanced,
        pinnedAppPaths: [String] = [],
        activate: Bool = true
    ) throws -> HomeProfile {
        guard profiles.count < 8 else { throw HomeLayoutError.profileLimitReached }
        let resolvedID = id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ?? "profile-\(UUID().uuidString.prefix(6).lowercased())"
        guard HomeLaunchSecurity.isSafeIdentifier(resolvedID, maxLength: 40) else {
            throw HomeLayoutError.invalidProfileID(resolvedID)
        }
        guard !profiles.contains(where: { $0.id == resolvedID }) else {
            throw HomeLayoutError.duplicateProfileID(resolvedID)
        }
        let created = HomeProfile.makePreset(preset, id: resolvedID, name: name, symbol: symbol, pinnedAppPaths: pinnedAppPaths)
        profiles.append(created)
        if activate { activeProfileID = created.id }
        return created
    }

    @discardableResult
    public mutating func deleteProfile(id: String) throws -> Bool {
        guard profiles.count > 1 else { throw HomeLayoutError.cannotDeleteLastProfile }
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: idx)
        if activeProfileID == id { activeProfileID = profiles[0].id }
        return true
    }

    public mutating func applyPreset(_ preset: HomeLayoutPreset, toProfileID: String? = nil, preserveDockItems: Bool = true) {
        let targetID = toProfileID ?? activeProfileID
        guard let idx = profiles.firstIndex(where: { $0.id == targetID }) else { return }
        let previous = profiles[idx]
        lastUndoProfile = previous
        var fresh = HomeProfile.makePreset(preset, id: previous.id, name: previous.name, symbol: previous.symbol)
        if preserveDockItems && !previous.dockItems.isEmpty { fresh.dockItems = previous.dockItems }
        profiles[idx] = fresh
    }

    @discardableResult
    public mutating func undoLastChange() -> Bool {
        guard let snapshot = lastUndoProfile,
              let idx = profiles.firstIndex(where: { $0.id == snapshot.id }) else { return false }
        profiles[idx] = snapshot
        activeProfileID = snapshot.id
        lastUndoProfile = nil
        return true
    }

    public mutating func upsertItem(
        _ item: HomeLaunchItem,
        in destination: HomeItemDestination,
        at index: Int? = nil,
        shelfTitle: String? = nil
    ) throws {
        if let err = HomeLaunchSecurity.validateItem(item) { throw HomeLayoutError.invalidItem(err) }
        var profile = activeProfile
        switch destination {
        case .bento: Self.upsert(item, into: &profile.bentoItems, at: index, cap: 16)
        case .dock: Self.upsert(item, into: &profile.dockItems, at: index, cap: 24)
        case .shelf(let shelfID):
            if let sIdx = profile.pillShelves.firstIndex(where: { $0.id == shelfID }) {
                Self.upsert(item, into: &profile.pillShelves[sIdx].items, at: index, cap: 24)
                if let shelfTitle, !shelfTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.pillShelves[sIdx].title = String(shelfTitle.prefix(32))
                }
            } else {
                guard profile.pillShelves.count < 6 else { throw HomeLayoutError.shelfLimitReached }
                profile.pillShelves.append(HomePillShelf(
                    id: shelfID, title: shelfTitle ?? shelfID, symbol: "bookmark.fill",
                    accentColor: item.accentColor ?? "cyan", items: [item]
                ))
            }
        case .utilityChips: Self.upsert(item, into: &profile.utilityChips, at: index, cap: 12)
        case .utilityRight: Self.upsert(item, into: &profile.utilityRightItems, at: index, cap: 6)
        }
        activeProfile = profile
    }

    @discardableResult
    public mutating func removeItem(id: String, from destination: HomeItemDestination? = nil) -> Int {
        var profile = activeProfile
        var removed = 0
        func strip(_ list: inout [HomeLaunchItem]) {
            let before = list.count; list.removeAll { $0.id == id }; removed += (before - list.count)
        }
        if let destination {
            switch destination {
            case .bento: strip(&profile.bentoItems)
            case .dock: strip(&profile.dockItems)
            case .shelf(let shelfID):
                if let idx = profile.pillShelves.firstIndex(where: { $0.id == shelfID }) { strip(&profile.pillShelves[idx].items) }
            case .utilityChips: strip(&profile.utilityChips)
            case .utilityRight: strip(&profile.utilityRightItems)
            }
        } else {
            strip(&profile.bentoItems); strip(&profile.dockItems)
            for idx in profile.pillShelves.indices { strip(&profile.pillShelves[idx].items) }
            strip(&profile.utilityChips); strip(&profile.utilityRightItems)
        }
        if removed > 0 { activeProfile = profile }
        return removed
    }

    @discardableResult
    public mutating func moveItem(id: String, in destination: HomeItemDestination, offset: Int) -> Bool {
        guard offset != 0 else { return false }
        var profile = activeProfile
        let moved: Bool = switch destination {
        case .bento: Self.move(id: id, in: &profile.bentoItems, offset: offset)
        case .dock: Self.move(id: id, in: &profile.dockItems, offset: offset)
        case .shelf(let shelfID):
            profile.pillShelves.firstIndex(where: { $0.id == shelfID })
                .map { Self.move(id: id, in: &profile.pillShelves[$0].items, offset: offset) } ?? false
        case .utilityChips: Self.move(id: id, in: &profile.utilityChips, offset: offset)
        case .utilityRight: Self.move(id: id, in: &profile.utilityRightItems, offset: offset)
        }
        if moved { activeProfile = profile }
        return moved
    }

    private static func upsert(_ item: HomeLaunchItem, into list: inout [HomeLaunchItem], at index: Int?, cap: Int) {
        if let existing = list.firstIndex(where: { $0.id == item.id }) {
            list.remove(at: existing)
            list.insert(item, at: index.map { min(max(0, $0), list.count) } ?? min(existing, list.count))
            return
        }
        if list.count >= cap { list.removeLast() }
        list.insert(item, at: index.map { min(max(0, $0), list.count) } ?? list.count)
    }

    private static func move(id: String, in list: inout [HomeLaunchItem], offset: Int) -> Bool {
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return false }
        let dest = min(max(0, idx + offset), list.count - 1)
        guard dest != idx else { return false }
        list.insert(list.remove(at: idx), at: dest)
        return true
    }

    private static func normalizeProfiles(_ raw: [HomeProfile]) -> [HomeProfile] {
        var seen = Set<String>(); var out: [HomeProfile] = []
        for p in raw where seen.insert(p.id).inserted { out.append(p); if out.count >= 8 { break } }
        return out.isEmpty ? [HomeProfile.makePreset(.balanced)] : out
    }

    public static func defaultConfigURL(appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func scopedConfigURL(forPluginsRoot pluginsRoot: URL) -> URL {
        let std = pluginsRoot.standardizedFileURL
        if std.lastPathComponent == "Plugins" {
            return std.deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: false)
        }
        return std.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func loadOrBootstrap(from url: URL = defaultConfigURL(), legacyPinnedAppIDs: [String] = []) -> HomeLayoutConfig {
        if var decoded = AtomicJSONStore.decode(HomeLayoutConfig.self, from: url) {
            if !decoded.migratedLegacyPinnedApps && !legacyPinnedAppIDs.isEmpty {
                decoded.seedLegacyPinnedAppsIfEmpty(legacyPinnedAppIDs)
                decoded.save(to: url, notifyInProcess: false, notifyCrossProcess: false)
            }
            return decoded
        }
        var fresh = HomeLayoutConfig(
            profiles: [HomeProfile.makePreset(.balanced, pinnedAppPaths: legacyPinnedAppIDs)],
            migratedLegacyPinnedApps: !legacyPinnedAppIDs.isEmpty
        )
        if !legacyPinnedAppIDs.isEmpty { fresh.seedLegacyPinnedAppsIfEmpty(legacyPinnedAppIDs) }
        return fresh
    }

    public mutating func seedLegacyPinnedAppsIfEmpty(_ appPaths: [String]) {
        guard !migratedLegacyPinnedApps else { return }
        migratedLegacyPinnedApps = true
        guard !appPaths.isEmpty, profiles[0].dockItems.isEmpty else { return }
        profiles[0].dockItems = HomeProfile.dockItems(fromAppPaths: appPaths)
    }

    public func save(to url: URL = defaultConfigURL(), notifyInProcess: Bool = true, notifyCrossProcess: Bool = false) {
        guard AtomicJSONStore.save(
            self, to: url,
            formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
            notification: notifyInProcess ? .lucentHomeLayoutDidChange : nil
        ) else { return }
        if notifyCrossProcess {
            DistributedNotificationCenter.default().postNotificationName(
                Self.distributedReloadNotificationName, object: url.standardizedFileURL.path, userInfo: nil, deliverImmediately: true
            )
        }
    }
}
