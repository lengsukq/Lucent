import Foundation
import LucentCore

extension AppViewModel {
    func activateAndReconcileCachedSnapshot(
        _ cached: EverythingIndex,
        scopeKey: String,
        excludedPaths: Set<String>
    ) async {
        let idleDirs = runtime.idleDirtyDirectories.union(runtime.pendingFSEventDirs)
        let idleRecDirs = runtime.idleDirtyRecursiveDirectories.union(runtime.pendingRecursiveFSEventDirs)
        runtime.idleDirtyDirectories.removeAll()
        runtime.idleDirtyRecursiveDirectories.removeAll()
        runtime.pendingFSEventDirs.removeAll()
        runtime.pendingRecursiveFSEventDirs.removeAll()
        runtime.pendingLatestEventId = 0
        runtime.pendingEventIdsWrapped = false
        let needsColdReconcile = !runtime.reconciledColdScopeKeys.contains(scopeKey)

        everythingIndex = cached
        runtime.activeIndexScopeKey = scopeKey
        everythingNodeCount = cached.nodes.count
        isIndexingEverything = false
        refreshDisplayedCandidates()
        ensureFSEventWatcherRunning(roots: cached.rootURLs, scopeKey: scopeKey, sinceEventId: cached.lastEventId)
        runtime.fsEventWatcher?.flushAsync()
        scheduleIdleIndexUnloadIfOverlayHidden()

        guard needsColdReconcile || !idleDirs.isEmpty || !idleRecDirs.isEmpty else { return }
        await runSerializedReconcile(
            baseIndex: cached,
            scopeKey: scopeKey,
            dirtyDirs: idleDirs,
            recursiveDirs: idleRecDirs,
            fullMtimeScan: needsColdReconcile,
            excludedPaths: excludedPaths
        )
    }

    func runSerializedReconcile(
        baseIndex: EverythingIndex,
        scopeKey: String,
        dirtyDirs: Set<String>,
        recursiveDirs: Set<String>,
        fullMtimeScan: Bool,
        excludedPaths: Set<String>
    ) async {
        runtime.fsEventApplyToken = UUID()
        runtime.fsEventApplyTask?.cancel()
        runtime.fsEventApplyTask = nil
        let mergedDirty = dirtyDirs.union(runtime.inFlightFSEventDirs)
        let mergedRec = recursiveDirs.union(runtime.inFlightRecursiveFSEventDirs)
        runtime.inFlightFSEventDirs.removeAll()
        runtime.inFlightRecursiveFSEventDirs.removeAll()

        let token = UUID()
        runtime.reconcileToken = token
        runtime.isReconcilingIndex = true
        defer {
            if self.runtime.reconcileToken == token {
                self.runtime.isReconcilingIndex = false
            }
        }

        let maxNodes = max(700_000, baseIndex.nodes.count + 50_000)
        let synced = await Task.detached(priority: .userInitiated) {
            fullMtimeScan
                ? baseIndex.reconcilingFilesystemChangesSinceSnapshot(
                    additionalDirtyDirs: mergedDirty,
                    recursiveSubtreeDirs: mergedRec,
                    maxNodes: maxNodes,
                    excludedPaths: excludedPaths
                  )
                : baseIndex.applyingFSEventDirectories(
                    mergedDirty,
                    recursiveSubtreeDirs: mergedRec,
                    maxNodes: maxNodes,
                    excludedPaths: excludedPaths
                  )
        }.value
        guard !Task.isCancelled, runtime.reconcileToken == token else { return }

        let wakeRequestedDuringScan = runtime.needsWakeReconcile
        if fullMtimeScan && !wakeRequestedDuringScan {
            runtime.reconciledColdScopeKeys.insert(scopeKey)
        }
        if everythingIndex?.rootPaths == baseIndex.rootPaths {
            let nodesChanged = synced.nodes != baseIndex.nodes
            everythingIndex = synced
            everythingNodeCount = synced.nodes.count
            if nodesChanged {
                runtime.indexContentRevision &+= 1
                runtime.hasUnsavedIndexChanges = true
                refreshDisplayedCandidates()
                scheduleSnapshotSave(synced, scopeKey: scopeKey, revision: runtime.indexContentRevision)
            }
        }
        runtime.isReconcilingIndex = false

        if wakeRequestedDuringScan, let latest = everythingIndex {
            runtime.needsWakeReconcile = false
            await runSerializedReconcile(
                baseIndex: latest,
                scopeKey: scopeKey,
                dirtyDirs: [],
                recursiveDirs: [],
                fullMtimeScan: true,
                excludedPaths: excludedPaths
            )
            return
        }
        drainPendingFSEventsIfNeeded(scopeKey: scopeKey)
    }

