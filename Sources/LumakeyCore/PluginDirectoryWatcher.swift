import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import CoreServices
import Foundation

public struct PluginWatchChangeSet: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bundle = PluginWatchChangeSet(rawValue: 1 << 0)
    public static let searchIndex = PluginWatchChangeSet(rawValue: 1 << 1)
    public static let all: PluginWatchChangeSet = [.bundle, .searchIndex]
}

public final class PluginDirectoryWatcher: @unchecked Sendable {
    private final class DebounceBox {
        let queue: DispatchQueue
        let debounceInterval: TimeInterval
        let dataRootPath: String
        let onChange: @Sendable (PluginWatchChangeSet) -> Void
        var pendingChanges: PluginWatchChangeSet = []
        var workItem: DispatchWorkItem?

        init(
            queue: DispatchQueue,
            debounceInterval: TimeInterval,
            dataRootPath: String,
            onChange: @escaping @Sendable (PluginWatchChangeSet) -> Void
        ) {
            self.queue = queue
            self.debounceInterval = debounceInterval
            self.dataRootPath = dataRootPath
            self.onChange = onChange
        }

        func schedule(paths: [String]) {
            var batch: PluginWatchChangeSet = []
            for path in paths {
                let name = URL(fileURLWithPath: path).lastPathComponent
                if name == ".DS_Store" { continue }
                if name == PluginSearchIndex.defaultIndexFileName {
                    batch.insert(.searchIndex)
                } else if path.hasPrefix(dataRootPath + "/") {
                    continue
                } else {
                    batch.insert(.bundle)
                }
            }
            guard !batch.isEmpty else { return }
            pendingChanges.formUnion(batch)
            workItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let captured = self.pendingChanges
                self.pendingChanges = []
                self.workItem = nil
                guard !captured.isEmpty else { return }
                self.onChange(captured)
            }
            workItem = item
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.queensu.lumakey.plugin-watcher", qos: .utility)
    private let box: DebounceBox
    private var stopped = false

    public var isWatching: Bool {
        queue.sync { !stopped && stream != nil }
    }

    public convenience init?(
        directoryURL: URL = PluginSystem.defaultPluginsDirectory(),
        debounceInterval: TimeInterval = 0.35,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.init(directoryURL: directoryURL, debounceInterval: debounceInterval) { _ in onChange() }
    }

    public init?(
        directoryURL: URL = PluginSystem.defaultPluginsDirectory(),
        debounceInterval: TimeInterval = 0.35,
        onScopedChange: @escaping @Sendable (PluginWatchChangeSet) -> Void
    ) {
        let dataRoot = PluginDataPaths.dataRoot(forPluginsRoot: directoryURL)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)

        let resolvedPlugins = directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedData = dataRoot.resolvingSymlinksInPath().standardizedFileURL.path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPlugins, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        let box = DebounceBox(
            queue: queue,
            debounceInterval: debounceInterval,
            dataRootPath: resolvedData,
            onChange: onScopedChange
        )
        self.box = box

        let retained = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: retained, retain: nil,
            release: { ptr in if let ptr { Unmanaged<DebounceBox>.fromOpaque(ptr).release() } },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let raw = unsafeBitCast(eventPaths, to: NSArray.self)
            var collected: [String] = []
            collected.reserveCapacity(numEvents)
            for idx in 0..<numEvents {
                if let p = raw[idx] as? String { collected.append(p) }
            }
            Unmanaged<DebounceBox>.fromOpaque(info).takeUnretainedValue().schedule(paths: collected)
        }
        let watchPaths = resolvedPlugins == resolvedData ? [resolvedPlugins] : [resolvedPlugins, resolvedData]
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags
        ) else {
            Unmanaged<DebounceBox>.fromOpaque(retained).release()
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
            box.workItem?.cancel()
            box.workItem = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        if !stopped, let stream {
            box.workItem?.cancel()
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
