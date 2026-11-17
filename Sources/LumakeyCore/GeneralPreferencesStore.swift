import Foundation
import LumakeyFoundation
import LumakeyMedia
import LumakeySearch
import LumakeySystem

public struct GeneralPreferences: Codable, Sendable, Hashable, Equatable {
    public static let fileName = "general-preferences.json"
    public static let clipboardCapacityPresets: [Int] = [30, 80, 200, 500]

    public var schemaVersion: Int
    public var launchSilentlyInMenuBar: Bool
    public var showDockIcon: Bool
    public var defaultEverythingScope: PersistedEverythingScope

    public var queryClearPolicy: OverlayQueryClearPolicy
    public var overlayScreenTarget: OverlayScreenTarget
    public var rememberOverlayPosition: Bool
    public var savedOverlayTopCenter: PersistedOverlayAnchor?
    public var menuBarIconStyle: MenuBarIconStyle

    public var clipboardMaxUnpinned: Int
    public var clipboardRetentionTTL: ClipboardRetentionTTL
    public var clipboardExcludedBundleIDs: [String]

    public var defaultCaptureSaveDirectoryPath: String
    public var quickSaveCaptureWithoutDialog: Bool
    public var screenshotExcludeWindowShadow: Bool
    public var gifDefaultOptions: GifRecordingOptions

    public var excludedIndexPaths: [String]

    public var updateCheckFrequency: UpdateCheckFrequency
    public var includePrereleaseAppUpdates: Bool
    public var skippedAppVersion: String
    public var autoCheckPluginUpdates: Bool
    public var autoInstallSafePluginUpdates: Bool
    public var lastUpdateCheckTimestamp: Double
    public var enableSelectionQuickBar: Bool

