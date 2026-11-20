import Foundation
import LucentFoundation

public struct PersistedPluginCustomWindow: Codable, Sendable, Hashable, Equatable {
    public static let maxInlineHTMLBytes = 65_536

    public var pluginID: String
    public var windowID: String
    public var spec: PluginCustomWindowSpec
    public var updatedAtEpoch: Double

    public init(
        pluginID: String,
        windowID: String,
        spec: PluginCustomWindowSpec,
        updatedAtEpoch: Double = Date().timeIntervalSince1970
    ) {
        self.pluginID = pluginID
        self.windowID = PluginCustomWindowSpec.sanitizeWindowID(windowID)
        self.spec = PluginCustomWindowSpec(
            pluginID: pluginID,
            windowID: self.windowID,
            title: spec.title,
            htmlPath: spec.htmlPath,
            html: spec.html,
            width: spec.width,
            height: spec.height,
            minWidth: spec.minWidth,
            minHeight: spec.minHeight,
            resizable: spec.resizable,
            chrome: spec.chrome,
            transparent: spec.transparent,
            pinOnTop: spec.pinOnTop,
            clickThrough: spec.clickThrough,
            showInDock: spec.showInDock,
            opacity: spec.opacity,
            x: nil,
            y: nil,
            initialStateJSON: spec.initialStateJSON
        )
        self.updatedAtEpoch = updatedAtEpoch
    }

    public var isPersistable: Bool {
        guard PluginSystem.isSafePluginID(pluginID) else { return false }
        if let path = spec.htmlPath, !path.isEmpty {
            return PluginCustomWindowSpec.isSafeRelativeAssetPath(path)
        }
        if let rawHTML = spec.html, !rawHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawHTML.utf8.count <= Self.maxInlineHTMLBytes
        }
        return false
    }
}

public struct PersistedPinnedImageWindow: Codable, Sendable, Hashable, Equatable {
    public var id: String
    public var imagePath: String
    public var isManagedSessionCopy: Bool
    public var isCutout: Bool
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var opacity: Double
    public var isClickThrough: Bool
    public var updatedAtEpoch: Double

    public init(
        id: String,
        imagePath: String,
        isManagedSessionCopy: Bool,
        isCutout: Bool,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        opacity: Double,
        isClickThrough: Bool,
        updatedAtEpoch: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.imagePath = imagePath
        self.isManagedSessionCopy = isManagedSessionCopy
        self.isCutout = isCutout
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = max(96, width.isFinite ? width : 320)
        self.height = max(64, height.isFinite ? height : 220)
        self.opacity = min(max(opacity.isFinite ? opacity : 0.98, 0.20), 1.0)
        self.isClickThrough = isClickThrough
        self.updatedAtEpoch = updatedAtEpoch
    }
}

public struct PersistedFloatingWindowSession: Codable, Sendable, Equatable {
    public static let maxPluginCustomWindows = 12
    public static let maxPluginFloatingPanels = 8
    public static let maxPinnedImages = 16

    public var schemaVersion: Int
    public var pluginCustomWindows: [PersistedPluginCustomWindow]
    public var pluginFloatingPanels: [PluginFloatingPanelRequest]
    public var pinnedImages: [PersistedPinnedImageWindow]

    public init(
        schemaVersion: Int = 1,
        pluginCustomWindows: [PersistedPluginCustomWindow] = [],
        pluginFloatingPanels: [PluginFloatingPanelRequest] = [],
        pinnedImages: [PersistedPinnedImageWindow] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pluginCustomWindows = Array(pluginCustomWindows.filter(\.isPersistable).suffix(Self.maxPluginCustomWindows))
        self.pluginFloatingPanels = Array(pluginFloatingPanels.suffix(Self.maxPluginFloatingPanels))
        self.pinnedImages = Array(pinnedImages.suffix(Self.maxPinnedImages))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1,
            pluginCustomWindows: (try? c.decodeIfPresent([PersistedPluginCustomWindow].self, forKey: .pluginCustomWindows)) ?? [],
            pluginFloatingPanels: (try? c.decodeIfPresent([PluginFloatingPanelRequest].self, forKey: .pluginFloatingPanels)) ?? [],
            pinnedImages: (try? c.decodeIfPresent([PersistedPinnedImageWindow].self, forKey: .pinnedImages)) ?? []
        )
    }
}

