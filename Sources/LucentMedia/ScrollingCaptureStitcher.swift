import CoreGraphics
import Foundation
import LucentFoundation

public enum ScrollAppendOutcome: Equatable, Sendable {
    case initialized(height: Int)
    case unchanged
    case appendedDown(addedRows: Int, totalHeight: Int)
    case appendedUp(addedRows: Int, totalHeight: Int)
    case overlapLost
    case reachedMaxHeight(Int)
}

/// Pure CPU row-hash + strip-verification scrolling screenshot stitcher inspired by AirSnip §4.5.
/// Automatically detects sticky header/footer bands, supports both downward and upward scrolling,
/// and records checkpoints so `undoLastSegment()` cleanly rolls back mis-stitched frames.
public final class ScrollingCaptureStitcher: @unchecked Sendable {
    private struct FrameDigest {
        let width: Int
        let height: Int
        let rgba: [UInt8]
        let rowHashes: [UInt64]
    }

    private struct Checkpoint {
        let stitchedRows: Int
        let stitchedRGBA: [UInt8]
        let lastFrame: FrameDigest
        let topFixed: Int
        let bottomFixed: Int
    }

    public let maxPixelHeight: Int
    private(set) public var width: Int = 0
    private(set) public var stitchedRows: Int = 0
    private(set) public var segmentCount: Int = 0
    private var topFixedRows: Int = 0
    private var bottomFixedRows: Int = 0
    private var stitchedRGBA: [UInt8] = []
    private var lastFrame: FrameDigest?
    private var undoCheckpoints: [Checkpoint] = []

    public init(maxPixelHeight: Int = 30_000) {
        self.maxPixelHeight = max(1_200, maxPixelHeight)
    }

    public var canUndo: Bool { !undoCheckpoints.isEmpty }

    public var totalRenderedHeight: Int {
        guard let last = lastFrame else { return 0 }
        return topFixedRows + stitchedRows + bottomFixedRows + (stitchedRows == 0 ? last.height : 0)
    }

    public func pushFrame(_ image: CGImage) -> ScrollAppendOutcome {
        guard let digest = Self.makeDigest(from: image) else { return .unchanged }
        guard let prev = lastFrame else {
            width = digest.width
            topFixedRows = 0
            bottomFixedRows = 0
            stitchedRows = digest.height
            stitchedRGBA = digest.rgba
            lastFrame = digest
            segmentCount = 1
            return .initialized(height: digest.height)
        }
        guard digest.width == prev.width, digest.height == prev.height else { return .unchanged }
        if identicalRows(prev, digest, range: 0..<digest.height) >= Int(Double(digest.height) * 0.985) {
            return .unchanged
        }

        let detectedTop = min(digest.height / 3, leadingIdenticalRows(prev, digest))
        let detectedBottom = min(digest.height / 3, trailingIdenticalRows(prev, digest))
        let effTop = segmentCount == 1 ? detectedTop : min(max(topFixedRows, detectedTop), digest.height / 3)
        let effBottom = segmentCount == 1 ? detectedBottom : min(max(bottomFixedRows, detectedBottom), digest.height / 3)
        let scrollStart = effTop
        let scrollEnd = digest.height - effBottom
        let scrollSpan = scrollEnd - scrollStart
        guard scrollSpan >= 32 else { return .unchanged }

        if let shiftDown = matchDownwardShift(prev: prev, next: digest, start: scrollStart, end: scrollEnd) {
            guard shiftDown >= 6 else { return .unchanged }
            let projected = stitchedRows + shiftDown + effBottom
            guard projected <= maxPixelHeight else { return .reachedMaxHeight(maxPixelHeight) }
            saveCheckpoint()
            if segmentCount == 1 && effBottom > 0 {
                let trimBytes = effBottom * width * 4
                if stitchedRGBA.count > trimBytes {
                    stitchedRGBA.removeLast(trimBytes)
                    stitchedRows -= effBottom
                }
            }
            topFixedRows = effTop
            bottomFixedRows = effBottom
            let appendStartRow = scrollEnd - shiftDown
            let sliceStartByte = appendStartRow * width * 4
            let sliceEndByte = scrollEnd * width * 4
            stitchedRGBA.append(contentsOf: digest.rgba[sliceStartByte..<sliceEndByte])
            stitchedRows += shiftDown
            lastFrame = digest
            segmentCount += 1
            return .appendedDown(addedRows: shiftDown, totalHeight: stitchedRows + bottomFixedRows)
        }

        if let shiftUp = matchUpwardShift(prev: prev, next: digest, start: scrollStart, end: scrollEnd) {
            guard shiftUp >= 6 else { return .unchanged }
            let projected = stitchedRows + shiftUp + effBottom
            guard projected <= maxPixelHeight else { return .reachedMaxHeight(maxPixelHeight) }
            saveCheckpoint()
            if segmentCount == 1 && effBottom > 0 {
                let trimBytes = effBottom * width * 4
                if stitchedRGBA.count > trimBytes {
                    stitchedRGBA.removeLast(trimBytes)
                    stitchedRows -= effBottom
                }
            }
            topFixedRows = effTop
            bottomFixedRows = effBottom
            let headBytes = topFixedRows * width * 4
            let newStartByte = scrollStart * width * 4
            let newEndByte = (scrollStart + shiftUp) * width * 4
            stitchedRGBA.insert(contentsOf: digest.rgba[newStartByte..<newEndByte], at: min(headBytes, stitchedRGBA.count))
            stitchedRows += shiftUp
            lastFrame = digest
            segmentCount += 1
            return .appendedUp(addedRows: shiftUp, totalHeight: stitchedRows + bottomFixedRows)
        }

        return .overlapLost
    }

