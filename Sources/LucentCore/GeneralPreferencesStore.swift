import Foundation
import LucentFoundation
import LucentMedia
import LucentSearch
import LucentSystem

public struct GeneralPreferences: Codable, Sendable, Hashable, Equatable {
    public static let fileName = "general-preferences.json"
    public static let clipboardCapacityPresets: [Int] = [30, 80, 200, 500]
    public static let defaultSwatchHexes = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF"]

    public var schemaVersion: Int
    public var launchSilentlyInMenuBar: Bool
    public var showLaunchIntroAnimation: Bool
    public var restoreFloatingWindowsOnLaunch: Bool
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
    public var lastCaptureSavePanelDirectoryPath: String
    public var quickSaveCaptureWithoutDialog: Bool
    public var screenshotExcludeWindowShadow: Bool
    public var hideLucentDuringScreenshot: Bool
    public var captureExportFormat: CaptureExportFormat
    public var captureFileNameTemplate: String
    public var captureDoubleClickAction: CaptureDoubleClickAction
    public var confirmCancelAnnotatedCaptureWithDoublePress: Bool
    public var enableCaptureControlDrillDown: Bool
    public var customAnnotationSwatchHexes: [String]
    public var hiddenScreenshotToolbarItems: [String]
    public var gifDefaultOptions: GifRecordingOptions
    public var videoDefaultOptions: VideoRecordingOptions

    public var excludedIndexPaths: [String]

    public var updateCheckFrequency: UpdateCheckFrequency
    public var includePrereleaseAppUpdates: Bool
    public var skippedAppVersion: String
    public var autoCheckPluginUpdates: Bool
    public var autoInstallSafePluginUpdates: Bool
    public var lastUpdateCheckTimestamp: Double
    public var enableSelectionQuickBar: Bool
    public var enableSmartSearchRanking: Bool
    public var enableMcpFileSearch: Bool

