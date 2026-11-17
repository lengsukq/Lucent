import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func updateGeneralPreferences(_ mutate: (inout GeneralPreferences) -> Void) {
        let prev = generalPreferences
        var next = prev
        mutate(&next)
        guard next != prev else { return }
        generalPreferences = next
        next.save()
        applyGeneralPreferencesSideEffects(previous: prev, current: next)
    }

    func applyGeneralPreferencesSideEffects(previous: GeneralPreferences, current: GeneralPreferences) {
        if showDockIcon != current.showDockIcon {
            showDockIcon = current.showDockIcon
        }
        if previous.showDockIcon != current.showDockIcon {
            onDockVisibilityChanged?(current.showDockIcon)
        }
        if previous.gifDefaultOptions != current.gifDefaultOptions {
            GifCaptureController.shared.options = current.gifDefaultOptions
        }
        if previous.clipboardMaxUnpinned != current.clipboardMaxUnpinned
            || previous.clipboardRetentionTTL != current.clipboardRetentionTTL {
            clipboardItems = ClipboardService.pruneAndCap(
                clipboardItems,
                maxUnpinned: current.clipboardMaxUnpinned,
                ttl: current.clipboardRetentionTTL
            )
        }
        if previous.queryClearPolicy != current.queryClearPolicy, current.queryClearPolicy == .keepPrevious {
            queryIdleClearTask?.cancel()
            queryIdleClearTask = nil
        }
        if previous.enableSelectionQuickBar != current.enableSelectionQuickBar {
            SelectionQuickBarController.shared.syncMonitoring(
                enabled: current.enableSelectionQuickBar,
                plugins: plugins,
                viewModel: self
            )
        }
    }

    func reloadGeneralPreferencesFromDisk() {
        let loaded = GeneralPreferences.load()
        let prev = generalPreferences
        generalPreferences = loaded
        showDockIcon = loaded.showDockIcon
        onDockVisibilityChanged?(loaded.showDockIcon)
        GifCaptureController.shared.options = loaded.gifDefaultOptions
        clipboardItems = ClipboardService.pruneAndCap(
            clipboardItems,
            maxUnpinned: loaded.clipboardMaxUnpinned,
            ttl: loaded.clipboardRetentionTTL
        )
        let targetScope = EverythingScope(persisted: loaded.defaultEverythingScope)
        if everythingScope != targetScope || prev.excludedIndexPaths != loaded.excludedIndexPaths {
            loadOrBuildEverythingIndex(scope: targetScope, forceRebuild: prev.excludedIndexPaths != loaded.excludedIndexPaths)
        }
        NotificationCenter.default.post(name: .lumakeyGeneralPreferencesDidChange, object: nil)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginService.currentStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginStatus = status
            if enabled && !generalPreferences.launchSilentlyInMenuBar {
                updateGeneralPreferences { $0.launchSilentlyInMenuBar = true }
            }
            switch status {
            case .enabled:
                serviceMessage = L10n.pick("已开启开机自启（默认静默驻留状态栏）", "Launch at Login enabled (silent menu-bar startup)")
            case .requiresApproval:
                serviceMessage = L10n.pick("请在「系统设置 - 通用 - 登录项」中允许 Lumakey", "Approve Lumakey in System Settings - General - Login Items")
            case .notRegistered:
                serviceMessage = L10n.pick("已关闭开机自启", "Launch at Login disabled")
            case .notFound:
                serviceMessage = L10n.pick("请先将 Lumakey.app 移入 /Applications 目录后再开启", "Move Lumakey.app to /Applications before enabling")
            }
        } catch {
            launchAtLoginStatus = LaunchAtLoginService.currentStatus()
            serviceMessage = L10n.pick(
                "开机自启设置失败：\(error.localizedDescription)（请确认应用位于 /Applications）",
                "Launch at Login failed: \(error.localizedDescription) (ensure app is in /Applications)"
            )
        }
    }

    func selectDefaultEverythingScope(_ scope: EverythingScope) {
        updateGeneralPreferences { $0.defaultEverythingScope = scope.persisted }
        rebuildEverythingIndex(scope: scope)
    }

    func addExcludedIndexDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty, path != "/" else { return }
        let before = generalPreferences.excludedIndexPaths
        updateGeneralPreferences { $0.addExcludedIndexPath(path) }
        if generalPreferences.excludedIndexPaths != before {
            forceRebuildEverythingIndex()
            serviceMessage = L10n.pick("已排除索引目录：\(url.lastPathComponent)", "Excluded folder from index: \(url.lastPathComponent)")
        }
    }

    func removeExcludedIndexDirectory(_ path: String) {
        let before = generalPreferences.excludedIndexPaths
        updateGeneralPreferences { $0.removeExcludedIndexPath(path) }
        if generalPreferences.excludedIndexPaths != before {
            forceRebuildEverythingIndex()
        }
    }

    func selectCaptureSaveDirectoryInteractive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = generalPreferences.resolvedCaptureSaveDirectory()
        panel.prompt = L10n.pick("设为默认保存目录", "Select Folder")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            updateGeneralPreferences { $0.defaultCaptureSaveDirectoryPath = url.standardizedFileURL.path }
            serviceMessage = L10n.pick("默认导出目录已更新：\(url.path)", "Default capture directory updated: \(url.path)")
        }
    }

    func addExcludedIndexDirectoryInteractive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.pick("添加排除目录", "Exclude Folder")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            let before = generalPreferences.excludedIndexPaths
            updateGeneralPreferences { prefs in
                for url in panel.urls {
                    prefs.addExcludedIndexPath(url.standardizedFileURL.path)
                }
            }
            if generalPreferences.excludedIndexPaths != before {
                forceRebuildEverythingIndex()
            }
        }
    }
}
