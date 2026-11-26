import Darwin
import Foundation
import LucentFoundation

public extension EverythingIndex {
    func directoriesModifiedSinceSnapshot(safetyMarginSeconds: TimeInterval = 2.0) -> Set<String> {
        modifiedDirectoriesSinceSnapshot(safetyMarginSeconds: safetyMarginSeconds).changed
    }

    func modifiedDirectoriesSinceSnapshot(
        safetyMarginSeconds: TimeInterval = 2.0
    ) -> (changed: Set<String>, recursive: Set<String>) {
        guard !rootPaths.isEmpty else { return ([], []) }
        let cutoff = builtAt.timeIntervalSince1970 - safetyMarginSeconds
        var changed = Set<String>()
        var recursive = Set<String>()

        func inspectDirectory(path: String, fallbackParent: String?, isRoot: Bool) {
            var st = stat()
            let ok = path.withCString { isRoot ? stat($0, &st) == 0 : lstat($0, &st) == 0 }
            guard ok, (st.st_mode & S_IFMT) == S_IFDIR else {
                if let fallbackParent { changed.insert(fallbackParent) }
                else { changed.insert(path) }
                return
            }
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) * 1e-9
            let ctime = Double(st.st_ctimespec.tv_sec) + Double(st.st_ctimespec.tv_nsec) * 1e-9
            if max(mtime, ctime) >= cutoff {
                changed.insert(path)
                // A moved/replaced directory updates ctime (and parent mtime) without touching nested subdirs.
                let parentChanged = fallbackParent.map { changed.contains($0) } ?? false
                if !isRoot && ctime >= cutoff && (mtime < cutoff || parentChanged || ctime > mtime + 0.001) {
                    recursive.insert(path)
                }
            }
        }

        for rootPath in rootPaths { inspectDirectory(path: rootPath, fallbackParent: nil, isRoot: true) }

