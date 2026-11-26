import Foundation
import LucentCore

extension AppViewModel {
    func primeEverythingIndexOnStartup(scope: EverythingScope) {
        runtime.everythingIndexTask?.cancel()
        let token = UUID()
        runtime.everythingIndexTaskToken = token
        stopIndexWatcher(cancelPendingSave: true)
        runtime.activeIndexScopeKey = nil
        everythingScope = scope
        isIndexingEverything = true
        let excluded = generalPreferences.excludedIndexPathSet

        runtime.everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let volumes = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
            self.cachedVolumes = volumes
            let externals = volumes.filter { $0.mountPath != "/" }

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals, excludedPaths: excluded)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots, excludedPaths: excluded)

            if let meta = await Task.detached(priority: .utility, operation: {
                EverythingSnapshotStore.readHeaderMetadata(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
            }).value {
                guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
                self.everythingNodeCount = meta.nodeCount
                self.isIndexingEverything = false
                self.ensureFSEventWatcherRunning(roots: rootSetup.allRoots, scopeKey: scopeKey, sinceEventId: meta.lastEventId)
                if self.needsEverythingIndexResident || self.isOverlayVisible {
                    self.loadOrBuildEverythingIndex(scope: scope, forceRebuild: false)
                }
                return
            }

            let built = await Self.buildScopedIndex(
                scope: scope, rootSetup: rootSetup, excludedPaths: excluded, priority: .utility
            )
            guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
            if let built {
                self.runtime.reconciledColdScopeKeys.insert(scopeKey)
                self.everythingNodeCount = built.nodes.count
                self.runtime.indexContentRevision &+= 1
                self.ensureFSEventWatcherRunning(roots: built.rootURLs, scopeKey: scopeKey, sinceEventId: built.lastEventId)
                if self.needsEverythingIndexResident || self.isOverlayVisible {
                    self.everythingIndex = built
                    self.runtime.activeIndexScopeKey = scopeKey
                    self.runtime.hasUnsavedIndexChanges = true
                    self.refreshDisplayedCandidates()
                    self.scheduleSnapshotSave(built, scopeKey: scopeKey, revision: self.runtime.indexContentRevision)
                } else {
                    self.runtime.hasUnsavedIndexChanges = false
                    let rev = self.runtime.indexContentRevision
                    self.scheduleSnapshotSave(built, scopeKey: scopeKey, revision: rev, immediate: true)
                    await self.runtime.snapshotSaveTask?.value
                    guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
                    if self.needsEverythingIndexResident || self.isOverlayVisible {
                        self.everythingIndex = built
                        self.runtime.activeIndexScopeKey = scopeKey
                        self.refreshDisplayedCandidates()
                    } else {
                        MemoryStats.reclaimFreeHeapPages()
                    }
                }
            }
            if self.runtime.everythingIndexTaskToken == token {
                self.isIndexingEverything = false
            }
        }
    }

    func rebuildEverythingIndex(scope: EverythingScope) {
        loadOrBuildEverythingIndex(scope: scope, forceRebuild: false)
    }

    func forceRebuildEverythingIndex(scope: EverythingScope? = nil) {
        loadOrBuildEverythingIndex(scope: scope ?? everythingScope, forceRebuild: true)
    }

    func loadOrBuildEverythingIndex(scope: EverythingScope, forceRebuild: Bool) {
        let excluded = generalPreferences.excludedIndexPathSet
        if !forceRebuild,
           !isIndexingEverything,
           everythingScope == scope,
           let existing = everythingIndex,
           !existing.nodes.isEmpty {
            let externals = cachedVolumes.filter { $0.mountPath != "/" }
            let expectedSetup = Self.resolveIndexRoots(scope: scope, externals: externals, excludedPaths: excluded)
            let expectedPaths = expectedSetup.allRoots.map(\.standardizedFileURL.path)
            if existing.rootPaths == expectedPaths {
                let scopeKey = Self.snapshotScopeKey(scope: scope, roots: existing.rootURLs, excludedPaths: excluded)
                runtime.activeIndexScopeKey = scopeKey
                ensureFSEventWatcherRunning(roots: existing.rootURLs, scopeKey: scopeKey, sinceEventId: existing.lastEventId)
                runtime.fsEventWatcher?.flushAsync()
                return
            }
        }

        runtime.everythingIndexTask?.cancel()
        let token = UUID()
        runtime.everythingIndexTaskToken = token
        let scopeOrForceChanged = forceRebuild || everythingScope != scope
        if scopeOrForceChanged {
            stopIndexWatcher(cancelPendingSave: false)
            runtime.activeIndexScopeKey = nil
            everythingIndex = nil
            if isOverlayVisible && omniFilter == .files {
                refreshDisplayedCandidates(resetSelection: true)
            }
        }
        everythingScope = scope
        isIndexingEverything = true

        runtime.everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let volumes = await Task.detached(priority: .userInitiated) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
            self.cachedVolumes = volumes
            let externals = volumes.filter { $0.mountPath != "/" }

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals, excludedPaths: excluded)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots, excludedPaths: excluded)

            if !forceRebuild {
                await self.runtime.snapshotSaveTask?.value
                guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
                if let cached = await Task.detached(priority: .userInitiated, operation: {
                    EverythingSnapshotStore.load(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
                }).value {
                    guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
                    await self.activateAndReconcileCachedSnapshot(cached, scopeKey: scopeKey, excludedPaths: excluded)
                    return
                }
            }

            // Stop any lingering watcher before rebuilding so FSEvents replay cleanly from baselineEventId.
            self.stopIndexWatcher(cancelPendingSave: false)
            self.runtime.activeIndexScopeKey = nil
            let finalIndex = await Self.buildScopedIndex(
                scope: scope, rootSetup: rootSetup, excludedPaths: excluded, priority: .userInitiated
            ) { [weak self] stage1 in
                Task { @MainActor [weak self] in
                    guard let self, self.runtime.everythingIndexTaskToken == token else { return }
                    self.everythingIndex = stage1
                    self.everythingNodeCount = stage1.nodes.count
                    self.refreshDisplayedCandidates()
                }
            }

            guard !Task.isCancelled, self.runtime.everythingIndexTaskToken == token else { return }
            if let finalIndex {
                self.runtime.reconciledColdScopeKeys.insert(scopeKey)
                self.runtime.idleDirtyDirectories.removeAll()
                self.runtime.idleDirtyRecursiveDirectories.removeAll()
                self.everythingIndex = finalIndex
                self.runtime.activeIndexScopeKey = scopeKey
                self.everythingNodeCount = finalIndex.nodes.count
                self.runtime.indexContentRevision &+= 1
                self.runtime.hasUnsavedIndexChanges = true
                self.refreshDisplayedCandidates()
                self.ensureFSEventWatcherRunning(roots: finalIndex.rootURLs, scopeKey: scopeKey, sinceEventId: finalIndex.lastEventId)
                self.scheduleSnapshotSave(finalIndex, scopeKey: scopeKey, revision: self.runtime.indexContentRevision)
                self.scheduleIdleIndexUnloadIfOverlayHidden()
            }
            if self.runtime.everythingIndexTaskToken == token {
                self.isIndexingEverything = false
            }
        }
    }

    private static func buildScopedIndex(
        scope: EverythingScope,
        rootSetup: (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]),
        excludedPaths: Set<String>,
        priority: TaskPriority,
        onStage1: (@Sendable (EverythingIndex) -> Void)? = nil
    ) async -> EverythingIndex? {
        if scope == .allVolumes {
            let stage1 = await Task.detached(priority: priority) {
                try? EverythingIndex.build(rootURLs: rootSetup.fastRoots, maxNodes: 500_000, excludedPaths: excludedPaths)
            }.value
            guard !Task.isCancelled else { return nil }
            if let stage1, !rootSetup.slowRoots.isEmpty, let onStage1 { onStage1(stage1) }
            guard !rootSetup.slowRoots.isEmpty else { return stage1 }
            let stage2 = await Task.detached(priority: .utility) {
                try? EverythingIndex.build(rootURLs: rootSetup.slowRoots, maxNodes: 200_000, excludedPaths: excludedPaths)
            }.value
            guard !Task.isCancelled else { return stage1 }
            return stage2.map { stage1?.merging($0) ?? $0 } ?? stage1
        }
        return await Task.detached(priority: priority) {
            try? EverythingIndex.build(rootURLs: rootSetup.allRoots, maxNodes: 500_000, excludedPaths: excludedPaths)
        }.value
    }

    func scheduleSnapshotSave(
        _ index: EverythingIndex,
        scopeKey: String,
        revision: UInt64? = nil,
        immediate: Bool = false
    ) {
        let targetRev = revision ?? runtime.indexContentRevision
        let previous = runtime.snapshotSaveTask
        let token = UUID()
        runtime.snapshotSaveToken = token
        runtime.snapshotSaveTask = Task { [weak self] in
            _ = await previous?.value
            if !immediate {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, self.runtime.snapshotSaveToken == token else { return }
            }
            let saved = await Task.detached(priority: .utility) {
                EverythingSnapshotStore.save(index, scopeKey: scopeKey) != nil
            }.value
            guard let self else { return }
            if saved, self.runtime.indexContentRevision == targetRev {
                self.runtime.hasUnsavedIndexChanges = false
            }
        }
    }

    func flushSnapshotSynchronouslyIfNeeded() {
        guard runtime.hasUnsavedIndexChanges,
              let index = everythingIndex,
              let scopeKey = runtime.activeIndexScopeKey ?? runtime.watchedIndexScopeKey else { return }
        runtime.hasUnsavedIndexChanges = false
        _ = EverythingSnapshotStore.save(index, scopeKey: scopeKey)
    }

    static func resolveIndexRoots(
        scope: EverythingScope,
        externals: [VolumeSummary],
        excludedPaths: Set<String> = []
    ) -> (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]) {
        scope.persisted.resolveFilteredRoots(externals: externals, excludedPaths: excludedPaths)
    }

    static func snapshotScopeKey(scope: EverythingScope, roots: [URL], excludedPaths: Set<String>) -> String {
        PersistedEverythingScope.snapshotScopeKey(scopeID: scope.id, roots: roots, excludedPaths: excludedPaths)
    }
}
