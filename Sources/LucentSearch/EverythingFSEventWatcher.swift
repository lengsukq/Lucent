import CoreServices
import Darwin
import Foundation
import LucentFoundation

public struct EverythingFSEventBatch: Sendable, Equatable {
    public let directories: Set<String>
    public let recursiveDirectories: Set<String>
    public let latestEventId: UInt64
    public let isHistoricalReplay: Bool
    public let eventIdsWrapped: Bool

    public init(
        directories: Set<String>, recursiveDirectories: Set<String> = [],
        latestEventId: UInt64 = 0, isHistoricalReplay: Bool = false, eventIdsWrapped: Bool = false
    ) {
        self.directories = directories; self.recursiveDirectories = recursiveDirectories
        self.latestEventId = latestEventId; self.isHistoricalReplay = isHistoricalReplay
        self.eventIdsWrapped = eventIdsWrapped
    }
}

public final class EverythingFSEventWatcher: @unchecked Sendable {
    private final class CallbackBox: @unchecked Sendable {
        let queue: DispatchQueue
        let watchPaths: [String]
        let debounceInterval: TimeInterval
        let maxWaitInterval: TimeInterval
        let ignoreNonStructuralFileModifications: Bool
        let ignoreHiddenItems: Bool
        let shouldTrackDirectory: (@Sendable (String) -> Bool)?
        let onBatch: @Sendable (EverythingFSEventBatch) -> Void

        var pendingDirectories: Set<String> = []
        var pendingRecursiveDirectories: Set<String> = []
        var pendingLatestEventId: UInt64 = 0
        var pendingWrapped = false
        var firstPendingEventTime: DispatchTime?
        var flushWorkItem: DispatchWorkItem?

        init(
            queue: DispatchQueue, watchPaths: [String], debounceInterval: TimeInterval, maxWaitInterval: TimeInterval,
            ignoreNonStructuralFileModifications: Bool, ignoreHiddenItems: Bool,
            shouldTrackDirectory: (@Sendable (String) -> Bool)?,
            onBatch: @escaping @Sendable (EverythingFSEventBatch) -> Void
        ) {
            self.queue = queue; self.watchPaths = watchPaths
            self.debounceInterval = max(0.05, debounceInterval)
            self.maxWaitInterval = max(self.debounceInterval, maxWaitInterval)
            self.ignoreNonStructuralFileModifications = ignoreNonStructuralFileModifications
            self.ignoreHiddenItems = ignoreHiddenItems
            self.shouldTrackDirectory = shouldTrackDirectory; self.onBatch = onBatch
        }

        func enqueue(dirs: [String], recursiveDirs: [String], maxEventId: UInt64, sawHistoryDone: Bool, sawWrapped: Bool) {
            if !dirs.isEmpty { pendingDirectories.formUnion(dirs) }
            if !recursiveDirs.isEmpty { pendingRecursiveDirectories.formUnion(recursiveDirs) }
            if sawWrapped { pendingWrapped = true; pendingLatestEventId = maxEventId }
            else if maxEventId > pendingLatestEventId { pendingLatestEventId = maxEventId }

            if sawHistoryDone {
                flushWorkItem?.cancel(); flushWorkItem = nil
                flushNow(isHistoricalReplay: true); return
            }
            guard !dirs.isEmpty || !recursiveDirs.isEmpty else { return }
            guard !pendingDirectories.isEmpty || !pendingRecursiveDirectories.isEmpty else { return }

            let now = DispatchTime.now()
            let firstTime = firstPendingEventTime ?? now
            firstPendingEventTime = firstTime
            let elapsed = Double(now.uptimeNanoseconds - firstTime.uptimeNanoseconds) / 1_000_000_000.0
            let remaining = maxWaitInterval - elapsed
            if remaining <= 0.005 {
                flushWorkItem?.cancel(); flushWorkItem = nil
                flushNow(isHistoricalReplay: false); return
            }
            flushWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.flushNow(isHistoricalReplay: false) }
            flushWorkItem = item
            queue.asyncAfter(deadline: .now() + min(debounceInterval, remaining), execute: item)
        }

        func flushPendingImmediately() {
            flushWorkItem?.cancel(); flushWorkItem = nil
            flushNow(isHistoricalReplay: false)
        }

