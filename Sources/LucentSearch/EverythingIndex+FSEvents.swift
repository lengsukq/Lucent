import Darwin
import Foundation
import LucentFoundation

public extension EverythingIndex {
    func directoriesModifiedSinceSnapshot(safetyMarginSeconds: TimeInterval = 2.0) -> Set<String> {
        guard !rootPaths.isEmpty else { return [] }
        let cutoff = builtAt.timeIntervalSince1970 - safetyMarginSeconds
        var changed = Set<String>()

        func inspectDirectory(path: String, fallbackParent: String?) {
            var st = stat()
            guard path.withCString({ stat($0, &st) == 0 }), (st.st_mode & S_IFMT) == S_IFDIR else {
                if let fallbackParent { changed.insert(fallbackParent) }
                else { changed.insert(path) }
                return
            }
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) * 1e-9
            if mtime >= cutoff {
                changed.insert(path)
            }
        }

        for rootPath in rootPaths {
            inspectDirectory(path: rootPath, fallbackParent: nil)
        }

        var dirPaths: [Int32: String] = [:]
        dirPaths.reserveCapacity(min(nodes.count / 6 + 16, 32_768))
        for (idx, node) in nodes.enumerated() where node.isDirectory {
            let rootIdx = Int(node.rootIndex)
            guard rootIdx >= 0, rootIdx < rootPaths.count else { continue }
            let parentPath: String
            if node.parentID >= 0, let cachedParent = dirPaths[node.parentID] {
                parentPath = cachedParent
            } else {
                parentPath = rootPaths[rootIdx]
            }
            let fullPath = parentPath == "/" ? "/\(node.name)" : "\(parentPath)/\(node.name)"
            dirPaths[Int32(idx)] = fullPath
            inspectDirectory(path: fullPath, fallbackParent: parentPath)
        }
        return changed
    }

    func reconcilingFilesystemChangesSinceSnapshot(
        additionalDirtyDirs: Set<String> = [],
        recursiveSubtreeDirs: Set<String> = [],
        maxNodes: Int = 450_000,
        excludedPaths: Set<String> = [],
        safetyMarginSeconds: TimeInterval = 2.0
    ) -> EverythingIndex {
        var stale = directoriesModifiedSinceSnapshot(safetyMarginSeconds: safetyMarginSeconds)
        if !additionalDirtyDirs.isEmpty {
            stale.formUnion(additionalDirtyDirs)
        }
        guard !stale.isEmpty || !recursiveSubtreeDirs.isEmpty else {
            return withUpdatedEventId(EverythingFSEventWatcher.currentEventId())
        }
        return applyingFSEventDirectories(
            stale,
            recursiveSubtreeDirs: recursiveSubtreeDirs,
            latestEventId: EverythingFSEventWatcher.currentEventId(),
            maxNodes: maxNodes,
            excludedPaths: excludedPaths
        )
    }

    func applyingFSEventDirectories(
        _ rawChangedDirs: Set<String>,
        recursiveSubtreeDirs: Set<String> = [],
        latestEventId: UInt64? = nil,
        maxNodes: Int = 450_000,
        excludedPaths: Set<String> = []
    ) -> EverythingIndex {
        let resolvedNextEventId = max(lastEventId, latestEventId ?? EverythingFSEventWatcher.currentEventId())
        guard (!rawChangedDirs.isEmpty || !recursiveSubtreeDirs.isEmpty), !rootPaths.isEmpty else {
            return withUpdatedEventId(resolvedNextEventId)
        }
        let normalizedExclusions = Self.normalizedExcludedSet(excludedPaths)
        let resolvedRoots = rootPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }

        func mapToRootSpace(_ inputPaths: Set<String>) -> Set<String> {
            var mappedSet = Set<String>()
            for raw in inputPaths {
                let std = URL(fileURLWithPath: raw).standardizedFileURL.path
                if !normalizedExclusions.isEmpty && Self.isPathExcluded(std, excludedPaths: normalizedExclusions) { continue }
                let res = URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL.path
                for (idx, rootPath) in rootPaths.enumerated() {
                    let resRoot = resolvedRoots[idx]
                    if std == rootPath || std.hasPrefix(rootPath == "/" ? "/" : rootPath + "/") {
                        mappedSet.insert(std)
                    }
                    if res == resRoot || res.hasPrefix(resRoot == "/" ? "/" : resRoot + "/") {
                        let mapped = resRoot == rootPath ? res : rootPath + String(res.dropFirst(resRoot.count))
                        if normalizedExclusions.isEmpty || !Self.isPathExcluded(mapped, excludedPaths: normalizedExclusions) {
                            mappedSet.insert(mapped)
                        }
                    }
                }
            }
            return mappedSet
        }

        let recursiveSet = mapToRootSpace(recursiveSubtreeDirs)
        var changedSet = mapToRootSpace(rawChangedDirs)
        changedSet.formUnion(recursiveSet)
        guard !changedSet.isEmpty else {
            return withUpdatedEventId(resolvedNextEventId)
        }

        func isUnderRecursiveSubtree(_ path: String) -> Bool {
            guard !recursiveSet.isEmpty else { return false }
            if recursiveSet.contains(path) { return true }
            for rec in recursiveSet where path.hasPrefix(rec == "/" ? "/" : rec + "/") {
                return true
            }
            return false
        }

        var oldPaths = Array(repeating: "", count: nodes.count)
        var oldChildren = Array(repeating: [Int](), count: nodes.count)
        var oldRootChildren = Array(repeating: [Int](), count: rootPaths.count)
        var oldDirIDByPath: [String: Int] = [:]
        for idx in 0..<nodes.count {
            let node = nodes[idx]
            let parentID = Int(node.parentID)
            let rootIdx = Int(node.rootIndex)
            let parentPath = parentID >= 0 && parentID < idx ? oldPaths[parentID] : rootPaths[rootIdx]
            let fullPath = parentPath == "/" ? "/\(node.name)" : "\(parentPath)/\(node.name)"
            oldPaths[idx] = fullPath
            if parentID >= 0 && parentID < idx {
                oldChildren[parentID].append(idx)
            } else if rootIdx < oldRootChildren.count {
                oldRootChildren[rootIdx].append(idx)
            }
            if node.isDirectory { oldDirIDByPath[fullPath] = idx }
        }

        struct QueueItem { let path: String; let parentNewID: Int32; let oldDirID: Int? }
        var newNodes: [IndexedNode] = []
        newNodes.reserveCapacity(min(maxNodes, max(nodes.count, 1024)))
        var queues: [[QueueItem]] = rootPaths.map { [QueueItem(path: $0, parentNewID: -1, oldDirID: nil)] }
        var heads = Array(repeating: 0, count: rootPaths.count)
        var reachedLimit = false
        var active = true

        while active && !reachedLimit {
            active = false
            for rootIdx in 0..<rootPaths.count {
                guard heads[rootIdx] < queues[rootIdx].count else { continue }
                active = true
                let item = queues[rootIdx][heads[rootIdx]]
                heads[rootIdx] += 1
                if !normalizedExclusions.isEmpty && Self.isPathExcluded(item.path, excludedPaths: normalizedExclusions) {
                    continue
                }
                let isRoot = item.parentNewID == -1
                let forceSubtree = isUnderRecursiveSubtree(item.path)
                let shouldScan = forceSubtree || changedSet.contains(item.path) || (!isRoot && item.oldDirID == nil)

                if shouldScan {
                    let children = DirectoryEntryEnumerator.enumerate(
                        at: item.path,
                        includeHidden: false,
                        excludedPaths: normalizedExclusions
                    )
                    for child in children {
                        if newNodes.count >= maxNodes { reachedLimit = true; break }
                        let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(
                            parentID: item.parentNewID,
                            rootIndex: UInt16(rootIdx),
                            isDirectory: child.isDirectory,
                            name: child.name
                        ))
                        if child.isDirectory {
                            let childPath = item.path == "/" ? "/\(child.name)" : "\(item.path)/\(child.name)"
                            let matchingOld = forceSubtree ? nil : (changedSet.contains(item.path) ? oldDirIDByPath[childPath] : nil)
                            queues[rootIdx].append(QueueItem(path: childPath, parentNewID: newID, oldDirID: matchingOld))
                        }
                    }
                } else {
                    let existing = isRoot ? oldRootChildren[rootIdx] : (item.oldDirID.map { oldChildren[$0] } ?? [])
                    for oldIdx in existing {
                        if newNodes.count >= maxNodes { reachedLimit = true; break }
                        let childPath = oldPaths[oldIdx]
                        if !normalizedExclusions.isEmpty && Self.isPathExcluded(childPath, excludedPaths: normalizedExclusions) {
                            continue
                        }
                        let old = nodes[oldIdx]
                        let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(
                            parentID: item.parentNewID,
                            rootIndex: UInt16(rootIdx),
                            isDirectory: old.isDirectory,
                            name: old.name
                        ))
                        if old.isDirectory {
                            queues[rootIdx].append(QueueItem(path: childPath, parentNewID: newID, oldDirID: oldIdx))
                        }
                    }
                }
                if reachedLimit { break }
            }
        }
        return EverythingIndex(
            rootURLs: rootURLs,
            nodes: newNodes,
            builtAt: Date(),
            reachedNodeLimit: reachedLimit,
            lastEventId: resolvedNextEventId
        )
    }
}
