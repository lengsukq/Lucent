import LucentFoundation
import Darwin
import Foundation

public struct IndexedNode: Sendable, Hashable {
    public let parentID: Int32
    public let rootIndex: UInt16
    public let isDirectory: Bool
    public let name: String

    public init(parentID: Int32, rootIndex: UInt16, isDirectory: Bool, name: String) {
        self.parentID = parentID
        self.rootIndex = rootIndex
        self.isDirectory = isDirectory
        self.name = name
    }
}

public struct EverythingSearchHit: Identifiable, Sendable, Hashable {
    public let id: Int
    public let url: URL
    public let relativeParentPath: String
    public let name: String
    public let isDirectory: Bool
    public let sizeBytes: Int64
    public let modifiedAt: Date
    public let mediaKind: PreviewMediaKind

    public var formattedSize: String {
        if isDirectory || sizeBytes < 0 { return "—" }
        return FastFormatters.formatFileBytes(sizeBytes)
    }
}

public struct EverythingIndex: Sendable {
    public let rootURLs: [URL]
    public let rootPaths: [String]
    public var rootURL: URL { rootURLs.first ?? URL(fileURLWithPath: "/") }
    public let nodes: [IndexedNode]
    public let builtAt: Date
    public let reachedNodeLimit: Bool
    public let lastEventId: UInt64

    public init(
        rootURLs: [URL],
        nodes: [IndexedNode],
        builtAt: Date,
        reachedNodeLimit: Bool,
        lastEventId: UInt64 = 0
    ) {
        self.rootURLs = rootURLs
        self.rootPaths = rootURLs.map { $0.standardizedFileURL.path }
        self.nodes = nodes
        self.builtAt = builtAt
        self.reachedNodeLimit = reachedNodeLimit
        self.lastEventId = lastEventId
    }

    public func withUpdatedEventId(_ eventId: UInt64) -> EverythingIndex {
        guard eventId > lastEventId else { return self }
        return EverythingIndex(
            rootURLs: rootURLs,
            nodes: nodes,
            builtAt: builtAt,
            reachedNodeLimit: reachedNodeLimit,
            lastEventId: eventId
        )
    }

    private static let packageSuffixBytes: [[UInt8]] = [
        ".app", ".framework", ".bundle", ".xcodeproj", ".xcworkspace", ".playground", ".photoslibrary"
    ].map { Array($0.utf8) }

    private static let highPriorityUserFolders: Set<String> = [
        "Desktop", "Downloads", "Pictures", "Movies", "Music"
    ]

    public static func normalizedExcludedSet(_ raw: Set<String>) -> Set<String> {
        var out = Set<String>()
        for path in raw {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let std = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            if !std.isEmpty && std != "/" { out.insert(std) }
        }
        return out
    }

    public static func isPathExcluded(_ standardizedPath: String, excludedPaths: Set<String>) -> Bool {
        guard !excludedPaths.isEmpty else { return false }
        if excludedPaths.contains(standardizedPath) { return true }
        for excluded in excludedPaths where standardizedPath.hasPrefix(excluded + "/") {
            return true
        }
        return false
    }