        func flushNow(isHistoricalReplay: Bool) {
            let dirs = pendingDirectories; let recDirs = pendingRecursiveDirectories
            let recordedId = pendingLatestEventId; let wrapped = pendingWrapped
            pendingDirectories.removeAll(); pendingRecursiveDirectories.removeAll()
            pendingLatestEventId = 0; pendingWrapped = false; firstPendingEventTime = nil; flushWorkItem = nil
            guard isHistoricalReplay || wrapped || !dirs.isEmpty || !recDirs.isEmpty else { return }
            onBatch(EverythingFSEventBatch(
                directories: dirs, recursiveDirectories: recDirs,
                latestEventId: recordedId, isHistoricalReplay: isHistoricalReplay, eventIdsWrapped: wrapped
            ))
        }

        func hasHiddenRelativeComponent(_ cleanPath: String) -> Bool {
            for root in watchPaths {
                if cleanPath == root { return false }
                let prefix = root == "/" ? "/" : root + "/"
                guard cleanPath.hasPrefix(prefix) else { continue }
                for seg in cleanPath.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: true) where seg.hasPrefix(".") {
                    return true
                }
                return false
            }
            return (cleanPath as NSString).lastPathComponent.hasPrefix(".")
        }
    }

    private static let queueKey = DispatchSpecificKey<UInt8>()
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue
    private let box: CallbackBox
    private var stopped = false

    public static func currentEventId() -> UInt64 { UInt64(FSEventsGetCurrentEventId()) }

    public static func canonicalKernelPath(_ path: String) -> String {
        guard let ptr = path.withCString({ realpath($0, nil) }) else {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        }
        defer { free(ptr) }
        return String(cString: ptr)
    }

    public convenience init?(
        roots: [URL], debounceInterval: TimeInterval = 0.8,
        onChangedDirectories: @escaping @Sendable (Set<String>) -> Void
    ) {
        self.init(
            roots: roots, sinceEventId: nil, debounceInterval: debounceInterval,
            maxWaitInterval: max(debounceInterval * 2.5, 0.8),
            ignoreNonStructuralFileModifications: true, ignoreHiddenItems: true, shouldTrackDirectory: nil
        ) { batch in guard !batch.directories.isEmpty else { return }; onChangedDirectories(batch.directories) }
    }

    public init?(
        roots: [URL], sinceEventId: UInt64? = nil,
        debounceInterval: TimeInterval = 0.2, maxWaitInterval: TimeInterval = 0.6,
        ignoreNonStructuralFileModifications: Bool = true, ignoreHiddenItems: Bool = true,
        shouldTrackDirectory: (@Sendable (String) -> Bool)? = nil,
        onEventBatch: @escaping @Sendable (EverythingFSEventBatch) -> Void
    ) {
        var seen = Set<String>(); var watchPaths: [String] = []
        for root in roots {
            let resolved = Self.canonicalKernelPath(root.path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue,
               seen.insert(resolved).inserted { watchPaths.append(resolved) }
        }
        guard !watchPaths.isEmpty else { return nil }

        let q = DispatchQueue(label: LucentIdentifiers.scoped("fsevents"), qos: .utility)
        q.setSpecific(key: Self.queueKey, value: 1)
        self.queue = q
        let box = CallbackBox(
            queue: q, watchPaths: watchPaths, debounceInterval: debounceInterval, maxWaitInterval: maxWaitInterval,
            ignoreNonStructuralFileModifications: ignoreNonStructuralFileModifications,
            ignoreHiddenItems: ignoreHiddenItems, shouldTrackDirectory: shouldTrackDirectory, onBatch: onEventBatch
        )
        self.box = box

        let retained = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: retained, retain: nil,
            release: { ptr in guard let ptr else { return }; Unmanaged<CallbackBox>.fromOpaque(ptr).release() },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
        )
        let nowId = Self.currentEventId()
        let startSince: FSEventStreamEventId = if let sinceEventId, sinceEventId > 0, nowId > 0,
            sinceEventId <= nowId, sinceEventId < UInt64(kFSEventStreamEventIdSinceNow) {
            FSEventStreamEventId(sinceEventId)
        } else { FSEventStreamEventId(kFSEventStreamEventIdSinceNow) }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, Self.streamCallback, &context, watchPaths as CFArray, startSince, 0.08, flags
        ) else { Unmanaged<CallbackBox>.fromOpaque(retained).release(); return nil }
        FSEventStreamSetDispatchQueue(created, q)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created); FSEventStreamRelease(created); return nil
        }
        self.stream = created
    }

    private static let streamCallback: FSEventStreamCallback = { streamRef, info, numEvents, eventPaths, eventFlags, eventIds in
        guard let info else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        var dirs: [String] = []; var recursiveDirs: [String] = []
        dirs.reserveCapacity(min(numEvents, 256))
        let streamLatest = UInt64(FSEventStreamGetLatestEventId(streamRef))
        var maxEventId: UInt64 = streamLatest < UInt64(kFSEventStreamEventIdSinceNow) ? streamLatest : 0
        var sawHistoryDone = false; var sawWrapped = false

        let historyDoneMask = UInt32(kFSEventStreamEventFlagHistoryDone)
        let wrappedMask = UInt32(kFSEventStreamEventFlagEventIdsWrapped)
        let subtreeMask = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount
        )
        let isFileMask = UInt32(kFSEventStreamEventFlagItemIsFile)
        let isDirMask = UInt32(kFSEventStreamEventFlagItemIsDir)
        let isSymlinkMask = UInt32(kFSEventStreamEventFlagItemIsSymlink)
        let dirSubtreeChangeMask = UInt32(kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemCreated)
        let structuralMask = subtreeMask | UInt32(
            kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
            | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagEventIdsWrapped
        )
        let nonStructuralMask = UInt32(
            kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod
            | kFSEventStreamEventFlagItemXattrMod | kFSEventStreamEventFlagItemFinderInfoMod
            | kFSEventStreamEventFlagItemChangeOwner
        )

        func appendIfTracked(_ path: String, recursive: Bool = false) {
            guard !path.isEmpty else { return }
            if let filter = box.shouldTrackDirectory, !filter(path) { return }
            dirs.append(path)
            if recursive { recursiveDirs.append(path) }
        }

        for i in 0..<numEvents {
            let flag = eventFlags[i]; let evId = UInt64(eventIds[i])
            if evId < UInt64(kFSEventStreamEventIdSinceNow), evId > maxEventId { maxEventId = evId }
            if (flag & historyDoneMask) != 0 { sawHistoryDone = true; continue }
            if (flag & wrappedMask) != 0 {
                sawWrapped = true; for wp in box.watchPaths { appendIfTracked(wp, recursive: true) }; continue
            }
            let isLeaf = ((flag & isFileMask) != 0 || (flag & isSymlinkMask) != 0) && (flag & isDirMask) == 0
            if box.ignoreNonStructuralFileModifications && isLeaf
                && (flag & structuralMask) == 0 && (flag & nonStructuralMask) != 0 { continue }

            guard let rawPath = paths[i] as? String else { continue }
            let clean = rawPath.hasSuffix("/") && rawPath.count > 1 ? String(rawPath.dropLast()) : rawPath
            if (flag & subtreeMask) != 0 {
                let covered = box.watchPaths.filter { clean == "/" || $0 == clean || $0.hasPrefix(clean + "/") }
                if !covered.isEmpty { for wp in covered { appendIfTracked(wp, recursive: true) } }
                else { appendIfTracked((clean as NSString).deletingLastPathComponent); appendIfTracked(clean, recursive: true) }
                continue
            }
            if box.ignoreHiddenItems && box.hasHiddenRelativeComponent(clean) { continue }
            let parent = (clean as NSString).deletingLastPathComponent
            appendIfTracked(parent)
            if !isLeaf {
                appendIfTracked(clean, recursive: (flag & isDirMask) != 0 && (flag & dirSubtreeChangeMask) != 0)
            }
        }
        box.enqueue(dirs: dirs, recursiveDirs: recursiveDirs, maxEventId: maxEventId, sawHistoryDone: sawHistoryDone, sawWrapped: sawWrapped)
    }

    public func flushAsync() {
        queue.async { [weak self] in
            guard let self, !self.stopped, let stream = self.stream else { return }
            self.box.flushPendingImmediately()
            FSEventStreamFlushAsync(stream)
        }
    }

    public func stop() {
        let teardown = {
            guard !self.stopped, let stream = self.stream else { return }
            self.stopped = true
            self.box.flushWorkItem?.cancel(); self.box.flushWorkItem = nil
            self.box.firstPendingEventTime = nil; self.box.pendingWrapped = false
            self.box.pendingDirectories.removeAll(); self.box.pendingRecursiveDirectories.removeAll()
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
            self.stream = nil
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { teardown() } else { queue.sync(execute: teardown) }
    }

    deinit {
        guard !stopped, let stream else { return }
        let box = self.box; let streamBits = UInt(bitPattern: stream)
        queue.async {
            box.flushWorkItem?.cancel(); box.flushWorkItem = nil
            box.pendingDirectories.removeAll(); box.pendingRecursiveDirectories.removeAll()
            if let ptr = UnsafeMutableRawPointer(bitPattern: streamBits) {
                let ref = FSEventStreamRef(ptr)
                FSEventStreamStop(ref); FSEventStreamInvalidate(ref); FSEventStreamRelease(ref)
            }
        }
    }
}
