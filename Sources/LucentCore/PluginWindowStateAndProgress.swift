import LucentFoundation
import Foundation

public struct PluginExecutionProgress: Codable, Sendable, Hashable, Equatable {
    public let pluginID: String
    public let message: String
    public let fraction: Double?

    public init(pluginID: String, message: String, fraction: Double? = nil) {
        self.pluginID = pluginID
        self.message = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        if let fraction, fraction.isFinite {
            self.fraction = min(max(fraction, 0.0), 1.0)
        } else {
            self.fraction = nil
        }
    }
}

public struct PluginSavedWindowFrame: Codable, Sendable, Hashable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var opacity: Double?
    public var pinOnTop: Bool?
    public var updatedAtEpoch: Double

    public init(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        opacity: Double? = nil,
        pinOnTop: Bool? = nil,
        updatedAtEpoch: Double = Date().timeIntervalSince1970
    ) {
        self.x = x
        self.y = y
        self.width = PluginCustomWindowSpec.clampWidth(width)
        self.height = PluginCustomWindowSpec.clampHeight(height)
        self.opacity = opacity.map { min(max($0, PluginCustomWindowSpec.minOpacity), 1.0) }
        self.pinOnTop = pinOnTop
        self.updatedAtEpoch = updatedAtEpoch
    }
}

public enum PluginWindowFrameStore {
    public static let fileName = "window-frames.json"
    private static let lock = NSLock()

    public static func fileURL(for pluginID: String, in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()) -> URL? {
        PluginDataPaths.dataDirectory(for: pluginID, pluginsRoot: pluginsRoot)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func loadFrames(
        for pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) -> [String: PluginSavedWindowFrame] {
        lock.withLock {
            guard let url = fileURL(for: pluginID, in: pluginsRoot),
                  let data = try? Data(contentsOf: url),
                  data.count <= 65_536,
                  let decoded = try? JSONDecoder().decode([String: PluginSavedWindowFrame].self, from: data)
            else { return [:] }
            return decoded
        }
    }

    public static func loadFrame(
        pluginID: String,
        windowID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) -> PluginSavedWindowFrame? {
        let key = PluginCustomWindowSpec.sanitizeWindowID(windowID)
        return loadFrames(for: pluginID, in: pluginsRoot)[key]
    }

    public static func saveFrame(
        _ frame: PluginSavedWindowFrame,
        pluginID: String,
        windowID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) {
        guard PluginSystem.isSafePluginID(pluginID) else { return }
        let key = PluginCustomWindowSpec.sanitizeWindowID(windowID)
        lock.withLock {
            guard let dir = PluginDataPaths.ensureDataDirectory(for: pluginID, pluginsRoot: pluginsRoot) else { return }
            let url = dir.appendingPathComponent(fileName, isDirectory: false)
            var existing: [String: PluginSavedWindowFrame] = [:]
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: PluginSavedWindowFrame].self, from: data) {
                existing = decoded
            }
            existing[key] = frame
            if existing.count > 16,
               let oldest = existing.min(by: { $0.value.updatedAtEpoch < $1.value.updatedAtEpoch })?.key {
                existing.removeValue(forKey: oldest)
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let out = try? enc.encode(existing) {
                try? out.write(to: url, options: .atomic)
            }
        }
    }

