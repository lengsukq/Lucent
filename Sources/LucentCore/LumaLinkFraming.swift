import Foundation

public enum LumaLinkFraming {
    public static let maxFrameBytes = 4 * 1024 * 1024

    public static func encodeFrame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }
}

public enum LumaLinkFramingError: Error {
    case frameTooLarge(Int)
}

public struct LumaLinkFrameAccumulator: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) throws -> [Data] {
        if !chunk.isEmpty { buffer.append(chunk) }
        var frames: [Data] = []
        while buffer.count >= 4 {
            let b0 = Int(buffer[buffer.startIndex])
            let b1 = Int(buffer[buffer.startIndex + 1])
            let b2 = Int(buffer[buffer.startIndex + 2])
            let b3 = Int(buffer[buffer.startIndex + 3])
            let length = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            guard length >= 0, length <= LumaLinkFraming.maxFrameBytes else {
                buffer.removeAll(keepingCapacity: false)
                throw LumaLinkFramingError.frameTooLarge(length)
            }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            let frame = Data(buffer[start..<(start + length)])
            buffer.removeFirst(4 + length)
            frames.append(frame)
        }
        return frames
    }
}
