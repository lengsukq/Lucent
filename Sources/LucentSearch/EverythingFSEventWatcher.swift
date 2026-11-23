import CoreServices
import Foundation
import LucentFoundation

public struct EverythingFSEventBatch: Sendable, Equatable {
    public let directories: Set<String>
    public let recursiveDirectories: Set<String>
    public let latestEventId: UInt64
    public let isHistoricalReplay: Bool

    public init(
        directories: Set<String>,
        recursiveDirectories: Set<String> = [],
        latestEventId: UInt64 = 0,
        isHistoricalReplay: Bool = false
    ) {
        self.directories = directories
        self.recursiveDirectories = recursiveDirectories
        self.latestEventId = latestEventId
        self.isHistoricalReplay = isHistoricalReplay
    }
}

public final class EverythingFSEventWatcher: @unchecked Sendable {
    private final class CallbackBox: @unchecked Sendable {
        let queue: DispatchQueue
        let watchPaths: [String]
        let debounceInterval: TimeInterval
        let onBatch: @Sendable (EverythingFSEventBatch) -> Void
        var pendingDirectories: Set<String> = []
        var pendingRecursiveDirectories: Set<String> = []
        var pendingLatestEventId: UInt64 = 0
        var flushWorkItem: DispatchWorkItem?

        init(
            queue: DispatchQueue,
            watchPaths: [String],
            debounceInterval: TimeInterval,
            onBatch: @escaping @Sendable (EverythingFSEventBatch) -> Void
        ) {
            self.queue = queue
            self.watchPaths = watchPaths
            self.debounceInterval = debounceInterval
            self.onBatch = onBatch
        }

        func enqueue(
            dirs: [String],
            recursiveDirs: [String],
            maxEventId: UInt64,
            sawHistoryDone: Bool
        ) {
            if !dirs.isEmpty { pendingDirectories.formUnion(dirs) }
            if !recursiveDirs.isEmpty { pendingRecursiveDirectories.formUnion(recursiveDirs) }
            if maxEventId > pendingLatestEventId { pendingLatestEventId = maxEventId }

            if sawHistoryDone {
                flushWorkItem?.cancel()
                flushWorkItem = nil
                flushNow(isHistoricalReplay: true)
                return
            }

            guard !pendingDirectories.isEmpty || !pendingRecursiveDirectories.isEmpty else { return }
            flushWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.flushNow(isHistoricalReplay: false)
            }
            flushWorkItem = item
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }

        private func flushNow(isHistoricalReplay: Bool) {
            let dirs = pendingDirectories
            let recDirs = pendingRecursiveDirectories
            let recordedId = pendingLatestEventId
            pendingDirectories.removeAll()
            pendingRecursiveDirectories.removeAll()
            pendingLatestEventId = 0
            flushWorkItem = nil

            let resolvedId = max(recordedId, EverythingFSEventWatcher.currentEventId())
            guard isHistoricalReplay || !dirs.isEmpty || !recDirs.isEmpty else { return }
            onBatch(EverythingFSEventBatch(
                directories: dirs,
                recursiveDirectories: recDirs,
                latestEventId: resolvedId,
                isHistoricalReplay: isHistoricalReplay
            ))
        }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: LucentIdentifiers.scoped("fsevents"), qos: .utility)
    private let box: CallbackBox
    private var stopped = false

    public static func currentEventId() -> UInt64 {
        UInt64(FSEventsGetCurrentEventId())
    }

    public convenience init?(
        roots: [URL],
        debounceInterval: TimeInterval = 0.8,
        onChangedDirectories: @escaping @Sendable (Set<String>) -> Void
    ) {
        self.init(
            roots: roots,
            sinceEventId: nil,
            debounceInterval: debounceInterval,
            onEventBatch: { batch in
                guard !batch.directories.isEmpty else { return }
                onChangedDirectories(batch.directories)
            }
        )
    }

    public init?(
        roots: [URL],
        sinceEventId: UInt64? = nil,
        debounceInterval: TimeInterval = 0.25,
        onEventBatch: @escaping @Sendable (EverythingFSEventBatch) -> Void
    ) {
        var seen = Set<String>()
        var watchPaths: [String] = []
        for root in roots {
            let resolved = root.resolvingSymlinksInPath().standardizedFileURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir),
               isDir.boolValue,
               seen.insert(resolved).inserted {
                watchPaths.append(resolved)
            }
        }
        guard !watchPaths.isEmpty else { return nil }

        let box = CallbackBox(
            queue: queue,
            watchPaths: watchPaths,
            debounceInterval: debounceInterval,
            onBatch: onEventBatch
        )
        self.box = box

        let retained = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: retained,
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<CallbackBox>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagFileEvents
        )

        let startSince: FSEventStreamEventId
        if let sinceEventId, sinceEventId > 0, sinceEventId < UInt64(kFSEventStreamEventIdSinceNow) {
            startSince = FSEventStreamEventId(sinceEventId)
        } else {
            startSince = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        }

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, eventIds in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            var dirs: [String] = []
            var recursiveDirs: [String] = []
            dirs.reserveCapacity(numEvents)
            var maxEventId: UInt64 = 0
            var sawHistoryDone = false

            let historyDoneMask = UInt32(kFSEventStreamEventFlagHistoryDone)
            let wrappedMask = UInt32(kFSEventStreamEventFlagEventIdsWrapped)
            let subtreeMask = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged)
            let isFileMask = UInt32(kFSEventStreamEventFlagItemIsFile)
            let isDirMask = UInt32(kFSEventStreamEventFlagItemIsDir)

            for i in 0..<numEvents {
                let flag = eventFlags[i]
                let evId = UInt64(eventIds[i])
                if evId > maxEventId { maxEventId = evId }

                if (flag & historyDoneMask) != 0 {
                    sawHistoryDone = true
                    continue
                }
                if (flag & wrappedMask) != 0 {
                    dirs.append(contentsOf: box.watchPaths)
                    recursiveDirs.append(contentsOf: box.watchPaths)
                    continue
                }
                guard let rawPath = paths[i] as? String else { continue }
                let clean = rawPath.hasSuffix("/") && rawPath.count > 1 ? String(rawPath.dropLast()) : rawPath
                let parent = (clean as NSString).deletingLastPathComponent

                if (flag & subtreeMask) != 0 {
                    if !parent.isEmpty { dirs.append(parent) }
                    dirs.append(clean)
                    recursiveDirs.append(clean)
                } else if (flag & isFileMask) != 0 && (flag & isDirMask) == 0 {
                    dirs.append(parent)
                } else {
                    if !parent.isEmpty { dirs.append(parent) }
                    dirs.append(clean)
                }
            }
            box.enqueue(
                dirs: dirs,
                recursiveDirs: recursiveDirs,
                maxEventId: maxEventId,
                sawHistoryDone: sawHistoryDone
            )
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchPaths as CFArray,
            startSince,
            0.15,
            flags
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(retained).release()
            return nil
        }

        self.stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        queue.sync {
            guard !stopped, let stream else { return }
            stopped = true
            box.flushWorkItem?.cancel()
            box.flushWorkItem = nil
            box.pendingDirectories.removeAll()
            box.pendingRecursiveDirectories.removeAll()
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        if !stopped, let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
