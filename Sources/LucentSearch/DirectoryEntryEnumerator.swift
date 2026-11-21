import Darwin
import Foundation

public struct DirectoryChildEntry: Sendable, Hashable {
    public let name: String
    public let isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// High-throughput directory enumerator using macOS `getattrlistbulk` with automatic
/// fallback to POSIX `opendir`/`readdir` on filesystems that do not support bulk attributes.
public enum DirectoryEntryEnumerator {
    public static let defaultBufferBytes: Int = 32 * 1024

    public static let defaultSkippedFolders: Set<String> = [
        "Library", "node_modules", ".git", ".build", "DerivedData", "Caches",
        ".Spotlight-V100", ".Trashes", "$RECYCLE.BIN", "System Volume Information",
        ".fseventsd", ".TemporaryItems", ".venv", "venv", "__pycache__", "Pods",
        ".gradle", ".cargo", ".rustup", ".npm"
    ]

    public static func enumerate(
        at path: String,
        includeHidden: Bool = false,
        excludedPaths: Set<String> = [],
        skippedFolders: Set<String> = defaultSkippedFolders,
        scratchBuffer: UnsafeMutableRawBufferPointer? = nil
    ) -> [DirectoryChildEntry] {
        if let bulk = enumerateViaGetAttrListBulk(
            at: path,
            includeHidden: includeHidden,
            excludedPaths: excludedPaths,
            skippedFolders: skippedFolders,
            scratchBuffer: scratchBuffer
        ) {
            return bulk
        }
        return enumerateViaReaddir(
            at: path,
            includeHidden: includeHidden,
            excludedPaths: excludedPaths,
            skippedFolders: skippedFolders
        )
    }

    static func enumerateViaGetAttrListBulk(
        at path: String,
        includeHidden: Bool,
        excludedPaths: Set<String>,
        skippedFolders: Set<String>,
        scratchBuffer: UnsafeMutableRawBufferPointer?
    ) -> [DirectoryChildEntry]? {
        let fd = path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC) }
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let ownedBuffer: UnsafeMutableRawBufferPointer?
        let buf: UnsafeMutableRawBufferPointer
        if let scratchBuffer, scratchBuffer.count >= 4096, scratchBuffer.baseAddress != nil {
            ownedBuffer = nil
            buf = scratchBuffer
        } else {
            let allocated = UnsafeMutableRawBufferPointer.allocate(byteCount: defaultBufferBytes, alignment: 8)
            ownedBuffer = allocated
            buf = allocated
        }
        defer { ownedBuffer?.deallocate() }
        guard let baseAddr = buf.baseAddress else { return nil }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)

        var results: [DirectoryChildEntry] = []
        while true {
            let count = getattrlistbulk(fd, &attrList, baseAddr, buf.count, 0)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            var offset = 0
            for _ in 0..<count {
                guard offset + 4 <= buf.count else { break }
                let recLen = Int(buf.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let attrSetSize = MemoryLayout<attribute_set_t>.size
                guard recLen >= 4 + attrSetSize, offset + recLen <= buf.count else { break }
                let entryEnd = offset + recLen
                var cursor = offset + 4
                let returned = buf.loadUnaligned(fromByteOffset: cursor, as: attribute_set_t.self)
                cursor += attrSetSize

                if (returned.commonattr & attrgroup_t(ATTR_CMN_ERROR)) != 0 {
                    offset = entryEnd
                    continue
                }

                var entryName: String?
                if (returned.commonattr & attrgroup_t(ATTR_CMN_NAME)) != 0 {
                    let refSize = MemoryLayout<attrreference_t>.size
                    guard cursor + refSize <= entryEnd else { offset = entryEnd; continue }
                    let nameRef = buf.loadUnaligned(fromByteOffset: cursor, as: attrreference_t.self)
                    let nameStart = cursor + Int(nameRef.attr_dataoffset)
                    let nameLen = Int(nameRef.attr_length)
                    if nameStart >= offset, nameLen > 0, nameStart + nameLen <= entryEnd {
                        let slice = UnsafeBufferPointer(
                            start: baseAddr.advanced(by: nameStart).assumingMemoryBound(to: UInt8.self),
                            count: nameLen
                        )
                        let trimmedLen = slice.firstIndex(of: 0) ?? nameLen
                        entryName = String(decoding: slice.prefix(trimmedLen), as: UTF8.self)
                    }
                    cursor += refSize
                }

                var rawIsDir = false
                if (returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE)) != 0 {
                    let typeSize = MemoryLayout<UInt32>.size
                    guard cursor + typeSize <= entryEnd else { offset = entryEnd; continue }
                    let objType = buf.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
                    rawIsDir = (objType == VDIR.rawValue)
                }

                if let name = entryName,
                   let child = makeFilteredEntry(
                    parentPath: path, name: name, rawIsDir: rawIsDir,
                    includeHidden: includeHidden, excludedPaths: excludedPaths, skippedFolders: skippedFolders
                   ) {
                    results.append(child)
                }
                offset = entryEnd
            }
        }
        return results
    }

    static func enumerateViaReaddir(
        at path: String,
        includeHidden: Bool,
        excludedPaths: Set<String>,
        skippedFolders: Set<String>
    ) -> [DirectoryChildEntry] {
        guard let dir = path.withCString({ opendir($0) }) else { return [] }
        defer { closedir(dir) }
        var results: [DirectoryChildEntry] = []
        while let entry = readdir(dir) {
            let len = Int(entry.pointee.d_namlen) + 1
            let name: String = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: len) { String(cString: $0) }
            }
            let childPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
            let rawIsDir: Bool
            switch Int32(entry.pointee.d_type) {
            case DT_DIR:
                rawIsDir = true
            case DT_UNKNOWN:
                var st = stat()
                rawIsDir = childPath.withCString { lstat($0, &st) == 0 } && ((st.st_mode & S_IFMT) == S_IFDIR)
            default:
                rawIsDir = false
            }
            if let child = makeFilteredEntry(
                parentPath: path, name: name, rawIsDir: rawIsDir,
                includeHidden: includeHidden, excludedPaths: excludedPaths, skippedFolders: skippedFolders
            ) {
                results.append(child)
            }
        }
        return results
    }

    private static func makeFilteredEntry(
        parentPath: String,
        name: String,
        rawIsDir: Bool,
        includeHidden: Bool,
        excludedPaths: Set<String>,
        skippedFolders: Set<String>
    ) -> DirectoryChildEntry? {
        if name.isEmpty || name == "." || name == ".." { return nil }
        if !includeHidden && name.hasPrefix(".") { return nil }
        if !excludedPaths.isEmpty {
            let childPath = parentPath == "/" ? "/\(name)" : "\(parentPath)/\(name)"
            if EverythingIndex.isPathExcluded(childPath, excludedPaths: excludedPaths) { return nil }
        }
        let isPackage = rawIsDir && EverythingIndex.hasPackageSuffix(name)
        let isDirectory = rawIsDir && !isPackage
        if isDirectory && !includeHidden && skippedFolders.contains(name) { return nil }
        return DirectoryChildEntry(name: name, isDirectory: isDirectory)
    }
}
