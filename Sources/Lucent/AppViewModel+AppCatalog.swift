import AppKit
import Darwin
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
        installUserApplicationsCreationMonitorIfNeeded()
        guard runtime.appDirectoryWatcher == nil || runtime.watchedAppRootPaths != existingPaths else { return }

        runtime.appDirectoryWatcher?.stop()
        runtime.watchedAppRootPaths = existingPaths
        runtime.appDirectoryWatcher = EverythingFSEventWatcher(
            roots: roots,
            sinceEventId: nil,
            debounceInterval: 0.25,
            maxWaitInterval: 0.65,
            ignoreNonStructuralFileModifications: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInstalledApps(force: true, invalidateIcons: true)
            }
        }
    }

    private func installUserApplicationsCreationMonitorIfNeeded() {
        let userAppsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: userAppsPath, isDirectory: &isDir), isDir.boolValue {
            runtime.homeDirVnodeSource?.cancel()
            runtime.homeDirVnodeSource = nil
            return
        }
        guard runtime.homeDirVnodeSource == nil else { return }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let fd = homePath.withCString { open($0, O_EVTONLY | O_CLOEXEC) }
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            var dirFlag: ObjCBool = false
            guard FileManager.default.fileExists(atPath: userAppsPath, isDirectory: &dirFlag), dirFlag.boolValue else { return }
            MainActor.assumeIsolated {
                self?.installAppDirectoryWatcher()
                self?.refreshInstalledApps(force: true, invalidateIcons: true)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        runtime.homeDirVnodeSource = source
    }

    func installWorkspaceLifecycleObservers() {
        runtime.removeWorkspaceLifecycleObservers()
        let center = NSWorkspace.shared.notificationCenter
        let wakeObs = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleSystemDidWakeForIndex()
                self.refreshInstalledApps(force: true, invalidateIcons: true)
            }
        }
        let launchObs = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard running?.activationPolicy == .regular,
                  let bundleURL = running?.bundleURL,
                  bundleURL.pathExtension.lowercased() == "app" else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.installedApps.isEmpty else { return }
                guard Self.isTopLevelDiscoverableAppBundle(bundleURL) else { return }
                let stdPath = bundleURL.standardizedFileURL.path
                if self.runtime.knownAppCanonicalPaths.contains(stdPath) { return }
                let canonicalPath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
                if self.runtime.knownAppCanonicalPaths.contains(canonicalPath) { return }
                self.refreshInstalledApps(force: true, invalidateIcons: false)
            }
        }
        runtime.workspaceLifecycleObservers = [wakeObs, launchObs]
    }

    private static func isTopLevelDiscoverableAppBundle(_ bundleURL: URL) -> Bool {
        let stdPath = bundleURL.standardizedFileURL.path
        let canonicalPath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        for root in LauncherEngine.defaultApplicationRootURLs() {
            let rootStd = root.standardizedFileURL.path
            let rootCan = root.resolvingSymlinksInPath().standardizedFileURL.path
            let rel: Substring?
            if stdPath.hasPrefix(rootStd + "/") {
                rel = stdPath.dropFirst(rootStd.count + 1)
            } else if canonicalPath.hasPrefix(rootCan + "/") {
                rel = canonicalPath.dropFirst(rootCan.count + 1)
            } else {
                continue
            }
            guard let rel else { continue }
            let parts = rel.split(separator: "/")
            guard !parts.isEmpty, parts.count <= LauncherEngine.maxAppSubfolderDepth + 1 else { return false }
            // Reject nested helpers inside another .app or .framework bundle.
            for ancestor in parts.dropLast() {
                let lower = ancestor.lowercased()
                if lower.hasSuffix(".app") || lower.hasSuffix(".framework") || lower.hasSuffix(".bundle") {
                    return false
                }
            }
            return true
        }
        return false
    }

    func refreshInstalledAppsIfNeeded() {
        refreshInstalledApps(force: false, invalidateIcons: false)
    }

    func refreshInstalledApps(force: Bool = false, invalidateIcons: Bool = false) {
        if runtime.appRefreshTask != nil {
            runtime.appRefreshPending = true
            runtime.appRefreshPendingForce = runtime.appRefreshPendingForce || force
            runtime.appRefreshPendingInvalidateIcons = runtime.appRefreshPendingInvalidateIcons || invalidateIcons
            return
        }

        let token = UUID()
        runtime.appRefreshToken = token
        var currentForce = force
        var currentInvalidateIcons = invalidateIcons

        runtime.appRefreshTask = Task { [weak self] in
            defer {
                if let self, self.runtime.appRefreshToken == token {
                    self.runtime.appRefreshTask = nil
                }
            }
            while let self, !Task.isCancelled, self.runtime.appRefreshToken == token {
                let knownFingerprint = self.runtime.lastAppsFingerprint
                let needsInitialLoad = self.installedApps.isEmpty
                let runForce = currentForce
                let runInvalidateIcons = currentInvalidateIcons

                let snapshot: (fingerprint: UInt64, apps: [InstalledAppItem]?, canonicalPaths: Set<String>) =
                    await Task.detached(priority: .userInitiated) {
                        let fp = LauncherEngine.applicationDirectoriesFingerprint()
                        if !runForce && !needsInitialLoad && fp == knownFingerprint {
                            return (fp, nil, [])
                        }
                        let discovered = LauncherEngine.discoverInstalledApps()
                        var known = Set<String>()
                        known.reserveCapacity(discovered.count * 2)
                        for app in discovered {
                            known.insert(app.id)
                            known.insert(app.url.resolvingSymlinksInPath().standardizedFileURL.path)
                        }
                        return (fp, discovered, known)
                    }.value
                guard !Task.isCancelled, self.runtime.appRefreshToken == token else { return }

                let fingerprintChanged = snapshot.fingerprint != knownFingerprint
                self.runtime.lastAppsFingerprint = snapshot.fingerprint
                self.installAppDirectoryWatcher()
                if let apps = snapshot.apps {
                    self.runtime.knownAppCanonicalPaths = snapshot.canonicalPaths
                    if fingerprintChanged || runInvalidateIcons {
                        IconCache.shared.invalidateAppIcons()
                    }
                    AppUsageTrackerController.shared.ensureSystemProbe(for: apps)
                    self.installedApps = apps
                    if self.isOverlayVisible {
                        IconCache.shared.prewarmDockIcons(self.cachedDockApps)
                    }
                }

                guard self.runtime.appRefreshPending else { break }
                currentForce = self.runtime.appRefreshPendingForce
                currentInvalidateIcons = self.runtime.appRefreshPendingInvalidateIcons
                self.runtime.appRefreshPending = false
                self.runtime.appRefreshPendingForce = false
                self.runtime.appRefreshPendingInvalidateIcons = false
            }
        }
    }
}
