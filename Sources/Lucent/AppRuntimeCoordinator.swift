import AppKit
import Combine
import Foundation
import LucentCore

@MainActor
final class ClipboardRuntimeState {
    static let maxUndoDepth = 15

    var isSyncingPinnedStore: Bool = false
    private(set) var deletedUndoStack: [(entry: ClipboardEntry, index: Int)] = []
    var lastPasteboardChangeCount: Int = -1
    var monitorTask: Task<Void, Never>?

    var canUndo: Bool { !deletedUndoStack.isEmpty }

    func pushDeleted(entry: ClipboardEntry, index: Int) -> [ClipboardEntry] {
        deletedUndoStack.append((entry: entry, index: index))
        var evicted: [ClipboardEntry] = []
        while deletedUndoStack.count > Self.maxUndoDepth {
            evicted.append(deletedUndoStack.removeFirst().entry)
        }
        return evicted
    }

    func popDeleted() -> (entry: ClipboardEntry, index: Int)? {
        guard !deletedUndoStack.isEmpty else { return nil }
        return deletedUndoStack.removeLast()
    }

    func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }
}

@MainActor
final class WorkspaceRuntimeState {
    let directoryCache = WorkspaceDirectoryCache(maxEntries: 48)
    var selectionAnchorID: String?
    var activeDragURLs: [URL] = []
    var hasLoadedWorkspace: Bool = false

    var leftDirectoryTask: Task<Void, Never>?
    var rightDirectoryTask: Task<Void, Never>?
    var leftSearchTask: Task<Void, Never>?
    var rightSearchTask: Task<Void, Never>?
    var locationRefreshTask: Task<Void, Never>?
    var volumeObservers: [NSObjectProtocol] = []

    func replaceDirectoryTask(_ task: Task<Void, Never>?, for pane: PaneSide) {
        if pane == .left {
            leftDirectoryTask?.cancel()
            leftDirectoryTask = task
        } else {
            rightDirectoryTask?.cancel()
            rightDirectoryTask = task
        }
    }

    func replaceSearchTask(_ task: Task<Void, Never>?, for pane: PaneSide) {
        if pane == .left {
            leftSearchTask?.cancel()
            leftSearchTask = task
        } else {
            rightSearchTask?.cancel()
            rightSearchTask = task
        }
    }

    func cancelAllTasks() {
        leftDirectoryTask?.cancel(); leftDirectoryTask = nil
        rightDirectoryTask?.cancel(); rightDirectoryTask = nil
        leftSearchTask?.cancel(); leftSearchTask = nil
        rightSearchTask?.cancel(); rightSearchTask = nil
        locationRefreshTask?.cancel(); locationRefreshTask = nil
    }

    func removeVolumeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in volumeObservers { center.removeObserver(obs) }
        volumeObservers.removeAll()
    }
}

@MainActor
final class OverlayAndIndexRuntimeState {
    var searchTask: Task<Void, Never>?
    var everythingIndexTask: Task<Void, Never>?
    var previewTask: Task<Void, Never>?
    var hashTask: Task<Void, Never>?
    var indexUnloadTask: Task<Void, Never>?
    var queryIdleClearTask: Task<Void, Never>?
    var snapshotSaveTask: Task<Void, Never>?
    var pluginRunTask: Task<Void, Never>?
    private(set) var activePluginRunToken = UUID()
    var backgroundPluginTasks: [String: Task<Void, Never>] = [:]

    var hotKeyBannerCancelAction: (() -> Void)?
    var hotKeyBannerDismissTask: Task<Void, Never>?

    var fsEventWatcher: EverythingFSEventWatcher?
    var pluginWatcher: PluginDirectoryWatcher?
    var scriptsWatcher: PluginDirectoryWatcher?
    var scriptsInProcessObserver: NSObjectProtocol?
    var scriptsDistributedObserver: NSObjectProtocol?
    var homeLayoutObserver: NSObjectProtocol?
    var usageCancellable: AnyCancellable?

    func beginForegroundRun() -> UUID {
        pluginRunTask?.cancel()
        let token = UUID()
        activePluginRunToken = token
        return token
    }

    func cancelOverlaySessionTasks() {
        searchTask?.cancel(); searchTask = nil
        previewTask?.cancel(); previewTask = nil
        hashTask?.cancel(); hashTask = nil
        pluginRunTask?.cancel(); pluginRunTask = nil
    }

    func stopIndexWatcher() {
        fsEventWatcher?.stop()
        fsEventWatcher = nil
        snapshotSaveTask?.cancel()
        snapshotSaveTask = nil
    }

    func stopPluginWatcherAndTasks() {
        pluginWatcher?.stop()
        pluginWatcher = nil
        pluginRunTask?.cancel()
        pluginRunTask = nil
        for (_, task) in backgroundPluginTasks { task.cancel() }
        backgroundPluginTasks.removeAll()
    }

    func removeScriptObservers() {
        if let obs = scriptsInProcessObserver {
            NotificationCenter.default.removeObserver(obs)
            scriptsInProcessObserver = nil
        }
        if let dist = scriptsDistributedObserver {
            DistributedNotificationCenter.default().removeObserver(dist)
            scriptsDistributedObserver = nil
        }
        scriptsWatcher?.stop()
        scriptsWatcher = nil
    }

    func removeHomeLayoutObserver() {
        if let obs = homeLayoutObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            homeLayoutObserver = nil
        }
    }

    func shutdownAll() {
        removeHomeLayoutObserver()
        removeScriptObservers()
        stopPluginWatcherAndTasks()
        stopIndexWatcher()
        usageCancellable?.cancel(); usageCancellable = nil
        cancelOverlaySessionTasks()
        everythingIndexTask?.cancel(); everythingIndexTask = nil
        indexUnloadTask?.cancel(); indexUnloadTask = nil
        queryIdleClearTask?.cancel(); queryIdleClearTask = nil
        hotKeyBannerDismissTask?.cancel(); hotKeyBannerDismissTask = nil
        hotKeyBannerCancelAction = nil
    }
}
