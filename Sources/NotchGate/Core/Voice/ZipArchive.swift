import Accelerate
import Compression
import Foundation

/// Reads the members of a small zip file: the `.npz` arrays Underdog Bark's decoder comes
/// in, and the Python wheel Whistle's engine comes in. Stored and deflated members only.
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

    fileprivate static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
    }

    fileprivate static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }
}

/// The arrays of a NumPy `.npz` file, by name: little-endian float32, float16 and int8 only.
struct NumpyArchive {
    struct NumpyArray {
        let dtype: String
        let shape: [Int]
        /// The raw values, row-major.
        let bytes: Data

        var count: Int { shape.reduce(1, *) }
    }

    private let zip: ZipArchive

    init(contentsOf url: URL) throws {
        zip = try ZipArchive(contentsOf: url)
    }

    init(data: Data) throws {
        zip = try ZipArchive(data: data)
    }

    func contains(_ name: String) -> Bool {
        zip.names.contains(name + ".npy")
    }

    func array(_ name: String) throws -> NumpyArray {
        try Self.parse(zip.read(name + ".npy"), name: name)
    }

    /// The array as Float, whether it's stored as float32 or float16.
    func floats(_ name: String) throws -> [Float] {
        let array = try array(name)
        switch array.dtype {
        case "<f4":
            return array.bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(array.count)) }
        case "<f2":
            return Self.halfToFloat(array.bytes, count: array.count)
        default:
            throw ZipArchive.ReadError(reason: "\(name) is \(array.dtype), not a float array")
        }
    }

    /// int8 values `.q` times their per-row float16 scale `.s`, or the plain array when it isn't quantized.
    func dequantized(_ name: String) throws -> [Float] {
        guard contains(name + ".q") else { return try floats(name) }
        let quantized = try array(name + ".q")
        let scales = try floats(name + ".s")
        guard quantized.dtype == "|i1", quantized.shape.count == 2, quantized.shape[0] == scales.count else {
            throw ZipArchive.ReadError(reason: "\(name) isn't an int8 matrix with a scale per row")
        }
        let columns = quantized.shape[1]
        var values = [Float](repeating: 0, count: quantized.count)
        quantized.bytes.withUnsafeBytes { raw in
            let int8s = raw.bindMemory(to: Int8.self).baseAddress!
            values.withUnsafeMutableBufferPointer { output in
                vDSP_vflt8(int8s, 1, output.baseAddress!, 1, vDSP_Length(quantized.count))
                for (row, scale) in scales.enumerated() {
                    var scale = scale
                    let start = output.baseAddress! + row * columns
                    vDSP_vsmul(start, 1, &scale, start, 1, vDSP_Length(columns))
                }
            }
        }
        return values
    }

    static func parse(_ file: Data, name: String) throws -> NumpyArray {
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]  // \x93NUMPY
        guard file.count > 10, Array(file.prefix(6)) == magic else {
            throw ZipArchive.ReadError(reason: "\(name) isn't a .npy array")
        }
        let major = file[file.startIndex + 6]
        let headerLength = major == 1 ? Int(ZipArchive.uint16(file, 8)) : Int(ZipArchive.uint32(file, 8))
        let headerStart = major == 1 ? 10 : 12
        guard file.count >= headerStart + headerLength else { throw ZipArchive.ReadError(reason: "\(name) is truncated") }
        let header = String(decoding: file[(file.startIndex + headerStart)..<(file.startIndex + headerStart + headerLength)], as: UTF8.self)

        guard let dtype = header.firstMatch(of: /'descr':\s*'([^']+)'/)?.1,
              let shapeText = header.firstMatch(of: /'shape':\s*\(([^)]*)\)/)?.1,
              !header.contains("'fortran_order': True")
        else { throw ZipArchive.ReadError(reason: "\(name) has an unreadable header") }
        let shape = shapeText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let bytes = Data(file[(file.startIndex + headerStart + headerLength)...])
        let width = switch dtype { case "<f4": 4 case "<f2": 2 default: 1 }
        guard bytes.count >= shape.reduce(1, *) * width else { throw ZipArchive.ReadError(reason: "\(name) is truncated") }
        return NumpyArray(dtype: String(dtype), shape: shape, bytes: bytes)
    }

    /// IEEE half floats to Float (vImage works on Intel too, where Swift has no Float16).
    static func halfToFloat(_ halves: Data, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        halves.withUnsafeBytes { raw in
            output.withUnsafeMutableBytes { floats in
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress!), height: 1,
                                           width: vImagePixelCount(count), rowBytes: count * 2)
                var destination = vImage_Buffer(data: floats.baseAddress!, height: 1,
                                                width: vImagePixelCount(count), rowBytes: count * 4)
                vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
            }
        }
        return output
    }
}
