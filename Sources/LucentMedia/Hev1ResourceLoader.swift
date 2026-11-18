import AVFoundation
import Foundation
import LucentFoundation
import ObjectiveC
import UniformTypeIdentifiers

public final class Hev1ResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private nonisolated(unsafe) static var assocKey: UInt8 = 0
    private static let containerBoxes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl"]
    private static let patchableTags: Set<String> = ["hev1", "dvh1", "dvhe"]
    private static let hev1FallbackPattern = Data([0x68, 0x65, 0x76, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    private static let hvc1Bytes: [UInt8] = [0x68, 0x76, 0x63, 0x31]

    public let fileURL: URL
    public let fileSize: Int64
    public let patchOffsets: [Int64]
    private let contentTypeIdentifier: String
    private let loaderQueue = DispatchQueue(label: "app.lucent.hev1.loader", qos: .userInitiated)
    private var sharedHandle: FileHandle?
    private var activeRequests = Set<ObjectIdentifier>()

    public init(fileURL: URL, fileSize: Int64, patchOffsets: [Int64]) {
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.patchOffsets = patchOffsets
        self.contentTypeIdentifier = UTType(filenameExtension: fileURL.pathExtension)?.identifier
            ?? UTType.mpeg4Movie.identifier
    }

    deinit {
        try? sharedHandle?.close()
    }

    public static func findHev1SampleEntryOffsets(in fileURL: URL) -> (fileSize: Int64, offsets: [Int64]) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return (0, []) }
        defer { try? handle.close() }
        let fileSize = Int64((try? handle.seekToEnd()) ?? 0)
        guard fileSize >= 16 else { return (fileSize, []) }

        var offset: Int64 = 0
        var sawMoov = false
        var hits: [Int64] = []

        while offset + 8 <= fileSize {
            guard let box = readBoxHeader(handle: handle, at: offset, limit: fileSize) else { break }
            if box.type == "moov" {
                sawMoov = true
                var moovHits: [Int64] = []
                collectStsdPatchOffsets(
                    handle: handle,
                    start: offset + box.headerSize,
                    end: offset + box.size,
                    depth: 0,
                    into: &moovHits
                )
                if moovHits.isEmpty && box.size <= 64 * 1024 * 1024 {
                    moovHits = scanFallbackPatternInRange(handle: handle, start: offset, end: offset + box.size)
                }
                hits.append(contentsOf: moovHits)
            }
            let next = offset + box.size
            if next <= offset { break }
            offset = next
        }

        if !sawMoov && fileSize <= 8 * 1024 * 1024 {
            hits = scanFallbackPatternInRange(handle: handle, start: 0, end: min(fileSize, 1_048_576))
        }
        return (fileSize, Array(Set(hits)).sorted())
    }

    private static func collectStsdPatchOffsets(
        handle: FileHandle,
        start: Int64,
        end: Int64,
        depth: Int,
        into hits: inout [Int64]
    ) {
        guard depth <= 8, start + 8 <= end else { return }
        var cursor = start
        while cursor + 8 <= end {
            guard let box = readBoxHeader(handle: handle, at: cursor, limit: end) else { break }
            let boxEnd = cursor + box.size
            if containerBoxes.contains(box.type) {
                collectStsdPatchOffsets(handle: handle, start: cursor + box.headerSize, end: boxEnd, depth: depth + 1, into: &hits)
            } else if box.type == "stsd" {
                let entriesStart = cursor + box.headerSize + 8
                var entryCursor = entriesStart
                while entryCursor + 16 <= boxEnd {
                    guard let entry = readBoxHeader(handle: handle, at: entryCursor, limit: boxEnd) else { break }
                    if patchableTags.contains(entry.type) {
                        hits.append(entryCursor + 4)
                    }
                    let nextEntry = entryCursor + entry.size
                    if nextEntry <= entryCursor { break }
                    entryCursor = nextEntry
                }
            }
            if boxEnd <= cursor { break }
            cursor = boxEnd
        }
    }

    private static func readBoxHeader(
        handle: FileHandle,
        at offset: Int64,
        limit: Int64
    ) -> (type: String, size: Int64, headerSize: Int64)? {
        guard offset + 8 <= limit else { return nil }
        try? handle.seek(toOffset: UInt64(offset))
        guard let hdr = try? handle.read(upToCount: 16), hdr.count >= 8 else { return nil }
        let size32 = UInt32(hdr[0]) << 24 | UInt32(hdr[1]) << 16 | UInt32(hdr[2]) << 8 | UInt32(hdr[3])
        let type = String(bytes: hdr[4..<8], encoding: .ascii) ?? ""
        let boxSize: Int64
        let headerSize: Int64
        if size32 == 1 {
            guard hdr.count >= 16 else { return nil }
            var size64: UInt64 = 0
            for i in 8..<16 { size64 = (size64 << 8) | UInt64(hdr[i]) }
            boxSize = Int64(min(size64, UInt64(limit - offset)))
            headerSize = 16
        } else if size32 == 0 {
            boxSize = limit - offset
            headerSize = 8
        } else {
            boxSize = Int64(size32)
            headerSize = 8
        }
        guard boxSize >= headerSize, offset + boxSize <= limit else { return nil }
        return (type, boxSize, headerSize)
    }

    private static func scanFallbackPatternInRange(handle: FileHandle, start: Int64, end: Int64) -> [Int64] {
        guard end > start else { return [] }
        var found: [Int64] = []
        var pos = start
        let step: Int64 = 262_144
        let overlap = Int64(hev1FallbackPattern.count)
        while pos < end {
            try? handle.seek(toOffset: UInt64(pos))
            let toRead = Int(min(step + overlap, end - pos))
            guard let chunk = try? handle.read(upToCount: toRead), chunk.count >= overlap else { break }
            var range = chunk.startIndex..<chunk.endIndex
            while let hit = chunk.range(of: hev1FallbackPattern, options: [], in: range) {
                found.append(pos + Int64(hit.lowerBound - chunk.startIndex))
                let nextIdx = hit.lowerBound + hev1FallbackPattern.count
                if nextIdx >= chunk.endIndex { break }
                range = nextIdx..<chunk.endIndex
            }
            if pos + Int64(chunk.count) >= end { break }
            pos += step
        }
        return found
    }

    public static func makePatchedAsset(fileURL: URL, fileSize: Int64, patchOffsets: [Int64]) -> AVURLAsset? {
        guard var comps = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "lucent-hev1"
        guard let customURL = comps.url else { return nil }
        let loader = Hev1ResourceLoader(fileURL: fileURL, fileSize: fileSize, patchOffsets: patchOffsets)
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        objc_setAssociatedObject(asset, &assocKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return asset
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentTypeIdentifier
            info.contentLength = fileSize
            info.isByteRangeAccessSupported = true
        }
        guard let dataReq = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }
        let startOffset = dataReq.currentOffset > 0 ? dataReq.currentOffset : dataReq.requestedOffset
        let endOffset = dataReq.requestsAllDataToEndOfResource
            ? fileSize
            : min(fileSize, dataReq.requestedOffset + Int64(dataReq.requestedLength))
        guard endOffset > startOffset else {
            loadingRequest.finishLoading()
            return true
        }
        let reqID = ObjectIdentifier(loadingRequest)
        activeRequests.insert(reqID)
        loaderQueue.async { [weak self] in
            self?.feedNextChunk(loadingRequest: loadingRequest, dataReq: dataReq, cursor: startOffset, endOffset: endOffset)
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        activeRequests.remove(ObjectIdentifier(loadingRequest))
    }

    private func obtainHandle() throws -> FileHandle {
        if let existing = sharedHandle { return existing }
        let opened = try FileHandle(forReadingFrom: fileURL)
        sharedHandle = opened
        return opened
    }

    private func feedNextChunk(
        loadingRequest: AVAssetResourceLoadingRequest,
        dataReq: AVAssetResourceLoadingDataRequest,
        cursor: Int64,
        endOffset: Int64
    ) {
        let reqID = ObjectIdentifier(loadingRequest)
        guard !loadingRequest.isCancelled, activeRequests.contains(reqID) else {
            activeRequests.remove(reqID)
            return
        }
        let handle: FileHandle
        do {
            handle = try obtainHandle()
            try handle.seek(toOffset: UInt64(cursor))
        } catch {
            activeRequests.remove(reqID)
            loadingRequest.finishLoading(with: error)
            return
        }
        let remaining = endOffset - cursor
        guard remaining > 0, var chunk = try? handle.read(upToCount: Int(min(262_144, remaining))), !chunk.isEmpty else {
            activeRequests.remove(reqID)
            loadingRequest.finishLoading()
            return
        }
        let chunkEnd = cursor + Int64(chunk.count)
        for patchPos in patchOffsets where patchPos + 4 > cursor && patchPos < chunkEnd {
            for byteIdx in 0..<4 {
                let gPos = patchPos + Int64(byteIdx)
                if gPos >= cursor && gPos < chunkEnd {
                    chunk[Int(gPos - cursor)] = Self.hvc1Bytes[byteIdx]
                }
            }
        }
        dataReq.respond(with: chunk)
        if chunkEnd >= endOffset {
            activeRequests.remove(reqID)
            loadingRequest.finishLoading()
        } else {
            loaderQueue.async { [weak self] in
                self?.feedNextChunk(loadingRequest: loadingRequest, dataReq: dataReq, cursor: chunkEnd, endOffset: endOffset)
            }
        }
    }
}