    @discardableResult
    public func undoLastSegment() -> Bool {
        guard let snap = undoCheckpoints.popLast() else { return false }
        stitchedRows = snap.stitchedRows
        stitchedRGBA = snap.stitchedRGBA
        lastFrame = snap.lastFrame
        topFixedRows = snap.topFixed
        bottomFixedRows = snap.bottomFixed
        segmentCount = max(1, segmentCount - 1)
        return true
    }

    public func makeComposedImage() -> CGImage? {
        guard let last = lastFrame, width > 0, stitchedRows > 0 else { return nil }
        var full = stitchedRGBA
        var outHeight = stitchedRows
        if segmentCount > 1 && bottomFixedRows > 0 {
            let startByte = (last.height - bottomFixedRows) * width * 4
            full.append(contentsOf: last.rgba[startByte..<last.rgba.count])
            outHeight += bottomFixedRows
        }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return full.withUnsafeMutableBytes { rawBuf -> CGImage? in
            guard let base = rawBuf.baseAddress,
                  let ctx = CGContext(
                      data: base, width: width, height: outHeight, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return nil }
            return ctx.makeImage()
        }
    }

    private func saveCheckpoint() {
        guard let lastFrame else { return }
        if undoCheckpoints.count >= 12 { undoCheckpoints.removeFirst() }
        undoCheckpoints.append(Checkpoint(
            stitchedRows: stitchedRows, stitchedRGBA: stitchedRGBA,
            lastFrame: lastFrame, topFixed: topFixedRows, bottomFixed: bottomFixedRows
        ))
    }

    private func matchDownwardShift(prev: FrameDigest, next: FrameDigest, start: Int, end: Int) -> Int? {
        let span = end - start
        let band = min(28, max(10, span / 5))
        let anchorStart = end - band
        guard anchorStart > start + 4 else { return nil }
        let maxShift = span - band
        var bestShift: Int?
        var bestScore = Double.greatestFiniteMagnitude
        for shift in 4...maxShift {
            let candStart = anchorStart - shift
            let hashHits = (0..<band).filter { prev.rowHashes[anchorStart + $0] == next.rowHashes[candStart + $0] }.count
            if hashHits < band / 4 {
                let err = meanAbsDiff(prev: prev, rowA: anchorStart, next: next, rowB: candStart, rows: band)
                if err < bestScore && err < 14.0 { bestScore = err; bestShift = shift }
            } else {
                let err = meanAbsDiff(prev: prev, rowA: anchorStart, next: next, rowB: candStart, rows: band)
                if err < bestScore && err < 18.0 { bestScore = err; bestShift = shift }
                if err < 2.2 { return shift }
            }
        }
        return bestShift
    }