        var dirPaths: [Int32: String] = [:]
        dirPaths.reserveCapacity(min(nodes.count / 6 + 16, 32_768))
        for (idx, node) in nodes.enumerated() where node.isDirectory {
            let rootIdx = Int(node.rootIndex)
            guard rootIdx >= 0, rootIdx < rootPaths.count else { continue }
            let parentPath = (node.parentID >= 0 ? dirPaths[node.parentID] : nil) ?? rootPaths[rootIdx]
            let fullPath = parentPath == "/" ? "/\(node.name)" : "\(parentPath)/\(node.name)"
            dirPaths[Int32(idx)] = fullPath
            inspectDirectory(path: fullPath, fallbackParent: parentPath, isRoot: false)
        }
        return (changed, recursive)
    }

    func reconcilingFilesystemChangesSinceSnapshot(
        additionalDirtyDirs: Set<String> = [],
        recursiveSubtreeDirs: Set<String> = [],
        maxNodes: Int = 700_000,
        excludedPaths: Set<String> = [],
        safetyMarginSeconds: TimeInterval = 2.0
    ) -> EverythingIndex {
        let scanStartedAt = Date()
        let baselineEventId = EverythingFSEventWatcher.currentEventId()
        let detected = modifiedDirectoriesSinceSnapshot(safetyMarginSeconds: safetyMarginSeconds)
        var stale = detected.changed
        if !additionalDirtyDirs.isEmpty { stale.formUnion(additionalDirtyDirs) }
        let recDirs = detected.recursive.union(recursiveSubtreeDirs)
        guard !stale.isEmpty || !recDirs.isEmpty else {
            return EverythingIndex(
                rootURLs: rootURLs, nodes: nodes, builtAt: scanStartedAt,
                reachedNodeLimit: reachedNodeLimit, lastEventId: max(lastEventId, baselineEventId)
            )
        }
        return applyingFSEventDirectories(
            stale,
            recursiveSubtreeDirs: recDirs,
            latestEventId: baselineEventId,
            maxNodes: maxNodes,
            excludedPaths: excludedPaths,
            updatedBuiltAt: scanStartedAt
        )
    }

    func applyingFSEventDirectories(
        _ rawChangedDirs: Set<String>,
        recursiveSubtreeDirs: Set<String> = [],
        latestEventId: UInt64? = nil,
        maxNodes: Int = 700_000,
        excludedPaths: Set<String> = [],
        updatedBuiltAt: Date? = nil,
        resetEventId: Bool = false
    ) -> EverythingIndex {
        let targetBuiltAt = updatedBuiltAt ?? builtAt
        let candidateEventId = latestEventId ?? lastEventId
        let resolvedNextEventId = resetEventId ? candidateEventId : max(lastEventId, candidateEventId)
        guard (!rawChangedDirs.isEmpty || !recursiveSubtreeDirs.isEmpty), !rootPaths.isEmpty else {
            return EverythingIndex(
                rootURLs: rootURLs, nodes: nodes, builtAt: targetBuiltAt,
                reachedNodeLimit: reachedNodeLimit, lastEventId: resolvedNextEventId
            )
        }
        let normalizedExclusions = Self.normalizedExcludedSet(excludedPaths)
        let resolvedRoots = rootPaths.map { EverythingFSEventWatcher.canonicalKernelPath($0) }

        func mapToRootSpace(_ inputPaths: Set<String>, expandAncestorsToRoots: Bool) -> Set<String> {
            var mappedSet = Set<String>()
            for raw in inputPaths {
                let std = URL(fileURLWithPath: raw).standardizedFileURL.path
                if !normalizedExclusions.isEmpty && Self.isPathExcluded(std, excludedPaths: normalizedExclusions) { continue }
                let res = EverythingFSEventWatcher.canonicalKernelPath(raw)
                for (idx, rootPath) in rootPaths.enumerated() {
                    let resRoot = resolvedRoots[idx]
                    if expandAncestorsToRoots && (std == "/" || rootPath.hasPrefix(std + "/") || res == "/" || resRoot.hasPrefix(res + "/")) {
                        mappedSet.insert(rootPath)
                        continue
                    }
                    if (std == rootPath || std.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")),
                       !DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(std, relativeTo: rootPath) {
                        mappedSet.insert(std)
                    }
                    if res == resRoot || res.hasPrefix(resRoot == "/" ? "/" : resRoot + "/") {
                        let mapped = resRoot == rootPath ? res : rootPath + String(res.dropFirst(resRoot.count))
                        if (normalizedExclusions.isEmpty || !Self.isPathExcluded(mapped, excludedPaths: normalizedExclusions)),
                           !DirectoryEntryEnumerator.shouldIgnoreDirectoryPath(mapped, relativeTo: rootPath) {
                            mappedSet.insert(mapped)
                        }
                    }
                }
            }
            return mappedSet
        }

        let recursiveSet = mapToRootSpace(recursiveSubtreeDirs, expandAncestorsToRoots: true)
        var changedSet = mapToRootSpace(rawChangedDirs, expandAncestorsToRoots: false)
        changedSet.formUnion(recursiveSet)
        guard !changedSet.isEmpty else {
            return EverythingIndex(
                rootURLs: rootURLs, nodes: nodes, builtAt: targetBuiltAt,
                reachedNodeLimit: reachedNodeLimit, lastEventId: resolvedNextEventId
            )
        }

        var oldPaths = Array(repeating: "", count: nodes.count)
        var oldChildren = Array(repeating: [Int](), count: nodes.count)
        var oldRootChildren = Array(repeating: [Int](), count: rootPaths.count)
        var oldDirIDByPath: [String: Int] = [:]
        oldDirIDByPath.reserveCapacity(min(nodes.count / 6 + 16, 65_536))
        for idx in 0..<nodes.count {
            let node = nodes[idx]
            let parentID = Int(node.parentID); let rootIdx = Int(node.rootIndex)
            let parentPath = parentID >= 0 && parentID < idx ? oldPaths[parentID] : rootPaths[rootIdx]
            let fullPath = parentPath == "/" ? "/\(node.name)" : "\(parentPath)/\(node.name)"
            oldPaths[idx] = fullPath
            if parentID >= 0 && parentID < idx { oldChildren[parentID].append(idx) }
            else if rootIdx < oldRootChildren.count { oldRootChildren[rootIdx].append(idx) }
            if node.isDirectory { oldDirIDByPath[fullPath] = idx }
        }

        let rootSet = Set(rootPaths)
        var missingAncestors = Set<String>()
        var dirtyAncestors = Set<String>()
        for dir in changedSet {
            var cursor = dir
            var missing = oldDirIDByPath[cursor] == nil
            while !rootSet.contains(cursor) {
                let parent = (cursor as NSString).deletingLastPathComponent
                if parent.isEmpty || parent == cursor { break }
                dirtyAncestors.insert(parent)
                if missing {
                    missingAncestors.insert(parent)
                    if oldDirIDByPath[parent] != nil { missing = false }
                }
                cursor = parent
            }
        }
        if !missingAncestors.isEmpty {
            changedSet.formUnion(mapToRootSpace(missingAncestors, expandAncestorsToRoots: false))
        }

        func isUnderRecursiveSubtree(_ path: String) -> Bool {
            guard !recursiveSet.isEmpty else { return false }
            if recursiveSet.contains(path) { return true }
            for rec in recursiveSet where path.hasPrefix(rec == "/" ? "/" : rec + "/") { return true }
            return false
        }

        let effectiveMaxNodes = max(maxNodes, nodes.count)
        struct QueueItem { let path: String; let parentNewID: Int32; let oldDirID: Int?; let prioritized: Bool }
        var newNodes: [IndexedNode] = []
        newNodes.reserveCapacity(min(effectiveMaxNodes, max(nodes.count, 1024)))
        var priorityQueues: [[QueueItem]] = Array(repeating: [], count: rootPaths.count)
        var standardQueues: [[QueueItem]] = rootPaths.map { [QueueItem(path: $0, parentNewID: -1, oldDirID: nil, prioritized: false)] }
        var priorityHeads = Array(repeating: 0, count: rootPaths.count)
        var standardHeads = Array(repeating: 0, count: rootPaths.count)
        let bulkScratch = UnsafeMutableRawBufferPointer.allocate(byteCount: DirectoryEntryEnumerator.defaultBufferBytes, alignment: 8)
        defer { bulkScratch.deallocate() }
        var visitedChanged = Set<String>()
        var reachedLimit = false; var active = true

        while active && !reachedLimit {
            active = false
            for rootIdx in 0..<rootPaths.count {
                let item: QueueItem
                if priorityHeads[rootIdx] < priorityQueues[rootIdx].count {
                    item = priorityQueues[rootIdx][priorityHeads[rootIdx]]; priorityHeads[rootIdx] += 1
                } else if standardHeads[rootIdx] < standardQueues[rootIdx].count {
                    item = standardQueues[rootIdx][standardHeads[rootIdx]]; standardHeads[rootIdx] += 1
                } else { continue }
                active = true
                if !normalizedExclusions.isEmpty && Self.isPathExcluded(item.path, excludedPaths: normalizedExclusions) { continue }

                let isRoot = item.parentNewID == -1
                let forceSubtree = isUnderRecursiveSubtree(item.path)
                let isChanged = changedSet.contains(item.path)
                if isChanged { visitedChanged.insert(item.path) }
                let shouldScan = forceSubtree || isChanged || (!isRoot && item.oldDirID == nil)

                if shouldScan {
                    let children = DirectoryEntryEnumerator.enumerate(
                        at: item.path, includeHidden: false, excludedPaths: normalizedExclusions, scratchBuffer: bulkScratch
                    )
                    for child in children {
                        if newNodes.count >= effectiveMaxNodes { reachedLimit = true; break }
                        let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(parentID: item.parentNewID, rootIndex: UInt16(rootIdx), isDirectory: child.isDirectory, name: child.name))
                        if child.isDirectory {
                            let childPath = item.path == "/" ? "/\(child.name)" : "\(item.path)/\(child.name)"
                            let matchingOld = forceSubtree ? nil : (isChanged ? oldDirIDByPath[childPath] : nil)
                            let isPrio = item.prioritized || (isRoot && Self.highPriorityUserFolders.contains(child.name))
                                || changedSet.contains(childPath) || dirtyAncestors.contains(childPath)
                            let next = QueueItem(path: childPath, parentNewID: newID, oldDirID: matchingOld, prioritized: isPrio)
                            if isPrio { priorityQueues[rootIdx].append(next) } else { standardQueues[rootIdx].append(next) }
                        }
                    }
                } else {
                    let existing = isRoot ? oldRootChildren[rootIdx] : (item.oldDirID.map { oldChildren[$0] } ?? [])
                    for oldIdx in existing {
                        if newNodes.count >= effectiveMaxNodes { reachedLimit = true; break }
                        let childPath = oldPaths[oldIdx]
                        if !normalizedExclusions.isEmpty && Self.isPathExcluded(childPath, excludedPaths: normalizedExclusions) { continue }
                        let old = nodes[oldIdx]; let newID = Int32(newNodes.count)
                        newNodes.append(IndexedNode(parentID: item.parentNewID, rootIndex: UInt16(rootIdx), isDirectory: old.isDirectory, name: old.name))
                        if old.isDirectory {
                            let isPrio = item.prioritized || (isRoot && Self.highPriorityUserFolders.contains(old.name))
                                || changedSet.contains(childPath) || dirtyAncestors.contains(childPath)
                            let next = QueueItem(path: childPath, parentNewID: newID, oldDirID: oldIdx, prioritized: isPrio)
                            if isPrio { priorityQueues[rootIdx].append(next) } else { standardQueues[rootIdx].append(next) }
                        }
                    }
                }
                if reachedLimit { break }
            }
        }
        let missedDirty = reachedLimit && visitedChanged.count < changedSet.count
        let finalEventId = missedDirty ? lastEventId : resolvedNextEventId
        return EverythingIndex(
            rootURLs: rootURLs, nodes: newNodes, builtAt: missedDirty ? builtAt : targetBuiltAt,
            reachedNodeLimit: reachedLimit, lastEventId: finalEventId
        )
    }
}