    func handleSystemDidWakeForIndex() {
        runtime.reconciledColdScopeKeys.removeAll()
        guard let current = everythingIndex,
              let scopeKey = runtime.activeIndexScopeKey ?? runtime.watchedIndexScopeKey,
              !isIndexingEverything else { return }
        if runtime.isReconcilingIndex {
            runtime.needsWakeReconcile = true
            return
        }
        let excluded = generalPreferences.excludedIndexPathSet
        runtime.everythingIndexTask?.cancel()
        let token = UUID()
        runtime.everythingIndexTaskToken = token
        runtime.everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            await self.runSerializedReconcile(
                baseIndex: current, scopeKey: scopeKey,
                dirtyDirs: [], recursiveDirs: [], fullMtimeScan: true, excludedPaths: excluded
            )
        }
    }

    func prepareIndexForIdleUnload() {
        guard let snapshotToSave = everythingIndex else { return }
        let scopeKey = runtime.activeIndexScopeKey ?? runtime.watchedIndexScopeKey
        if runtime.isReconcilingIndex || isIndexingEverything {
            runtime.everythingIndexTaskToken = UUID()
            runtime.everythingIndexTask?.cancel()
            runtime.everythingIndexTask = nil
            runtime.reconcileToken = UUID()
            runtime.isReconcilingIndex = false
            runtime.needsWakeReconcile = false
            isIndexingEverything = false
            if let scopeKey { runtime.reconciledColdScopeKeys.remove(scopeKey) }
        }
        let unappliedDirs = runtime.inFlightFSEventDirs.union(runtime.pendingFSEventDirs)
        let unappliedRec = runtime.inFlightRecursiveFSEventDirs.union(runtime.pendingRecursiveFSEventDirs)
        if !unappliedDirs.isEmpty || !unappliedRec.isEmpty {
            if runtime.idleDirtyDirectories.count + unappliedDirs.count <= OverlayAndIndexRuntimeState.maxIdleDirtyDirectories {
                runtime.idleDirtyDirectories.formUnion(unappliedDirs)
                runtime.idleDirtyRecursiveDirectories.formUnion(unappliedRec)
            } else {
                runtime.idleDirtyDirectories.removeAll()
                runtime.idleDirtyRecursiveDirectories.removeAll()
                if let scopeKey { runtime.reconciledColdScopeKeys.remove(scopeKey) }
            }
        }
        runtime.fsEventApplyToken = UUID()
        runtime.fsEventApplyTask?.cancel()
        runtime.fsEventApplyTask = nil
        runtime.pendingFSEventDirs.removeAll()
        runtime.pendingRecursiveFSEventDirs.removeAll()
        runtime.inFlightFSEventDirs.removeAll()
        runtime.inFlightRecursiveFSEventDirs.removeAll()
        runtime.pendingLatestEventId = 0
        runtime.pendingEventIdsWrapped = false

        if runtime.hasUnsavedIndexChanges, let scopeKey {
            scheduleSnapshotSave(snapshotToSave, scopeKey: scopeKey, revision: runtime.indexContentRevision, immediate: true)
        }
        everythingIndex = nil
        runtime.activeIndexScopeKey = nil
        displayedCandidates = []
        MemoryStats.reclaimFreeHeapPages()
    }
}
