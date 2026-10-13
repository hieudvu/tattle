import Foundation

public enum FramingError: Error, Equatable, Sendable {
    case oversize(length: Int)
    /// A previous `oversize` left the stream unsynchronised; the connection must be dropped.
    case failed
}

/// Chrome / Firefox native-messaging framing: 4-byte little-endian length, then UTF-8 JSON.
public enum NativeMessageFraming {
    public static let maxFrameBytes = 1 << 20

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maxFrameBytes else { throw FramingError.oversize(length: payload.count) }
        var length = UInt32(payload.count).littleEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }
}

/// Streaming decoder: feed it whatever a `read` returned (partial frame, several
/// frames, anything) and get back every complete payload.
public struct NativeMessageFrameDecoder: Sendable {
    private var buffer = Data()
    private var failed = false

    public init() {}

    public mutating func feed(_ chunk: Data) throws -> [Data] {
        if failed { throw FramingError.failed }
        buffer.append(chunk)
        var frames: [Data] = []
        var offset = buffer.startIndex
        while buffer.endIndex - offset >= 4 {
            let b = buffer[offset..<offset + 4]
            let length = b.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            if length > NativeMessageFraming.maxFrameBytes {
                failed = true
                buffer = Data()
                throw FramingError.oversize(length: length)
            }
            guard buffer.endIndex - offset - 4 >= length else { break }
            frames.append(Data(buffer[offset + 4..<offset + 4 + length]))
            offset += 4 + length
        }
        buffer = Data(buffer[offset...])
        return frames
    }
}
