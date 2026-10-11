import Foundation

/// Splits a byte stream into newline-delimited frames.
///
/// Every bridge message is a single line of compact JSON, so framing is
/// trivially robust: JSON string escapes guarantee no raw `\n` inside a frame.
public struct LineFramer: Sendable {
    public static let delimiter: UInt8 = 0x0A
    public static let maxFrameBytes = 8 * 1024 * 1024

    private var buffer = Data()

    public init() {}

    /// Appends bytes and returns every complete frame now available.
    public mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while let index = buffer.firstIndex(of: Self.delimiter) {
            let frame = buffer[buffer.startIndex..<index]
            if !frame.isEmpty { frames.append(Data(frame)) }
            buffer.removeSubrange(buffer.startIndex...index)
        }
        guard buffer.count <= Self.maxFrameBytes else {
            buffer.removeAll()
            throw FramingError.frameTooLarge
        }
        return frames
    }

    public enum FramingError: Error {
        case frameTooLarge
    }
}

public extension UnixSocket {
    /// Encodes `value` as one JSON line and writes it.
    func sendFrame<T: Encodable>(_ value: T) throws {
        var data = try JSONEncoder.bridge.encode(value)
        data.append(LineFramer.delimiter)
        try send(data)
    }

    /// Blocks until one full frame arrives (or the peer closes / times out).
    func receiveFrame<T: Decodable>(_ type: T.Type) throws -> T {
        var framer = LineFramer()
        while true {
            let chunk = try receive()
            guard !chunk.isEmpty else { throw SocketError.closed }
            if let frame = try framer.append(chunk).first {
                return try JSONDecoder().decode(T.self, from: frame)
            }
        }
    }
}

public extension JSONEncoder {
    /// Compact encoder used on the wire (never pretty-printed: one frame per line).
    static var bridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
