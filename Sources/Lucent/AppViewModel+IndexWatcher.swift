import Foundation
import LucentCore

extension AppViewModel {
    func activateAndReconcileCachedSnapshot(
        _ cached: EverythingIndex,
        scopeKey: String,
        excludedPaths: Set<String>
    ) async {
        let idleDirs = runtime.idleDirtyDirectories
        let idleRecDirs = runtime.idleDirtyRecursiveDirectories
        runtime.idleDirtyDirectories.removeAll()
        runtime.idleDirtyRecursiveDirectories.removeAll()
        let needsColdReconcile = !runtime.reconciledColdScopeKeys.contains(scopeKey)

        everythingIndex = cached
        everythingNodeCount = cached.nodes.count
        isIndexingEverything = false
        refreshDisplayedCandidates()
        ensureFSEventWatcherRunning(roots: cached.rootURLs, scopeKey: scopeKey, sinceEventId: cached.lastEventId)

        guard needsColdReconcile || !idleDirs.isEmpty || !idleRecDirs.isEmpty else { return }
        let synced = await Task.detached(priority: .userInitiated) {
            needsColdReconcile
                ? cached.reconcilingFilesystemChangesSinceSnapshot(
                    additionalDirtyDirs: idleDirs,
                    recursiveSubtreeDirs: idleRecDirs,
                    excludedPaths: excludedPaths
                  )
                : cached.applyingFSEventDirectories(
                    idleDirs,
                    recursiveSubtreeDirs: idleRecDirs,
                    excludedPaths: excludedPaths
                  )
        }.value
        guard !Task.isCancelled else { return }
        runtime.reconciledColdScopeKeys.insert(scopeKey)
        if everythingIndex?.rootPaths == cached.rootPaths {
            everythingIndex = synced
            everythingNodeCount = synced.nodes.count
            refreshDisplayedCandidates()
            scheduleSnapshotSave(synced, scopeKey: scopeKey)
        }
    }

    func ensureFSEventWatcherRunning(roots: [URL], scopeKey: String, sinceEventId: UInt64 = 0) {
        if runtime.fsEventWatcher != nil, runtime.watchedIndexScopeKey == scopeKey {
            return
        }
        runtime.fsEventWatcher?.stop()
        runtime.fsEventWatcher = nil
        runtime.watchedIndexScopeKey = nil

        let vols = cachedVolumes.sorted { $0.mountPath.count > $1.mountPath.count }
        let watchRoots = roots.filter { root in
            let path = root.standardizedFileURL.path
            let summary = vols.first(where: { path == $0.mountPath || path.hasPrefix($0.mountPath == "/" ? "/" : $0.mountPath + "/") })
                ?? VolumeInspector.inspect(url: root)
            return summary.map { !VolumeInspector.isSlowOrRemoteVolume($0) } ?? true
        }
        guard !watchRoots.isEmpty else { return }
        runtime.watchedIndexScopeKey = scopeKey
        let resumeSince: UInt64? = sinceEventId > 0 ? sinceEventId : nil

        runtime.fsEventWatcher = EverythingFSEventWatcher(
            roots: watchRoots,
            sinceEventId: resumeSince,
            debounceInterval: 0.25
        ) { [weak self] batch in
            Task { @MainActor [weak self] in
                self?.enqueueFSEventBatch(batch, scopeKey: scopeKey)
            }
        }
    }

    private func enqueueFSEventBatch(_ batch: EverythingFSEventBatch, scopeKey: String) {
        guard runtime.watchedIndexScopeKey == scopeKey else { return }
        guard let current = everythingIndex else {
            guard !batch.directories.isEmpty || !batch.recursiveDirectories.isEmpty else { return }
            if runtime.idleDirtyDirectories.count + batch.directories.count <= OverlayAndIndexRuntimeState.maxIdleDirtyDirectories {
                runtime.idleDirtyDirectories.formUnion(batch.directories)
                runtime.idleDirtyRecursiveDirectories.formUnion(batch.recursiveDirectories)
            } else {
                runtime.idleDirtyDirectories.removeAll()
                runtime.idleDirtyRecursiveDirectories.removeAll()
                runtime.reconciledColdScopeKeys.remove(scopeKey)
            }
            return
        }

        if !batch.directories.isEmpty { runtime.pendingFSEventDirs.formUnion(batch.directories) }
        if !batch.recursiveDirectories.isEmpty { runtime.pendingRecursiveFSEventDirs.formUnion(batch.recursiveDirectories) }
        if batch.latestEventId > runtime.pendingLatestEventId { runtime.pendingLatestEventId = batch.latestEventId }
        guard !runtime.pendingFSEventDirs.isEmpty || !runtime.pendingRecursiveFSEventDirs.isEmpty else {
            if runtime.pendingLatestEventId > current.lastEventId {
                everythingIndex = current.withUpdatedEventId(runtime.pendingLatestEventId)
            }
            runtime.pendingLatestEventId = 0
            return
        }

        guard runtime.fsEventApplyTask == nil else { return }
        runtime.fsEventApplyTask = Task { @MainActor [weak self] in
            defer { self?.runtime.fsEventApplyTask = nil }
            while let self, !Task.isCancelled {
                let dirs = self.runtime.pendingFSEventDirs
                let recDirs = self.runtime.pendingRecursiveFSEventDirs
                let targetEventId = self.runtime.pendingLatestEventId
                guard !dirs.isEmpty || !recDirs.isEmpty, let baseIndex = self.everythingIndex else { break }
                self.runtime.pendingFSEventDirs.removeAll()
                self.runtime.pendingRecursiveFSEventDirs.removeAll()
                self.runtime.pendingLatestEventId = 0

                let activeExcluded = self.generalPreferences.excludedIndexPathSet
                let updated = await Task.detached(priority: .userInitiated) {
                    baseIndex.applyingFSEventDirectories(
                        dirs,
                        recursiveSubtreeDirs: recDirs,
                        latestEventId: targetEventId > 0 ? targetEventId : nil,
                        excludedPaths: activeExcluded
                    )
                }.value
                guard !Task.isCancelled, self.everythingIndex?.rootPaths == baseIndex.rootPaths else { break }
                self.everythingIndex = updated
                self.everythingNodeCount = updated.nodes.count
                if self.isOverlayVisible && (self.omniFilter == .files || !self.overlayQuery.isEmpty) {
                    self.refreshDisplayedCandidates()
                }
                self.scheduleSnapshotSave(updated, scopeKey: scopeKey)
            }
        }
    }

    func stopIndexWatcher(cancelPendingSave: Bool = false) {
        runtime.stopIndexWatcher(cancelPendingSave: cancelPendingSave)
    }
}