    public init(
        schemaVersion: Int = 1,
        launchSilentlyInMenuBar: Bool = false,
        showDockIcon: Bool = false,
        defaultEverythingScope: PersistedEverythingScope = .allVolumes,
        queryClearPolicy: OverlayQueryClearPolicy = .afterIdle30s,
        overlayScreenTarget: OverlayScreenTarget = .cursorScreen,
        rememberOverlayPosition: Bool = true,
        savedOverlayTopCenter: PersistedOverlayAnchor? = nil,
        menuBarIconStyle: MenuBarIconStyle = .sparkles,
        clipboardMaxUnpinned: Int = 80,
        clipboardRetentionTTL: ClipboardRetentionTTL = .forever,
        clipboardExcludedBundleIDs: [String] = [],
        defaultCaptureSaveDirectoryPath: String = "",
        quickSaveCaptureWithoutDialog: Bool = false,
        screenshotExcludeWindowShadow: Bool = false,
        gifDefaultOptions: GifRecordingOptions = GifRecordingOptions(),
        excludedIndexPaths: [String] = [],
        updateCheckFrequency: UpdateCheckFrequency = .daily,
        includePrereleaseAppUpdates: Bool = false,
        skippedAppVersion: String = "",
        autoCheckPluginUpdates: Bool = true,
        autoInstallSafePluginUpdates: Bool = false,
        lastUpdateCheckTimestamp: Double = 0,
        enableSelectionQuickBar: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.launchSilentlyInMenuBar = launchSilentlyInMenuBar
        self.showDockIcon = showDockIcon
        self.defaultEverythingScope = defaultEverythingScope
        self.queryClearPolicy = queryClearPolicy
        self.overlayScreenTarget = overlayScreenTarget
        self.rememberOverlayPosition = rememberOverlayPosition
        self.savedOverlayTopCenter = savedOverlayTopCenter
        self.menuBarIconStyle = menuBarIconStyle
        self.clipboardMaxUnpinned = min(max(clipboardMaxUnpinned, 10), 2_000)
        self.clipboardRetentionTTL = clipboardRetentionTTL
        self.clipboardExcludedBundleIDs = Self.normalizeBundleIDs(clipboardExcludedBundleIDs)
        self.defaultCaptureSaveDirectoryPath = Self.normalizeSingleDirectoryPath(defaultCaptureSaveDirectoryPath)
        self.quickSaveCaptureWithoutDialog = quickSaveCaptureWithoutDialog
        self.screenshotExcludeWindowShadow = screenshotExcludeWindowShadow
        self.gifDefaultOptions = gifDefaultOptions
        self.excludedIndexPaths = Self.normalizeExcludedPaths(excludedIndexPaths)
        self.updateCheckFrequency = updateCheckFrequency
        self.includePrereleaseAppUpdates = includePrereleaseAppUpdates
        self.skippedAppVersion = AppVersionComparator.normalize(skippedAppVersion)
        self.autoCheckPluginUpdates = autoCheckPluginUpdates
        self.autoInstallSafePluginUpdates = autoInstallSafePluginUpdates
        self.lastUpdateCheckTimestamp = max(0, lastUpdateCheckTimestamp)
        self.enableSelectionQuickBar = enableSelectionQuickBar
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, launchSilentlyInMenuBar, showDockIcon, defaultEverythingScope
        case queryClearPolicy, overlayScreenTarget, rememberOverlayPosition, savedOverlayTopCenter, menuBarIconStyle
        case clipboardMaxUnpinned, clipboardRetentionTTL, clipboardExcludedBundleIDs
        case defaultCaptureSaveDirectoryPath, quickSaveCaptureWithoutDialog, screenshotExcludeWindowShadow, gifDefaultOptions
        case excludedIndexPaths
        case updateCheckFrequency, includePrereleaseAppUpdates, skippedAppVersion
        case autoCheckPluginUpdates, autoInstallSafePluginUpdates, lastUpdateCheckTimestamp
        case enableSelectionQuickBar
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1,
            launchSilentlyInMenuBar: (try? c.decodeIfPresent(Bool.self, forKey: .launchSilentlyInMenuBar)) ?? false,
            showDockIcon: (try? c.decodeIfPresent(Bool.self, forKey: .showDockIcon)) ?? false,
            defaultEverythingScope: (try? c.decodeIfPresent(PersistedEverythingScope.self, forKey: .defaultEverythingScope)) ?? .allVolumes,
            queryClearPolicy: (try? c.decodeIfPresent(OverlayQueryClearPolicy.self, forKey: .queryClearPolicy)) ?? .afterIdle30s,
            overlayScreenTarget: (try? c.decodeIfPresent(OverlayScreenTarget.self, forKey: .overlayScreenTarget)) ?? .cursorScreen,
            rememberOverlayPosition: (try? c.decodeIfPresent(Bool.self, forKey: .rememberOverlayPosition)) ?? true,
            savedOverlayTopCenter: try? c.decodeIfPresent(PersistedOverlayAnchor.self, forKey: .savedOverlayTopCenter),
            menuBarIconStyle: (try? c.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle)) ?? .sparkles,
            clipboardMaxUnpinned: (try? c.decodeIfPresent(Int.self, forKey: .clipboardMaxUnpinned)) ?? 80,
            clipboardRetentionTTL: (try? c.decodeIfPresent(ClipboardRetentionTTL.self, forKey: .clipboardRetentionTTL)) ?? .forever,
            clipboardExcludedBundleIDs: (try? c.decodeIfPresent([String].self, forKey: .clipboardExcludedBundleIDs)) ?? [],
            defaultCaptureSaveDirectoryPath: (try? c.decodeIfPresent(String.self, forKey: .defaultCaptureSaveDirectoryPath)) ?? "",
            quickSaveCaptureWithoutDialog: (try? c.decodeIfPresent(Bool.self, forKey: .quickSaveCaptureWithoutDialog)) ?? false,
            screenshotExcludeWindowShadow: (try? c.decodeIfPresent(Bool.self, forKey: .screenshotExcludeWindowShadow)) ?? false,
            gifDefaultOptions: (try? c.decodeIfPresent(GifRecordingOptions.self, forKey: .gifDefaultOptions)) ?? GifRecordingOptions(),
            excludedIndexPaths: (try? c.decodeIfPresent([String].self, forKey: .excludedIndexPaths)) ?? [],
            updateCheckFrequency: (try? c.decodeIfPresent(UpdateCheckFrequency.self, forKey: .updateCheckFrequency)) ?? .daily,
            includePrereleaseAppUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .includePrereleaseAppUpdates)) ?? false,
            skippedAppVersion: (try? c.decodeIfPresent(String.self, forKey: .skippedAppVersion)) ?? "",
            autoCheckPluginUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .autoCheckPluginUpdates)) ?? true,
            autoInstallSafePluginUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .autoInstallSafePluginUpdates)) ?? false,
            lastUpdateCheckTimestamp: (try? c.decodeIfPresent(Double.self, forKey: .lastUpdateCheckTimestamp)) ?? 0,
            enableSelectionQuickBar: (try? c.decodeIfPresent(Bool.self, forKey: .enableSelectionQuickBar)) ?? true
        )
    }

    public func resolvedCaptureSaveDirectory() -> URL {
        if !defaultCaptureSaveDirectoryPath.isEmpty {
            return URL(fileURLWithPath: defaultCaptureSaveDirectoryPath, isDirectory: true)
        }
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Lumakey", isDirectory: true)
    }

    public var displayCaptureSaveDirectory: String {
        let raw = resolvedCaptureSaveDirectory().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if raw == home { return "~" }
        if raw.hasPrefix(home + "/") { return "~" + String(raw.dropFirst(home.count)) }
        return raw
    }

    public var excludedIndexPathSet: Set<String> { Set(excludedIndexPaths) }

    public mutating func toggleExcludedApp(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = clipboardExcludedBundleIDs.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            clipboardExcludedBundleIDs.remove(at: idx)
        } else {
            clipboardExcludedBundleIDs = Self.normalizeBundleIDs(clipboardExcludedBundleIDs + [trimmed])
        }
    }

    public func isAppExcludedFromClipboard(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return clipboardExcludedBundleIDs.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    public mutating func addExcludedIndexPath(_ path: String) {
        excludedIndexPaths = Self.normalizeExcludedPaths(excludedIndexPaths + [path])
    }

    public mutating func removeExcludedIndexPath(_ path: String) {
        let normalized = Self.normalizeSingleDirectoryPath(path)
        excludedIndexPaths.removeAll { $0 == normalized }
    }

    public static func defaultConfigURL(appSupportDirectory: URL = LumakeyAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> GeneralPreferences {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(GeneralPreferences.self, from: data)
        else { return GeneralPreferences() }
        return decoded
    }

    public func save(to url: URL = defaultConfigURL(), notify: Bool = true) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: url, options: .atomic)
            if notify { NotificationCenter.default.post(name: .lumakeyGeneralPreferencesDidChange, object: nil) }
        }
    }

    public static func normalizeBundleIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func normalizeSingleDirectoryPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    }

    public static func normalizeExcludedPaths(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in raw {
            let std = normalizeSingleDirectoryPath(item)
            guard !std.isEmpty, std != "/", seen.insert(std).inserted else { continue }
            result.append(std)
        }
        return result.sorted()
    }
}
