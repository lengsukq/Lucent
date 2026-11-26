import Foundation
import LucentFoundation
import LucentSearch

public extension Notification.Name {
    static let lucentGeneralPreferencesDidChange = Notification.Name(LucentIdentifiers.scoped("generalPreferencesDidChange"))
}

public enum PersistedEverythingScope: Codable, Sendable, Hashable, Equatable {
    case allVolumes
    case quickUserFolders
    case home
    case volume(name: String, mountPath: String)

    private enum KindKey: String, Codable {
        case allVolumes
        case quickUserFolders
        case home
        case volume
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case mountPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(KindKey.self, forKey: .kind)) ?? .allVolumes
        switch kind {
        case .allVolumes:
            self = .allVolumes
        case .quickUserFolders:
            self = .quickUserFolders
        case .home:
            self = .home
        case .volume:
            let path = (try? c.decode(String.self, forKey: .mountPath)) ?? ""
            guard !path.isEmpty else {
                self = .allVolumes
                return
            }
            let fallbackName = URL(fileURLWithPath: path).lastPathComponent
            let name = (try? c.decode(String.self, forKey: .name)) ?? fallbackName
            self = .volume(name: name.isEmpty ? path : name, mountPath: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allVolumes:
            try c.encode(KindKey.allVolumes, forKey: .kind)
        case .quickUserFolders:
            try c.encode(KindKey.quickUserFolders, forKey: .kind)
        case .home:
            try c.encode(KindKey.home, forKey: .kind)
        case .volume(let name, let mountPath):
            try c.encode(KindKey.volume, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(mountPath, forKey: .mountPath)
        }
    }

    public var scopeID: String {
        switch self {
        case .allVolumes: "all"
        case .quickUserFolders: "quick"
        case .home: "home"
        case .volume(_, let path): "vol:\(path)"
        }
    }

    public func resolveFilteredRoots(
        externals: [VolumeSummary],
        excludedPaths: Set<String>
    ) -> (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let normalizedExcl = EverythingIndex.normalizedExcludedSet(excludedPaths)
        var seen = Set<String>()

        func filterValid(_ urls: [URL]) -> [URL] {
            urls.filter { url in
                let std = url.standardizedFileURL.path
                guard !EverythingIndex.isPathExcluded(std, excludedPaths: normalizedExcl),
                      seen.insert(std).inserted else { return false }
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: std, isDirectory: &isDir) && isDir.boolValue
            }
        }

        switch self {
        case .allVolumes:
            let nonSMB = externals.filter { $0.formatKind != .smb }
            let fastRaw = [home] + nonSMB.filter { !VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            let slowRaw = nonSMB.filter { VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            let fast = filterValid(fastRaw)
            let slow = filterValid(slowRaw)
            return (fast, slow, fast + slow)
        case .quickUserFolders:
            let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Downloads")
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Documents")
            let roots = filterValid([desktop, downloads, documents])
            return (roots, [], roots)
        case .home:
            let roots = filterValid([home])
            return (roots, [], roots)
        case .volume(_, let mountPath):
            let roots = filterValid([URL(fileURLWithPath: mountPath)])
            return (roots, [], roots)
        }
    }

    public static func snapshotScopeKey(scopeID: String, roots: [URL], excludedPaths: Set<String>) -> String {
        let joinedRoots = roots.map(\.standardizedFileURL.path).sorted().joined(separator: "|")
        guard !excludedPaths.isEmpty else { return "\(scopeID)|\(joinedRoots)" }
        let joinedExcl = excludedPaths.sorted().joined(separator: ";")
        return "\(scopeID)|\(joinedRoots)|excl:\(joinedExcl)"
    }
}

public enum OverlayQueryClearPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case afterIdle30s
    case immediatelyOnHide
    case keepPrevious

    public var id: String { rawValue }

    public var idleSeconds: TimeInterval? {
        switch self {
        case .afterIdle30s: 30
        case .immediatelyOnHide: 0
        case .keepPrevious: nil
        }
    }

    public var localizedTitle: String {
        switch self {
        case .afterIdle30s:
            L10n.pick("隐藏 30 秒后清空", "Clear After 30s")
        case .immediatelyOnHide:
            L10n.pick("隐藏后立即清空", "Clear Immediately")
        case .keepPrevious:
            L10n.pick("保留上次输入", "Keep Last Query")
        }
    }
}

public enum OverlayScreenTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case cursorScreen
    case focusedWindowScreen
    case primaryScreen

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .cursorScreen: "cursorarrow.rays"
        case .focusedWindowScreen: "macwindow.on.rectangle"
        case .primaryScreen: "display"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .cursorScreen:
            L10n.pick("跟随鼠标所在屏幕", "Cursor Display")
        case .focusedWindowScreen:
            L10n.pick("跟随焦点窗口屏幕", "Active Window Display")
        case .primaryScreen:
            L10n.pick("固定主显示器", "Primary Display")
        }
    }
}

public enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case sparkles = "sparkles"
    case prism3D = "lucent.prism3d"
    case command = "command"
    case bolt = "bolt.circle.fill"
    case crosshair = "circle.grid.cross"

    public var id: String { rawValue }
    public var symbolName: String {
        self == .prism3D ? "sparkles" : rawValue
    }

    public var localizedTitle: String {
        switch self {
        case .sparkles: L10n.pick("流光星芒", "Sparkles")
        case .prism3D: L10n.pick("3D 流光键帽", "3D Keycap")
        case .command: L10n.pick("指令徽标", "Command")
        case .bolt: L10n.pick("极速闪电", "Bolt")
        case .crosshair: L10n.pick("极简准星", "Crosshair")
        }
    }
}

public enum ClipboardRetentionTTL: String, Codable, CaseIterable, Identifiable, Sendable {
    case forever
    case hours24
    case days7
    case days30

    public var id: String { rawValue }

    public var ttlSeconds: TimeInterval? {
        switch self {
        case .forever: nil
        case .hours24: 86_400
        case .days7: 604_800
        case .days30: 2_592_000
        }
    }

    public var localizedTitle: String {
        switch self {
        case .forever: L10n.pick("永不过期", "Never")
        case .hours24: L10n.pick("24 小时", "24 Hours")
        case .days7: L10n.pick("7 天", "7 Days")
        case .days30: L10n.pick("30 天", "30 Days")
        }
    }
}

public struct PersistedOverlayAnchor: Codable, Sendable, Hashable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