    public init(
        schemaVersion: Int = 1,
        launchSilentlyInMenuBar: Bool = false,
        showLaunchIntroAnimation: Bool = true,
        restoreFloatingWindowsOnLaunch: Bool = true,
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
        lastCaptureSavePanelDirectoryPath: String = "",
        quickSaveCaptureWithoutDialog: Bool = false,
        screenshotExcludeWindowShadow: Bool = false,
        hideLucentDuringScreenshot: Bool = true,
        captureExportFormat: CaptureExportFormat = .png,
        captureFileNameTemplate: String = CaptureFileNameFormatter.defaultTemplate,
        captureDoubleClickAction: CaptureDoubleClickAction = .copyAndFinish,
        confirmCancelAnnotatedCaptureWithDoublePress: Bool = true,
        enableCaptureControlDrillDown: Bool = true,
        customAnnotationSwatchHexes: [String] = GeneralPreferences.defaultSwatchHexes,
        hiddenScreenshotToolbarItems: [String] = [],
        gifDefaultOptions: GifRecordingOptions = GifRecordingOptions(),
        videoDefaultOptions: VideoRecordingOptions = VideoRecordingOptions(),
        excludedIndexPaths: [String] = [],
        updateCheckFrequency: UpdateCheckFrequency = .daily,
        includePrereleaseAppUpdates: Bool = false,
        skippedAppVersion: String = "",
        autoCheckPluginUpdates: Bool = true,
        autoInstallSafePluginUpdates: Bool = false,
        lastUpdateCheckTimestamp: Double = 0,
        enableSelectionQuickBar: Bool = true,
        enableSmartSearchRanking: Bool = true,
        enableMcpFileSearch: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.launchSilentlyInMenuBar = launchSilentlyInMenuBar
        self.showLaunchIntroAnimation = showLaunchIntroAnimation
        self.restoreFloatingWindowsOnLaunch = restoreFloatingWindowsOnLaunch
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
        self.lastCaptureSavePanelDirectoryPath = Self.normalizeSingleDirectoryPath(lastCaptureSavePanelDirectoryPath)
        self.quickSaveCaptureWithoutDialog = quickSaveCaptureWithoutDialog
        self.screenshotExcludeWindowShadow = screenshotExcludeWindowShadow
        self.hideLucentDuringScreenshot = hideLucentDuringScreenshot
        self.captureExportFormat = captureExportFormat
        let trimmedTpl = captureFileNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.captureFileNameTemplate = trimmedTpl.isEmpty ? CaptureFileNameFormatter.defaultTemplate : trimmedTpl
        self.captureDoubleClickAction = captureDoubleClickAction
        self.confirmCancelAnnotatedCaptureWithDoublePress = confirmCancelAnnotatedCaptureWithDoublePress
        self.enableCaptureControlDrillDown = enableCaptureControlDrillDown
        self.customAnnotationSwatchHexes = Self.normalizeSwatches(customAnnotationSwatchHexes)
        self.hiddenScreenshotToolbarItems = Array(Set(hiddenScreenshotToolbarItems)).sorted()
        self.gifDefaultOptions = gifDefaultOptions
        self.videoDefaultOptions = videoDefaultOptions
        self.excludedIndexPaths = Self.normalizeExcludedPaths(excludedIndexPaths)
        self.updateCheckFrequency = updateCheckFrequency
        self.includePrereleaseAppUpdates = includePrereleaseAppUpdates
        self.skippedAppVersion = AppVersionComparator.normalize(skippedAppVersion)
        self.autoCheckPluginUpdates = autoCheckPluginUpdates
        self.autoInstallSafePluginUpdates = autoInstallSafePluginUpdates
        self.lastUpdateCheckTimestamp = max(0, lastUpdateCheckTimestamp)
        self.enableSelectionQuickBar = enableSelectionQuickBar
        self.enableSmartSearchRanking = enableSmartSearchRanking
        self.enableMcpFileSearch = enableMcpFileSearch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1,
            launchSilentlyInMenuBar: (try? c.decodeIfPresent(Bool.self, forKey: .launchSilentlyInMenuBar)) ?? false,
            showLaunchIntroAnimation: (try? c.decodeIfPresent(Bool.self, forKey: .showLaunchIntroAnimation)) ?? true,
            restoreFloatingWindowsOnLaunch: (try? c.decodeIfPresent(Bool.self, forKey: .restoreFloatingWindowsOnLaunch)) ?? true,
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
            lastCaptureSavePanelDirectoryPath: (try? c.decodeIfPresent(String.self, forKey: .lastCaptureSavePanelDirectoryPath)) ?? "",
            quickSaveCaptureWithoutDialog: (try? c.decodeIfPresent(Bool.self, forKey: .quickSaveCaptureWithoutDialog)) ?? false,
            screenshotExcludeWindowShadow: (try? c.decodeIfPresent(Bool.self, forKey: .screenshotExcludeWindowShadow)) ?? false,
            hideLucentDuringScreenshot: (try? c.decodeIfPresent(Bool.self, forKey: .hideLucentDuringScreenshot)) ?? true,
            captureExportFormat: (try? c.decodeIfPresent(CaptureExportFormat.self, forKey: .captureExportFormat)) ?? .png,
            captureFileNameTemplate: (try? c.decodeIfPresent(String.self, forKey: .captureFileNameTemplate)) ?? CaptureFileNameFormatter.defaultTemplate,
            captureDoubleClickAction: (try? c.decodeIfPresent(CaptureDoubleClickAction.self, forKey: .captureDoubleClickAction)) ?? .copyAndFinish,
            confirmCancelAnnotatedCaptureWithDoublePress: (try? c.decodeIfPresent(Bool.self, forKey: .confirmCancelAnnotatedCaptureWithDoublePress)) ?? true,
            enableCaptureControlDrillDown: (try? c.decodeIfPresent(Bool.self, forKey: .enableCaptureControlDrillDown)) ?? true,
            customAnnotationSwatchHexes: (try? c.decodeIfPresent([String].self, forKey: .customAnnotationSwatchHexes)) ?? Self.defaultSwatchHexes,
            hiddenScreenshotToolbarItems: (try? c.decodeIfPresent([String].self, forKey: .hiddenScreenshotToolbarItems)) ?? [],
            gifDefaultOptions: (try? c.decodeIfPresent(GifRecordingOptions.self, forKey: .gifDefaultOptions)) ?? GifRecordingOptions(),
            videoDefaultOptions: (try? c.decodeIfPresent(VideoRecordingOptions.self, forKey: .videoDefaultOptions)) ?? VideoRecordingOptions(),
            excludedIndexPaths: (try? c.decodeIfPresent([String].self, forKey: .excludedIndexPaths)) ?? [],
            updateCheckFrequency: (try? c.decodeIfPresent(UpdateCheckFrequency.self, forKey: .updateCheckFrequency)) ?? .daily,
            includePrereleaseAppUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .includePrereleaseAppUpdates)) ?? false,
            skippedAppVersion: (try? c.decodeIfPresent(String.self, forKey: .skippedAppVersion)) ?? "",
            autoCheckPluginUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .autoCheckPluginUpdates)) ?? true,
            autoInstallSafePluginUpdates: (try? c.decodeIfPresent(Bool.self, forKey: .autoInstallSafePluginUpdates)) ?? false,
            lastUpdateCheckTimestamp: (try? c.decodeIfPresent(Double.self, forKey: .lastUpdateCheckTimestamp)) ?? 0,
            enableSelectionQuickBar: (try? c.decodeIfPresent(Bool.self, forKey: .enableSelectionQuickBar)) ?? true,
            enableSmartSearchRanking: (try? c.decodeIfPresent(Bool.self, forKey: .enableSmartSearchRanking)) ?? true,
            enableMcpFileSearch: (try? c.decodeIfPresent(Bool.self, forKey: .enableMcpFileSearch)) ?? false
        )
    }

    public func resolvedCaptureSaveDirectory() -> URL {
        if !defaultCaptureSaveDirectoryPath.isEmpty {
            return URL(fileURLWithPath: defaultCaptureSaveDirectoryPath, isDirectory: true)
        }
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Lucent", isDirectory: true)
    }

    public var displayCaptureSaveDirectory: String {
        let raw = resolvedCaptureSaveDirectory().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if raw == home { return "~" }
        if raw.hasPrefix(home + "/") { return "~" + String(raw.dropFirst(home.count)) }
        return raw
    }

    public var excludedIndexPathSet: Set<String> { Set(excludedIndexPaths) }
    public var hiddenToolbarItemSet: Set<String> { Set(hiddenScreenshotToolbarItems) }

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

    public static func defaultConfigURL(appSupportDirectory: URL = LucentAppPaths.defaultAppSupportDirectory()) -> URL {
        appSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func load(from url: URL = defaultConfigURL()) -> GeneralPreferences {
        AtomicJSONStore.load(GeneralPreferences.self, from: url, fallback: GeneralPreferences())
    }

    public func save(to url: URL = defaultConfigURL(), notify: Bool = true) {
        AtomicJSONStore.save(self, to: url, notification: notify ? .lucentGeneralPreferencesDidChange : nil)
    }

    public static func normalizeSwatches(_ raw: [String]) -> [String] {
        var out: [String] = []
        for idx in 0..<5 {
            let candidate = idx < raw.count ? AnnotationRGBColor(hex: raw[idx])?.hexString : nil
            out.append(candidate ?? defaultSwatchHexes[idx])
        }
        return out
    }

    public static func normalizeBundleIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>(); var result: [String] = []
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
        var seen = Set<String>(); var result: [String] = []
        for item in raw {
            let std = normalizeSingleDirectoryPath(item)
            guard !std.isEmpty, std != "/", seen.insert(std).inserted else { continue }
            result.append(std)
        }
        return result.sorted()
    }
}
