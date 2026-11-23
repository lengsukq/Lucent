import Foundation
import LucentCore

extension AppViewModel {
    func primeEverythingIndexOnStartup(scope: EverythingScope) {
        runtime.everythingIndexTask?.cancel()
        stopIndexWatcher(cancelPendingSave: true)
        everythingScope = scope
        isIndexingEverything = true
        let excluded = generalPreferences.excludedIndexPathSet

        runtime.everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let externals = await Task.detached(priority: .utility) { VolumeInspector.externalVolumes() }.value
            guard !Task.isCancelled else { return }
            let volumes = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled else { return }
            self.cachedVolumes = volumes

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots, excludedPaths: excluded)

            if let meta = await Task.detached(priority: .utility, operation: {
                EverythingSnapshotStore.readHeaderMetadata(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
            }).value {
                guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
            if let built {
                self.runtime.reconciledColdScopeKeys.insert(scopeKey)
                self.everythingNodeCount = built.nodes.count
                self.ensureFSEventWatcherRunning(roots: built.rootURLs, scopeKey: scopeKey, sinceEventId: built.lastEventId)
                if self.needsEverythingIndexResident || self.isOverlayVisible {
                    self.everythingIndex = built
                    self.refreshDisplayedCandidates()
                    self.scheduleSnapshotSave(built, scopeKey: scopeKey)
                } else {
                    _ = await Task.detached(priority: .utility) {
                        EverythingSnapshotStore.save(built, scopeKey: scopeKey)
                    }.value
                    MemoryStats.reclaimFreeHeapPages()
                }
            }
            self.isIndexingEverything = false
        }
    }

    func rebuildEverythingIndex(scope: EverythingScope) {
        loadOrBuildEverythingIndex(scope: scope, forceRebuild: false)
    }

    func forceRebuildEverythingIndex(scope: EverythingScope? = nil) {
        loadOrBuildEverythingIndex(scope: scope ?? everythingScope, forceRebuild: true)
    }

    func loadOrBuildEverythingIndex(scope: EverythingScope, forceRebuild: Bool) {
        if !forceRebuild,
           everythingScope == scope,
           let existing = everythingIndex,
           !existing.nodes.isEmpty {
            let scopeKey = Self.snapshotScopeKey(
                scope: scope, roots: existing.rootURLs, excludedPaths: generalPreferences.excludedIndexPathSet
            )
            ensureFSEventWatcherRunning(roots: existing.rootURLs, scopeKey: scopeKey, sinceEventId: existing.lastEventId)
            return
        }

        runtime.everythingIndexTask?.cancel()
        if forceRebuild || everythingScope != scope {
            stopIndexWatcher(cancelPendingSave: true)
        }
        everythingScope = scope
        isIndexingEverything = true
        let excluded = generalPreferences.excludedIndexPathSet

        runtime.everythingIndexTask = Task { [weak self] in
            guard let self else { return }
            let externals = await Task.detached(priority: .userInitiated) { VolumeInspector.externalVolumes() }.value
            guard !Task.isCancelled else { return }
            self.cachedVolumes = await Task.detached(priority: .utility) { VolumeInspector.mountedVolumes() }.value
            guard !Task.isCancelled else { return }

            let rootSetup = Self.resolveIndexRoots(scope: scope, externals: externals)
            let scopeKey = Self.snapshotScopeKey(scope: scope, roots: rootSetup.allRoots, excludedPaths: excluded)

            if !forceRebuild,
               let cached = await Task.detached(priority: .userInitiated, operation: {
                   EverythingSnapshotStore.load(scopeKey: scopeKey, expectedRoots: rootSetup.allRoots)
               }).value {
                guard !Task.isCancelled else { return }
                await self.activateAndReconcileCachedSnapshot(cached, scopeKey: scopeKey, excludedPaths: excluded)
                return
            }

            let finalIndex = await Self.buildScopedIndex(
                scope: scope, rootSetup: rootSetup, excludedPaths: excluded, priority: .userInitiated
            ) { [weak self] stage1 in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.everythingIndex = stage1
                    self.everythingNodeCount = stage1.nodes.count
                    self.refreshDisplayedCandidates()
                }
            }

            guard !Task.isCancelled else { return }
            if let finalIndex {
                self.runtime.reconciledColdScopeKeys.insert(scopeKey)
                self.runtime.idleDirtyDirectories.removeAll()
                self.runtime.idleDirtyRecursiveDirectories.removeAll()
                self.everythingIndex = finalIndex
                self.everythingNodeCount = finalIndex.nodes.count
                self.refreshDisplayedCandidates()
                self.ensureFSEventWatcherRunning(roots: finalIndex.rootURLs, scopeKey: scopeKey, sinceEventId: finalIndex.lastEventId)
                self.scheduleSnapshotSave(finalIndex, scopeKey: scopeKey)
            }
            self.isIndexingEverything = false
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
                try? EverythingIndex.build(rootURLs: rootSetup.fastRoots, maxNodes: 350_000, excludedPaths: excludedPaths)
            }.value
            guard !Task.isCancelled else { return nil }
            if let stage1, let onStage1 { onStage1(stage1) }
            guard !rootSetup.slowRoots.isEmpty else { return stage1 }
            let stage2 = await Task.detached(priority: .utility) {
                try? EverythingIndex.build(rootURLs: rootSetup.slowRoots, maxNodes: 180_000, excludedPaths: excludedPaths)
            }.value
            guard !Task.isCancelled else { return stage1 }
            return stage2.map { stage1?.merging($0) ?? $0 } ?? stage1
        }
        return await Task.detached(priority: priority) {
            try? EverythingIndex.build(rootURLs: rootSetup.allRoots, maxNodes: 400_000, excludedPaths: excludedPaths)
        }.value
    }

    func scheduleSnapshotSave(_ index: EverythingIndex, scopeKey: String) {
        runtime.snapshotSaveTask?.cancel()
        runtime.snapshotSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .utility) {
                EverythingSnapshotStore.save(index, scopeKey: scopeKey)
            }.value
        }
    }

    static func resolveIndexRoots(
        scope: EverythingScope,
        externals: [VolumeSummary]
    ) -> (fastRoots: [URL], slowRoots: [URL], allRoots: [URL]) {
        if scope == .allVolumes {
            let nonSMB = externals.filter { $0.formatKind != .smb }
            let fast = [FileManager.default.homeDirectoryForCurrentUser]
                + nonSMB.filter { !VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            let slow = nonSMB.filter { VolumeInspector.isSlowOrRemoteVolume($0) }.map { URL(fileURLWithPath: $0.mountPath) }
            return (fast, slow, fast + slow)
        }
        let roots = scope.resolveRootURLs(volumes: externals)
        return (roots, [], roots)
    }

    static func snapshotScopeKey(scope: EverythingScope, roots: [URL], excludedPaths: Set<String>) -> String {
        let joinedRoots = roots.map(\.standardizedFileURL.path).sorted().joined(separator: "|")
        guard !excludedPaths.isEmpty else { return "\(scope.id)|\(joinedRoots)" }
        let joinedExcl = excludedPaths.sorted().joined(separator: ";")
        return "\(scope.id)|\(joinedRoots)|excl:\(joinedExcl)"
    }
}
