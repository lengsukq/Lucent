import Foundation
import LucentCore

extension AppViewModel {
    func installAppDirectoryWatcher() {
        let roots = LauncherEngine.defaultApplicationRootURLs()
        let existingPaths = roots.compactMap { url -> String? in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            var isDir: ObjCBool = false
            return (FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir) && isDir.boolValue) ? resolved : nil
        }
        guard runtime.appDirectoryWatcher == nil || runtime.watchedAppRootPaths != existingPaths else { return }

        runtime.appDirectoryWatcher?.stop()
        runtime.watchedAppRootPaths = existingPaths
        runtime.appDirectoryWatcher = EverythingFSEventWatcher(roots: roots, debounceInterval: 0.45) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInstalledApps(force: true)
            }
        }
    }

    func refreshInstalledAppsIfNeeded() {
        refreshInstalledApps(force: false)
    }

    func refreshInstalledApps(force: Bool = false) {
        let knownFingerprint = runtime.lastAppsFingerprint
        let needsInitialLoad = installedApps.isEmpty
        runtime.appRefreshTask?.cancel()
        runtime.appRefreshTask = Task { [weak self] in
            let snapshot: (fingerprint: UInt64, apps: [InstalledAppItem]?) = await Task.detached(priority: .userInitiated) {
                let fp = LauncherEngine.applicationDirectoriesFingerprint()
                if !force && !needsInitialLoad && fp == knownFingerprint {
                    return (fp, nil)
                }
                let discovered = LauncherEngine.discoverInstalledApps()
                return (fp, discovered)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.runtime.lastAppsFingerprint = snapshot.fingerprint
            self.installAppDirectoryWatcher()
            guard let apps = snapshot.apps else { return }
            self.installedApps = apps
            AppUsageTrackerController.shared.ensureSystemProbe(for: apps)
            if self.isOverlayVisible {
                IconCache.shared.prewarmDockIcons(self.cachedDockApps)
            }
        }
    }
}
