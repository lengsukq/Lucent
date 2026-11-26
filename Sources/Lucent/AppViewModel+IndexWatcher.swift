import Foundation
import LucentCore

extension AppViewModel {
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

        let resolvedWatchRoots = watchRoots.map { EverythingFSEventWatcher.canonicalKernelPath($0.path) }
        let rawExcluded = EverythingIndex.normalizedExcludedSet(generalPreferences.excludedIndexPathSet)
        let excludedPaths = rawExcluded.union(
            rawExcluded.map { EverythingFSEventWatcher.canonicalKernelPath($0) }
        )
        let directoryFilter: @Sendable (String) -> Bool = { rawDir in
            if !excludedPaths.isEmpty && EverythingIndex.isPathExcluded(rawDir, excludedPaths: excludedPaths) {
                return false
            }
            for root in resolvedWatchRoots {
                if rawDir == root || rawDir.hasPrefix(root == "/" ? "/" : root + "/") {
                    return !DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(rawDir, relativeTo: root)
                }
            }
            return false
        }

        runtime.fsEventWatcher = EverythingFSEventWatcher(
            roots: watchRoots,
            sinceEventId: resumeSince,
            debounceInterval: 0.2,
            maxWaitInterval: 0.55,
            ignoreNonStructuralFileModifications: true,
            shouldTrackDirectory: directoryFilter
        ) { [weak self] batch in
            Task { @MainActor [weak self] in
                self?.enqueueFSEventBatch(batch, scopeKey: scopeKey)
            }
        }
    }

    func notifyLocalFileOperations(affectedDirs: [URL]) {
        guard let scopeKey = runtime.activeIndexScopeKey ?? runtime.watchedIndexScopeKey, !affectedDirs.isEmpty else { return }
        let excluded = EverythingIndex.normalizedExcludedSet(generalPreferences.excludedIndexPathSet)
        let activeRoots: [String] = if let current = everythingIndex {
            current.rootPaths
        } else {
            Self.resolveIndexRoots(
                scope: everythingScope, externals: cachedVolumes.filter { $0.mountPath != "/" }, excludedPaths: excluded
            ).allRoots.map(\.standardizedFileURL.path)
        }
        let filtered = Set(affectedDirs.map(\.standardizedFileURL.path).filter { dir in
            guard !EverythingIndex.isPathExcluded(dir, excludedPaths: excluded) else { return false }
            return activeRoots.contains { root in
                (dir == root || dir.hasPrefix(root == "/" ? "/" : root + "/"))
                    && !DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(dir, relativeTo: root)
            }
        })
        guard !filtered.isEmpty else { return }
        enqueueFSEventBatch(EverythingFSEventBatch(directories: filtered, latestEventId: 0), scopeKey: scopeKey)
    }

    func enqueueFSEventBatch(_ batch: EverythingFSEventBatch, scopeKey: String) {
        let matchesActive = runtime.activeIndexScopeKey == scopeKey || runtime.watchedIndexScopeKey == scopeKey
        guard matchesActive else { return }
        guard let current = everythingIndex else {
            guard !batch.directories.isEmpty || !batch.recursiveDirectories.isEmpty || batch.eventIdsWrapped else { return }
            if batch.eventIdsWrapped || runtime.idleDirtyDirectories.count + batch.directories.count > OverlayAndIndexRuntimeState.maxIdleDirtyDirectories {
                runtime.idleDirtyDirectories.removeAll()
                runtime.idleDirtyRecursiveDirectories.removeAll()
                runtime.reconciledColdScopeKeys.remove(scopeKey)
            } else {
                runtime.idleDirtyDirectories.formUnion(batch.directories)
                runtime.idleDirtyRecursiveDirectories.formUnion(batch.recursiveDirectories)
            }
            return
        }

        if !batch.directories.isEmpty { runtime.pendingFSEventDirs.formUnion(batch.directories) }
        if !batch.recursiveDirectories.isEmpty { runtime.pendingRecursiveFSEventDirs.formUnion(batch.recursiveDirectories) }
        if batch.eventIdsWrapped {
            runtime.pendingEventIdsWrapped = true
            runtime.pendingLatestEventId = batch.latestEventId
        } else if batch.latestEventId > runtime.pendingLatestEventId {
            runtime.pendingLatestEventId = batch.latestEventId
        }
        guard !runtime.isReconcilingIndex else { return }

        guard !runtime.pendingFSEventDirs.isEmpty || !runtime.pendingRecursiveFSEventDirs.isEmpty else {
            if runtime.pendingEventIdsWrapped || runtime.pendingLatestEventId > current.lastEventId {
                everythingIndex = current.withUpdatedEventId(runtime.pendingLatestEventId, allowReset: runtime.pendingEventIdsWrapped)
            }
            runtime.pendingLatestEventId = 0
            runtime.pendingEventIdsWrapped = false
            return
        }
        drainPendingFSEventsIfNeeded(scopeKey: scopeKey)
    }

    func drainPendingFSEventsIfNeeded(scopeKey: String) {
        guard !runtime.isReconcilingIndex, runtime.fsEventApplyTask == nil else { return }
        guard !runtime.pendingFSEventDirs.isEmpty || !runtime.pendingRecursiveFSEventDirs.isEmpty else { return }

        let token = UUID()
        runtime.fsEventApplyToken = token
        runtime.fsEventApplyTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.runtime.fsEventApplyToken == token {
                    self.runtime.inFlightFSEventDirs.removeAll()
                    self.runtime.inFlightRecursiveFSEventDirs.removeAll()
                    self.runtime.fsEventApplyTask = nil
                }
            }
            while let self, !Task.isCancelled, self.runtime.fsEventApplyToken == token, !self.runtime.isReconcilingIndex {
                let dirs = self.runtime.pendingFSEventDirs
                let recDirs = self.runtime.pendingRecursiveFSEventDirs
                let targetEventId = self.runtime.pendingLatestEventId
                let wrapped = self.runtime.pendingEventIdsWrapped
                guard !dirs.isEmpty || !recDirs.isEmpty, let baseIndex = self.everythingIndex else { break }
                self.runtime.pendingFSEventDirs.removeAll()
                self.runtime.pendingRecursiveFSEventDirs.removeAll()
                self.runtime.pendingLatestEventId = 0
                self.runtime.pendingEventIdsWrapped = false
                self.runtime.inFlightFSEventDirs = dirs
                self.runtime.inFlightRecursiveFSEventDirs = recDirs

                let activeExcluded = self.generalPreferences.excludedIndexPathSet
                let maxNodes = max(700_000, baseIndex.nodes.count + 50_000)
                let updated = await Task.detached(priority: .userInitiated) {
                    baseIndex.applyingFSEventDirectories(
                        dirs,
                        recursiveSubtreeDirs: recDirs,
                        latestEventId: (targetEventId > 0 || wrapped) ? targetEventId : nil,
                        maxNodes: maxNodes,
                        excludedPaths: activeExcluded,
                        resetEventId: wrapped
                    )
                }.value
                guard !Task.isCancelled, self.runtime.fsEventApplyToken == token,
                      self.everythingIndex?.rootPaths == baseIndex.rootPaths else { break }
                self.runtime.inFlightFSEventDirs.removeAll()
                self.runtime.inFlightRecursiveFSEventDirs.removeAll()

                let nodesChanged = updated.nodes != baseIndex.nodes
                self.everythingIndex = updated
                self.everythingNodeCount = updated.nodes.count
                if nodesChanged {
                    self.runtime.indexContentRevision &+= 1
                    self.runtime.hasUnsavedIndexChanges = true
                    if self.isOverlayVisible && (self.omniFilter == .files || !self.overlayQuery.isEmpty) {
                        self.refreshDisplayedCandidates()
                    }
                    self.scheduleSnapshotSave(updated, scopeKey: scopeKey, revision: self.runtime.indexContentRevision)
                }
            }
        }
    }

    func stopIndexWatcher(cancelPendingSave: Bool = false) {
        runtime.stopIndexWatcher(cancelPendingSave: cancelPendingSave)
    }
}