    public static func build(
        rootURL: URL,
        maxNodes: Int = 80_000,
        includeHidden: Bool = false,
        excludedPaths: Set<String> = []
    ) throws -> EverythingIndex {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LucentError.directoryNotFound(rootURL)
        }
        return try build(rootURLs: [rootURL], maxNodes: maxNodes, includeHidden: includeHidden, excludedPaths: excludedPaths)
    }

    public static func build(
        rootURLs: [URL],
        maxNodes: Int = 400_000,
        includeHidden: Bool = false,
        excludedPaths: Set<String> = []
    ) throws -> EverythingIndex {
        let baselineEventId = EverythingFSEventWatcher.currentEventId()
        let normalizedExclusions = normalizedExcludedSet(excludedPaths)
        var seenPaths = Set<String>()
        let validRoots: [URL] = rootURLs.filter { url in
            let std = url.standardizedFileURL.path
            guard !isPathExcluded(std, excludedPaths: normalizedExclusions) else { return false }
            guard seenPaths.insert(std).inserted else { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: std, isDirectory: &isDir) && isDir.boolValue
        }
        guard !validRoots.isEmpty else {
            return EverythingIndex(
                rootURLs: [], nodes: [], builtAt: Date(), reachedNodeLimit: false, lastEventId: baselineEventId
            )
        }

        struct FrontierItem {
            let path: String
            let parentID: Int32
            let prioritized: Bool
        }

        var nodes: [IndexedNode] = []
        nodes.reserveCapacity(min(maxNodes, 8192))
        var priorityQueues: [[FrontierItem]] = Array(repeating: [], count: validRoots.count)
        var standardQueues: [[FrontierItem]] = validRoots.map {
            [FrontierItem(path: $0.standardizedFileURL.path, parentID: -1, prioritized: false)]
        }
        var priorityHeads = Array(repeating: 0, count: validRoots.count)
        var standardHeads = Array(repeating: 0, count: validRoots.count)
        let bulkScratch = UnsafeMutableRawBufferPointer.allocate(byteCount: DirectoryEntryEnumerator.defaultBufferBytes, alignment: 8)
        defer { bulkScratch.deallocate() }
        var reachedLimit = false
        var active = true

        while active && !reachedLimit {
            active = false
            for rootIdx in 0..<validRoots.count {
                try Task.checkCancellation()
                let current: FrontierItem
                if priorityHeads[rootIdx] < priorityQueues[rootIdx].count {
                    current = priorityQueues[rootIdx][priorityHeads[rootIdx]]
                    priorityHeads[rootIdx] += 1
                } else if standardHeads[rootIdx] < standardQueues[rootIdx].count {
                    current = standardQueues[rootIdx][standardHeads[rootIdx]]
                    standardHeads[rootIdx] += 1
                } else {
                    continue
                }
                active = true

                let children = DirectoryEntryEnumerator.enumerate(
                    at: current.path,
                    includeHidden: includeHidden,
                    excludedPaths: normalizedExclusions,
                    scratchBuffer: bulkScratch
                )
                for child in children {
                    if nodes.count >= maxNodes {
                        reachedLimit = true
                        break
                    }
                    let nodeID = Int32(nodes.count)
                    nodes.append(IndexedNode(
                        parentID: current.parentID,
                        rootIndex: UInt16(rootIdx),
                        isDirectory: child.isDirectory,
                        name: child.name
                    ))
                    if child.isDirectory {
                        let childPath = current.path == "/" ? "/\(child.name)" : "\(current.path)/\(child.name)"
                        let isPrio = current.prioritized
                            || (current.parentID == -1 && highPriorityUserFolders.contains(child.name))
                        let nextItem = FrontierItem(path: childPath, parentID: nodeID, prioritized: isPrio)
                        if isPrio {
                            priorityQueues[rootIdx].append(nextItem)
                        } else {
                            standardQueues[rootIdx].append(nextItem)
                        }
                    }
                }
                if reachedLimit { break }
            }
        }

        return EverythingIndex(
            rootURLs: validRoots,
            nodes: nodes,
            builtAt: Date(),
            reachedNodeLimit: reachedLimit,
            lastEventId: baselineEventId
        )
    }

    public func merging(_ other: EverythingIndex) -> EverythingIndex {
        guard !other.nodes.isEmpty else { return self }
        let rootOffset = UInt16(rootURLs.count)
        let nodeOffset = Int32(nodes.count)
        var combinedNodes = nodes
        combinedNodes.reserveCapacity(nodes.count + other.nodes.count)
        for node in other.nodes {
            combinedNodes.append(IndexedNode(
                parentID: node.parentID >= 0 ? node.parentID + nodeOffset : -1,
                rootIndex: node.rootIndex + rootOffset,
                isDirectory: node.isDirectory,
                name: node.name
            ))
        }
        let mergedEventId = (lastEventId > 0 && other.lastEventId > 0)
            ? min(lastEventId, other.lastEventId)
            : max(lastEventId, other.lastEventId)
        return EverythingIndex(
            rootURLs: rootURLs + other.rootURLs,
            nodes: combinedNodes,
            builtAt: Date(),
            reachedNodeLimit: reachedNodeLimit || other.reachedNodeLimit,
            lastEventId: mergedEventId
        )
    }

    public static func hasPackageSuffix(_ name: String) -> Bool {
        guard name.utf8.count >= 4 else { return false }
        var copy = name
        return copy.withUTF8 { utf8 in
            for suffix in packageSuffixBytes where utf8.count >= suffix.count {
                let start = utf8.count - suffix.count
                var matched = true
                for i in 0..<suffix.count {
                    let b = utf8[start &+ i]
                    let folded = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
                    if folded != suffix[i] { matched = false; break }
                }
                if matched { return true }
            }
            return false
        }
    }

    public static func extractExtensionLower(fromName name: String) -> String {
        var copy = name
        return copy.withUTF8 { utf8 in
            guard utf8.count >= 2 else { return "" }
            var dotPos = -1
            var idx = utf8.count - 1
            while idx > 0 {
                if utf8[idx] == 0x2E { dotPos = idx; break }
                idx &-= 1
            }
            guard dotPos > 0, dotPos + 1 < utf8.count else { return "" }
            let extStart = dotPos + 1
            let extCount = utf8.count - extStart
            return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: extCount) { tmp in
                for i in 0..<extCount {
                    let b = utf8[extStart &+ i]
                    if b >= 0x80 {
                        let slice = UnsafeBufferPointer(rebasing: utf8[extStart...])
                        return String(decoding: slice, as: UTF8.self).lowercased()
                    }
                    tmp[i] = (b >= 0x41 && b <= 0x5A) ? (b &+ 32) : b
                }
                return String(decoding: UnsafeBufferPointer(tmp), as: UTF8.self)
            }
        }
    }

    public static func extractExtensionLower(_ lowerName: String) -> String {
        extractExtensionLower(fromName: lowerName)
    }
}
