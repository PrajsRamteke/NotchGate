import Compression
import Foundation

/// Reads the members of a small zip file: the Python wheel Whistle's engine comes in.
/// Stored and deflated members only.
struct ZipArchive {
    struct ReadError: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    var names: [String] { Array(entries.keys) }

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.data = data
        // The end-of-central-directory record sits in the last 64 KB (after an optional comment).
        let floor = max(0, data.count - 22 - 65_535)
        var end = data.count - 22
        while end >= floor, Self.uint32(data, end) != 0x0605_4B50 { end -= 1 }
        guard end >= floor else { throw ReadError(reason: "not a zip file") }

        let count = Int(Self.uint16(data, end + 10))
        var offset = Int(Self.uint32(data, end + 16))
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= data.count, Self.uint32(data, offset) == 0x0201_4B50 else {
                throw ReadError(reason: "damaged zip directory")
            }
            let nameLength = Int(Self.uint16(data, offset + 28))
            let extraLength = Int(Self.uint16(data, offset + 30))
            let commentLength = Int(Self.uint16(data, offset + 32))
            guard offset + 46 + nameLength <= data.count else { throw ReadError(reason: "damaged zip directory") }
            let name = String(decoding: data[(data.startIndex + offset + 46)..<(data.startIndex + offset + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(
                method: Self.uint16(data, offset + 10),
                compressedSize: Int(Self.uint32(data, offset + 20)),
                size: Int(Self.uint32(data, offset + 24)),
                headerOffset: Int(Self.uint32(data, offset + 42))
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// One member's bytes, inflated.
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw ReadError(reason: "\(name) is missing") }
        let header = entry.headerOffset
        guard header + 30 <= data.count, Self.uint32(data, header) == 0x0403_4B50 else {
            throw ReadError(reason: "damaged entry \(name)")
        }
        // The local header's own name and extra lengths (NumPy writes zip64 extras here only).
        let start = header + 30 + Int(Self.uint16(data, header + 26)) + Int(Self.uint16(data, header + 28))
        guard start + entry.compressedSize <= data.count else { throw ReadError(reason: "truncated entry \(name)") }
        let stored = data[(data.startIndex + start)..<(data.startIndex + start + entry.compressedSize)]

        switch entry.method {
        case 0:
            return Data(stored)
        case 8:
            var output = Data(count: entry.size)
            let written = output.withUnsafeMutableBytes { destination in
                stored.withUnsafeBytes { source in
                    // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what zip stores.
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                        source.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == entry.size else { throw ReadError(reason: "couldn't inflate \(name)") }
            return output
        default:
            throw ReadError(reason: "\(name) uses an unsupported compression method")
        }
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }
}