public enum FloatingWindowSessionStore {
    public static let fileName = "floating-window-session.json"
    private static let lock = NSLock()

    public static func defaultURL(appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()) -> URL {
        LucentAppPaths.configFileURL(fileName, in: appSupportDirectory)
    }

    public static func pinnedSessionDirectory(
        appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()
    ) -> URL {
        appSupportDirectory.appendingPathComponent("PinnedSession", isDirectory: true)
    }

    public static func load(from url: URL = defaultURL()) -> PersistedFloatingWindowSession {
        lock.withLock {
            AtomicJSONStore.load(PersistedFloatingWindowSession.self, from: url, fallback: PersistedFloatingWindowSession())
        }
    }

    @discardableResult
    public static func save(_ session: PersistedFloatingWindowSession, to url: URL = defaultURL()) -> Bool {
        lock.withLock {
            AtomicJSONStore.save(session, to: url)
        }
    }

    public static func update(at url: URL = defaultURL(), _ mutate: (inout PersistedFloatingWindowSession) -> Void) {
        lock.withLock {
            var current = AtomicJSONStore.load(
                PersistedFloatingWindowSession.self,
                from: url,
                fallback: PersistedFloatingWindowSession()
            )
            mutate(&current)
            let normalized = PersistedFloatingWindowSession(
                schemaVersion: current.schemaVersion,
                pluginCustomWindows: current.pluginCustomWindows,
                pluginFloatingPanels: current.pluginFloatingPanels,
                pinnedImages: current.pinnedImages
            )
            _ = AtomicJSONStore.save(normalized, to: url)
        }
    }

    public static func replacePluginCustomWindows(
        _ windows: [PersistedPluginCustomWindow],
        at url: URL = defaultURL()
    ) {
        update(at: url) { $0.pluginCustomWindows = windows.filter(\.isPersistable) }
    }

    public static func upsertPluginFloatingPanel(
        _ request: PluginFloatingPanelRequest,
        at url: URL = defaultURL()
    ) {
        update(at: url) { session in
            session.pluginFloatingPanels.removeAll { $0.pluginID == request.pluginID }
            session.pluginFloatingPanels.append(request)
        }
    }

    public static func removePluginFloatingPanel(pluginID: String, at url: URL = defaultURL()) {
        update(at: url) { session in
            session.pluginFloatingPanels.removeAll { $0.pluginID == pluginID }
        }
    }

    public static func replacePinnedImages(
        _ pins: [PersistedPinnedImageWindow],
        at url: URL = defaultURL()
    ) {
        update(at: url) { $0.pinnedImages = pins }
    }

    public static func pruneOrphanPinnedFiles(
        keeping activePaths: Set<String>,
        in directory: URL = pinnedSessionDirectory()
    ) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let normalizedKeep = Set(activePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        for file in files {
            let stdPath = file.standardizedFileURL.path
            if !normalizedKeep.contains(stdPath) {
                try? fm.removeItem(at: file)
            }
        }
    }
}

public enum InitialLaunchAction: String, Sendable, Equatable {
    case silent
    case playIntroThenShowLauncher
    case playIntroThenStaySilent
    case showLauncherImmediately
}

public enum LaunchPresentationPolicy {
    public static func resolve(
        launchSilentlyInMenuBar: Bool,
        showLaunchIntroAnimation: Bool,
        reduceMotion: Bool = false
    ) -> InitialLaunchAction {
        if showLaunchIntroAnimation && !reduceMotion {
            return launchSilentlyInMenuBar ? .playIntroThenStaySilent : .playIntroThenShowLauncher
        }
        return launchSilentlyInMenuBar ? .silent : .showLauncherImmediately
    }
}