    private func matchUpwardShift(prev: FrameDigest, next: FrameDigest, start: Int, end: Int) -> Int? {
        let span = end - start
        let band = min(28, max(10, span / 5))
        guard start + band < end - 4 else { return nil }
        let maxShift = span - band
        var bestShift: Int?
        var bestScore = Double.greatestFiniteMagnitude
        for shift in 4...maxShift {
            let candStart = start + shift
            let err = meanAbsDiff(prev: prev, rowA: start, next: next, rowB: candStart, rows: band)
            if err < bestScore && err < 14.0 { bestScore = err; bestShift = shift }
            if err < 2.2 { return shift }
        }
        return bestShift
    }

    private func identicalRows(_ a: FrameDigest, _ b: FrameDigest, range: Range<Int>) -> Int {
        range.filter { a.rowHashes[$0] == b.rowHashes[$0] }.count
    }

    private func leadingIdenticalRows(_ a: FrameDigest, _ b: FrameDigest) -> Int {
        var count = 0
        for r in 0..<a.height {
            if a.rowHashes[r] == b.rowHashes[r] || meanAbsDiff(prev: a, rowA: r, next: b, rowB: r, rows: 1) < 2.5 { count += 1 }
            else { break }
        }
        return count
    }

    private func trailingIdenticalRows(_ a: FrameDigest, _ b: FrameDigest) -> Int {
        var count = 0
        for idx in 0..<a.height {
            let r = a.height - 1 - idx
            if a.rowHashes[r] == b.rowHashes[r] || meanAbsDiff(prev: a, rowA: r, next: b, rowB: r, rows: 1) < 2.5 { count += 1 }
            else { break }
        }
        return count
    }

    private func meanAbsDiff(prev: FrameDigest, rowA: Int, next: FrameDigest, rowB: Int, rows: Int) -> Double {
        let stepX = max(1, width / 48)
        var sum = 0, samples = 0
        for r in 0..<rows {
            let baseA = (rowA + r) * width * 4, baseB = (rowB + r) * width * 4
            var x = 4
            while x < width - 4 {
                let ia = baseA + x * 4, ib = baseB + x * 4
                sum += abs(Int(prev.rgba[ia]) - Int(next.rgba[ib]))
                    + abs(Int(prev.rgba[ia + 1]) - Int(next.rgba[ib + 1]))
                    + abs(Int(prev.rgba[ia + 2]) - Int(next.rgba[ib + 2]))
                samples += 3; x += stepX
            }
        }
        return samples > 0 ? Double(sum) / Double(samples) : 255.0
    }

    private static func makeDigest(from cgImage: CGImage) -> FrameDigest? {
        let w = cgImage.width, h = cgImage.height
        guard w >= 16, h >= 32 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ptr = raw.baseAddress,
                  let ctx = CGContext(
                      data: ptr, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let stepX = max(1, w / 64)
        var hashes = [UInt64](repeating: 0, count: h)
        for y in 0..<h {
            var hVal: UInt64 = 14695981039346656037
            let rowStart = y * w * 4
            var x = 4
            while x < w - 4 {
                let idx = rowStart + x * 4
                let q = UInt64((buf[idx] >> 3) << 10) | UInt64((buf[idx + 1] >> 3) << 5) | UInt64(buf[idx + 2] >> 3)
                hVal = (hVal ^ q) &* 1099511628211
                x += stepX
            }
            hashes[y] = hVal
        }
        return FrameDigest(width: w, height: h, rgba: buf, rowHashes: hashes)
    }
}
