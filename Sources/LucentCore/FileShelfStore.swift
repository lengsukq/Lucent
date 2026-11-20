import Darwin
import Foundation
import LucentFoundation

public struct FileShelfItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let path: String
    public let bookmark: Data
    public let identity: ShelfFileIdentity

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var parent: String { URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent }
}

public struct ShelfFileIdentity: Codable, Equatable, Sendable {
    let volume: String?
    let fileNumber: UInt64?
    let createdAt: Date?

    init(_ url: URL) throws {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .fileIdentifierKey, .creationDateKey]
        let values = try url.resourceValues(forKeys: keys)
        volume = values.volumeUUIDString
        fileNumber = (values.allValues[.fileIdentifierKey] as? NSNumber)?.uint64Value
        createdAt = values.creationDate
    }

    public func matches(_ other: Self) -> Bool {
        guard let volume, let fileNumber else { return false }
        return volume == other.volume && fileNumber == other.fileNumber && createdAt == other.createdAt
    }
}

public enum FileShelfAvailability: Equatable, Sendable {
    case available(URL), volumeOffline, missing, noAccess, needsRelink

    public var url: URL? {
        if case let .available(url) = self { return url }
        return nil
    }
}

public struct FileShelfStore: Sendable {
    private struct Document: Codable {
        var version = 1
        let items: [FileShelfItem]
    }

    public static let directoryName = "FileShelves"
    public let location: URL

    public init(location: URL) {
        self.location = location
    }

    public static func local(pluginID: String) -> Self? {
        guard PluginSystem.isSafePluginID(pluginID) else { return nil }
        return Self(location: LucentAppPaths.defaultAppSupportDirectory()
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("\(pluginID).json"))
    }

    public func load() throws -> [FileShelfItem] {
        let data: Data
        do {
            data = try Data(contentsOf: location)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return document.items
    }

    public func save(_ items: [FileShelfItem]) throws {
        let directory = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try AtomicJSONStore.writeThrowing(Document(items: items), to: location)
    }

    public static func makeItem(_ url: URL, id: UUID = UUID()) throws -> FileShelfItem {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let source = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isReadableKey])
        guard (values.isRegularFile == true || values.isDirectory == true), values.isReadable == true else {
            throw CocoaError(.fileReadNoPermission)
        }
        return FileShelfItem(id: id, path: source.path,
                             bookmark: try source.bookmarkData(options: [.minimalBookmark]),
                             identity: try ShelfFileIdentity(source))
    }

    public static func updatedReference(_ item: FileShelfItem, to url: URL) -> FileShelfItem? {
        guard url.path != item.path, let next = try? makeItem(url, id: item.id),
              item.identity.matches(next.identity) else { return nil }
        return next
    }

    public static func resolve(_ item: FileShelfItem, mountedVolumes: Set<String>) -> FileShelfAvailability {
        let last = URL(fileURLWithPath: item.path)
        var isStale = false
        let bookmarked = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &isStale).standardizedFileURL
        if let bookmarked, let outcome = availability(of: bookmarked, for: item, nonStaleBookmark: !isStale) {
            return outcome
        }
        // A bookmark can return a stale path now occupied by an unrelated file. Recover by inode
        // on the already-mounted original volume, then check the full saved identity again.
        if let moved = pathByFileNumber(for: item, startingAt: last),
           let outcome = availability(of: moved, for: item, nonStaleBookmark: false) {
            return outcome
        }
        if let outcome = availability(of: last, for: item, nonStaleBookmark: false) { return outcome }
        if let volume = item.identity.volume, !mountedVolumes.isEmpty, !mountedVolumes.contains(volume) {
            return .volumeOffline
        }
        if FileManager.default.fileExists(atPath: last.path) { return .needsRelink }
        return .missing
    }

    private static func availability(of url: URL, for item: FileShelfItem,
                                     nonStaleBookmark: Bool) -> FileShelfAvailability? {
        do {
            let identity = try ShelfFileIdentity(url)
            let bookmarkVerified = nonStaleBookmark && identity.volume == item.identity.volume
                && item.identity.fileNumber == nil && identity.createdAt != nil && identity.createdAt == item.identity.createdAt
            guard item.identity.matches(identity) || bookmarkVerified else { return nil }
            guard !url.pathComponents.contains(".Trash"), !url.pathComponents.contains(".Trashes") else { return .missing }
            return FileManager.default.isReadableFile(atPath: url.path) ? .available(url) : .noAccess
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .noAccess
        } catch {
            return nil
        }
    }

    private static func pathByFileNumber(for item: FileShelfItem, startingAt last: URL) -> URL? {
        guard let number = item.identity.fileNumber, let volume = item.identity.volume else { return nil }
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey]
        var ancestor = last.deletingLastPathComponent()
        while ancestor.path != "/" && !FileManager.default.fileExists(atPath: ancestor.path) {
            ancestor.deleteLastPathComponent()
        }
        let mount: URL?
        if (try? ancestor.resourceValues(forKeys: keys).volumeUUIDString) == volume {
            mount = ancestor
        } else {
            mount = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [])?
                .first { (try? $0.resourceValues(forKeys: keys).volumeUUIDString) == volume }
        }
        guard let mount else { return nil }
        var filesystem = statfs()
        guard statfs(mount.path, &filesystem) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fsgetpath(&buffer, buffer.count, &filesystem.f_fsid, number) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static func mountedVolumeIDs() -> Set<String> {
        let keys: [URLResourceKey] = [.volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        return Set(urls.compactMap { try? $0.resourceValues(forKeys: Set(keys)).volumeUUIDString })
    }
}