    public static func clearFrames(
        for pluginID: String,
        in pluginsRoot: URL = PluginSystem.defaultPluginsDirectory()
    ) {
        lock.withLock {
            guard let url = fileURL(for: pluginID, in: pluginsRoot) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public extension PluginCustomWindowSpec {
    func applyingSavedFrame(
        _ saved: PluginSavedWindowFrame?,
        hasExplicitSize: Bool = false,
        hasExplicitOrigin: Bool = false,
        hasExplicitOpacity: Bool = false,
        hasExplicitPin: Bool = false,
        canRestoreFloatingPin: Bool = false
    ) -> PluginCustomWindowSpec {
        guard let saved else { return self }
        let resolvedW = hasExplicitSize ? width : (resizable ? saved.width : width)
        let resolvedH = hasExplicitSize ? height : (resizable ? saved.height : height)
        let resolvedX = hasExplicitOrigin ? x : saved.x
        let resolvedY = hasExplicitOrigin ? y : saved.y
        let resolvedOpacity = hasExplicitOpacity ? opacity : (saved.opacity ?? opacity)
        let resolvedPin: Bool = if hasExplicitPin {
            pinOnTop
        } else if let savedPin = saved.pinOnTop, (canRestoreFloatingPin || !savedPin) {
            savedPin
        } else {
            pinOnTop
        }
        return PluginCustomWindowSpec(
            pluginID: pluginID,
            windowID: windowID,
            title: title,
            htmlPath: htmlPath,
            html: html,
            width: resolvedW,
            height: resolvedH,
            minWidth: minWidth,
            minHeight: minHeight,
            resizable: resizable,
            chrome: chrome,
            transparent: transparent,
            pinOnTop: resolvedPin,
            clickThrough: clickThrough,
            showInDock: showInDock,
            opacity: resolvedOpacity,
            x: resolvedX,
            y: resolvedY,
            initialStateJSON: initialStateJSON
        )
    }
}

public struct PluginPermissionDiff: Sendable, Hashable, Equatable {
    public let addedCapabilities: [PluginCapability]
    public let addedResourceScopes: [PluginResourceScope]

    public init(addedCapabilities: [PluginCapability], addedResourceScopes: [PluginResourceScope]) {
        self.addedCapabilities = addedCapabilities
        self.addedResourceScopes = addedResourceScopes
    }

    public var hasEscalation: Bool {
        !addedCapabilities.isEmpty || !addedResourceScopes.isEmpty
    }
}

public struct PluginStoreAvailableUpdate: Sendable, Hashable, Identifiable {
    public var id: String { "\(store.id)::\(item.id)" }
    public let store: PluginStoreSubscription
    public let item: PluginStoreItem
    public let installedVersion: String
    public let permissionDiff: PluginPermissionDiff

    public init(
        store: PluginStoreSubscription,
        item: PluginStoreItem,
        installedVersion: String,
        permissionDiff: PluginPermissionDiff
    ) {
        self.store = store
        self.item = item
        self.installedVersion = installedVersion
        self.permissionDiff = permissionDiff
    }
}

public extension PluginStoreService {
    static func checkHostCompatibility(
        minAppVersion: String?,
        pluginID: String,
        hostVersion: String = PluginSystem.currentHostAppVersion
    ) throws {
        guard let rawMin = minAppVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawMin.isEmpty else { return }
        if PluginVersionComparator.compare(hostVersion, rawMin) == .orderedAscending {
            throw LucentError.pluginInvalid(
                L10n.pick(
                    "插件 '\(pluginID)' 需要 Lucent v\(rawMin) 及以上版本（当前宿主版本 v\(hostVersion)）",
                    "Plugin '\(pluginID)' requires Lucent v\(rawMin)+ (current v\(hostVersion))"
                )
            )
        }
    }

    static func permissionDiff(
        for item: PluginStoreItem,
        installedPlugins: [PluginDescriptor]
    ) -> PluginPermissionDiff {
        guard let existing = installedPlugins.first(where: { !$0.isBuiltin && $0.id == item.id }) else {
            return PluginPermissionDiff(addedCapabilities: [], addedResourceScopes: [])
        }
        let oldCaps = Set(existing.declaredCapabilities)
        let oldScopes = Set(existing.declaredResourceScopes)
        let addedCaps = item.declaredCapabilities.filter { !oldCaps.contains($0) }
        let addedScopes = item.declaredResourceScopes.filter { !oldScopes.contains($0) }
        return PluginPermissionDiff(addedCapabilities: addedCaps, addedResourceScopes: addedScopes)
    }

    static func availableUpdates(
        in stores: [PluginStoreSubscription],
        installedPlugins: [PluginDescriptor]
    ) -> [PluginStoreAvailableUpdate] {
        var seenPluginIDs = Set<String>()
        var results: [PluginStoreAvailableUpdate] = []
        for store in stores {
            for item in store.manifest.plugins {
                guard case .updateAvailable(let installed, _) = installState(for: item, installedPlugins: installedPlugins) else {
                    continue
                }
                guard seenPluginIDs.insert(item.id).inserted else { continue }
                let diff = permissionDiff(for: item, installedPlugins: installedPlugins)
                results.append(PluginStoreAvailableUpdate(
                    store: store,
                    item: item,
                    installedVersion: installed,
                    permissionDiff: diff
                ))
            }
        }
        return results
    }

    static func refreshAllStores(
        appSupportDirectory: URL = BackupArchiveService.defaultAppSupportDirectory(),
        fetcher: PluginURLFetcher = PluginStoreSniffer.defaultFetcher
    ) async -> (stores: [PluginStoreSubscription], errors: [String: String]) {
        let current = loadCatalog(appSupportDirectory: appSupportDirectory).stores
        var errors: [String: String] = [:]
        for sub in current {
            do {
                _ = try await refreshStore(storeID: sub.id, appSupportDirectory: appSupportDirectory, fetcher: fetcher)
            } catch {
                errors[sub.id] = (error as? LucentError)?.diagnostic.reason ?? error.localizedDescription
            }
        }
        return (loadCatalog(appSupportDirectory: appSupportDirectory).stores, errors)
    }
}
