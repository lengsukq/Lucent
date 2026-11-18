import CryptoKit
import Darwin
import Foundation
import LucentFoundation

public struct SnapshotHeaderMetadata: Sendable {
    public let nodeCount: Int
    public let builtAt: Date
    public let reachedNodeLimit: Bool
}

public enum EverythingSnapshotStore {
    public static let formatMagic = Data("LCNTIDX3".utf8)
    private static let magic: [UInt8] = Array("LCNTIDX3".utf8)
    private static let sha256ByteCount = 32

    public static func defaultCacheDirectory() -> URL {
        LucentAppPaths.defaultIndexCacheDirectory()
    }

    public static func snapshotFileURL(scopeKey: String, cacheDirectory: URL? = nil) -> URL {
        let dir = cacheDirectory ?? defaultCacheDirectory()
        let digest = SHA256.hash(data: Data(scopeKey.utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("idx-\(hex).lcntidx", isDirectory: false)
    }

    public static func removeAllSnapshots(cacheDirectory: URL? = nil) -> Int64 {
        let dir = cacheDirectory ?? defaultCacheDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: []
        ) else { return 0 }
        var freed: Int64 = 0
        for url in urls where url.pathExtension == "lcntidx" {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if (try? FileManager.default.removeItem(at: url)) != nil {
                freed += size
            }
        }
        return freed
    }

    public static func readHeaderMetadata(
        scopeKey: String,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval = 43_200,
        cacheDirectory: URL? = nil
    ) -> SnapshotHeaderMetadata? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = (attrs[.size] as? NSNumber)?.intValue,
              fileSize >= magic.count + 17 + sha256ByteCount,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw -> SnapshotHeaderMetadata? in
            var offset = 0
            guard let parsed = parseHeader(raw, limit: raw.count, offset: &offset, expectedRoots: expectedRoots, maxAgeSeconds: maxAgeSeconds) else {
                return nil
            }
            return SnapshotHeaderMetadata(
                nodeCount: Int(parsed.nodeCount),
                builtAt: parsed.builtAt,
                reachedNodeLimit: parsed.reachedNodeLimit
            )
        }
    }

    @discardableResult
    public static func save(_ index: EverythingIndex, scopeKey: String, cacheDirectory: URL? = nil) -> URL? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var data = Data()
        data.reserveCapacity(max(4096, index.nodes.count * 26 + sha256ByteCount))
        data.append(contentsOf: magic)
        appendLE(index.builtAt.timeIntervalSince1970.bitPattern, to: &data)
        data.append(index.reachedNodeLimit ? 1 : 0)
        appendLE(UInt32(index.rootPaths.count), to: &data)
        for path in index.rootPaths {
            let utf8 = Array(path.utf8)
            appendLE(UInt32(utf8.count), to: &data)
            data.append(contentsOf: utf8)
        }
        appendLE(UInt32(index.nodes.count), to: &data)
        for node in index.nodes {
            appendLE(node.parentID, to: &data)
            appendLE(node.rootIndex, to: &data)
            data.append(node.isDirectory ? 1 : 0)
            var nameStr = node.name
            let writtenLen: Bool = nameStr.withUTF8 { utf8 in
                let count = min(utf8.count, Int(UInt16.max))
                appendLE(UInt16(count), to: &data)
                data.append(UnsafeBufferPointer(start: utf8.baseAddress, count: count))
                return true
            }
            if !writtenLen {
                appendLE(UInt16(0), to: &data)
            }
        }
        let digest = SHA256.hash(data: data)
        data.append(contentsOf: digest)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    public static func load(
        scopeKey: String,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval = 43_200,
        cacheDirectory: URL? = nil
    ) -> EverythingIndex? {
        let fileURL = snapshotFileURL(scopeKey: scopeKey, cacheDirectory: cacheDirectory)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count >= magic.count + 17 + sha256ByteCount else { return nil }
        return data.withUnsafeBytes { raw -> EverythingIndex? in
            let payloadEnd = raw.count - sha256ByteCount
            let payloadSlice = UnsafeRawBufferPointer(rebasing: raw[0..<payloadEnd])
            let expectedDigest = Array(UnsafeRawBufferPointer(rebasing: raw[payloadEnd..<raw.count]))
            let computedDigest = Array(SHA256.hash(data: payloadSlice))
            guard computedDigest == expectedDigest else {
                return nil
            }

            var offset = 0
            guard let header = parseHeader(
                raw, limit: payloadEnd, offset: &offset,
                expectedRoots: expectedRoots, maxAgeSeconds: maxAgeSeconds
            ) else {
                return nil
            }
            let rootCount = header.rootURLs.count
            guard rootCount <= Int(UInt16.max) else { return nil }
            var nodes: [IndexedNode] = []
            nodes.reserveCapacity(min(Int(header.nodeCount), 262_144))
            for currentIdx in 0..<Int(header.nodeCount) {
                guard let parentID = readLE(raw, limit: payloadEnd, offset: &offset, as: Int32.self),
                      let rootIndex = readLE(raw, limit: payloadEnd, offset: &offset, as: UInt16.self),
                      let isDirByte = readByte(raw, limit: payloadEnd, offset: &offset),
                      let nameLen = readLE(raw, limit: payloadEnd, offset: &offset, as: UInt16.self),
                      let name = readString(raw, limit: payloadEnd, offset: &offset, count: Int(nameLen)),
                      !name.isEmpty,
                      Int(rootIndex) < rootCount,
                      parentID >= -1 && Int(parentID) < currentIdx
                else { return nil }
                nodes.append(IndexedNode(
                    parentID: parentID,
                    rootIndex: rootIndex,
                    isDirectory: isDirByte != 0,
                    name: name
                ))
            }
            guard offset == payloadEnd else { return nil }
            return EverythingIndex(
                rootURLs: header.rootURLs,
                nodes: nodes,
                builtAt: header.builtAt,
                reachedNodeLimit: header.reachedNodeLimit
            )
        }
    }

    private struct ParsedHeader {
        let builtAt: Date
        let reachedNodeLimit: Bool
        let rootURLs: [URL]
        let nodeCount: UInt32
    }

    private static func parseHeader(
        _ raw: UnsafeRawBufferPointer,
        limit: Int,
        offset: inout Int,
        expectedRoots: [URL],
        maxAgeSeconds: TimeInterval
    ) -> ParsedHeader? {
        guard limit >= magic.count + 17 else { return nil }
        for i in 0..<magic.count where raw[i] != magic[i] { return nil }
        offset = magic.count

        guard let builtBits = readLE(raw, limit: limit, offset: &offset, as: UInt64.self),
              let reachedByte = readByte(raw, limit: limit, offset: &offset),
              let rootCount = readLE(raw, limit: limit, offset: &offset, as: UInt32.self),
              rootCount <= 256
        else { return nil }

        let builtAt = Date(timeIntervalSince1970: Double(bitPattern: builtBits))
        if Date().timeIntervalSince(builtAt) > maxAgeSeconds { return nil }

        var rootURLs: [URL] = []
        rootURLs.reserveCapacity(Int(rootCount))
        for _ in 0..<rootCount {
            guard let len = readLE(raw, limit: limit, offset: &offset, as: UInt32.self),
                  len <= 4096,
                  let path = readString(raw, limit: limit, offset: &offset, count: Int(len))
            else { return nil }
            rootURLs.append(URL(fileURLWithPath: path))
        }
        let expectedPaths = expectedRoots.map { $0.standardizedFileURL.path }
        guard rootURLs.map(\.path) == expectedPaths else { return nil }

        guard let nodeCount = readLE(raw, limit: limit, offset: &offset, as: UInt32.self) else { return nil }
        return ParsedHeader(builtAt: builtAt, reachedNodeLimit: reachedByte != 0, rootURLs: rootURLs, nodeCount: nodeCount)
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readByte(_ raw: UnsafeRawBufferPointer, limit: Int, offset: inout Int) -> UInt8? {
        guard offset < limit else { return nil }
        let b = raw[offset]
        offset += 1
        return b
    }

    private static func readLE<T: FixedWidthInteger>(_ raw: UnsafeRawBufferPointer, limit: Int, offset: inout Int, as _: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= limit, let base = raw.baseAddress else { return nil }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: base.advanced(by: offset), count: size))
        }
        offset += size
        return T(littleEndian: value)
    }

    private static func readString(_ raw: UnsafeRawBufferPointer, limit: Int, offset: inout Int, count: Int) -> String? {
        guard count >= 0, offset + count <= limit, let base = raw.baseAddress else { return nil }
        let slice = UnsafeRawBufferPointer(start: base.advanced(by: offset), count: count)
        offset += count
        return String(decoding: slice, as: UTF8.self)
    }
}
