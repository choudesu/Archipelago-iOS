import Foundation
import zlib

enum ZipExtractor {
    static func extract(zipURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: zipURL)
        try extract(data: data, to: destination)
    }

    static func extract(data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = try parseCentralDirectory(data)
        for entry in entries {
            let outputURL = destination.appendingPathComponent(entry.path)
            if entry.path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let fileData = try extractEntry(entry, from: data)
            try fileData.write(to: outputURL, options: .atomic)
        }
    }

    private struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    private static func parseCentralDirectory(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw PopTrackerPackError.installFailed("ZIP file is too small.") }
        var entries: [Entry] = []
        var offset = data.count - 22
        while offset >= 0 {
            if readUInt32(data, offset) == 0x06054b50 { break }
            offset -= 1
        }
        guard offset >= 0 else { throw PopTrackerPackError.installFailed("ZIP end of central directory not found.") }

        let centralDirectoryOffset = Int(readUInt32(data, offset + 16))
        let totalEntries = Int(readUInt16(data, offset + 10))
        var cursor = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count else { break }
            guard readUInt32(data, cursor) == 0x02014b50 else {
                throw PopTrackerPackError.installFailed("Invalid ZIP central directory entry.")
            }
            let compressionMethod = readUInt16(data, cursor + 10)
            let compressedSize = readUInt32(data, cursor + 20)
            let uncompressedSize = readUInt32(data, cursor + 24)
            let fileNameLength = Int(readUInt16(data, cursor + 28))
            let extraLength = Int(readUInt16(data, cursor + 30))
            let commentLength = Int(readUInt16(data, cursor + 32))
            let localHeaderOffset = readUInt32(data, cursor + 42)
            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }
            let pathData = data[nameStart..<nameEnd]
            let path = String(data: pathData, encoding: .utf8) ?? ""
            entries.append(Entry(
                path: path,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func extractEntry(_ entry: Entry, from data: Data) throws -> Data {
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= data.count else {
            throw PopTrackerPackError.installFailed("Invalid ZIP local header for \(entry.path).")
        }
        let fileNameLength = Int(readUInt16(data, offset + 26))
        let extraLength = Int(readUInt16(data, offset + 28))
        let payloadStart = offset + 30 + fileNameLength + extraLength
        let payloadEnd = payloadStart + Int(entry.compressedSize)
        guard payloadEnd <= data.count else {
            throw PopTrackerPackError.installFailed("Truncated ZIP entry \(entry.path).")
        }
        let compressed = data[payloadStart..<payloadEnd]

        switch entry.compressionMethod {
        case 0:
            return Data(compressed)
        case 8:
            return try decompressDeflate(Data(compressed), expectedSize: Int(entry.uncompressedSize))
        default:
            throw PopTrackerPackError.installFailed("Unsupported ZIP compression for \(entry.path).")
        }
    }

    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        var status = data.withUnsafeBytes { inputBuffer -> Int32 in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard status == Z_OK else {
            throw PopTrackerPackError.installFailed("Could not initialize ZIP inflater.")
        }
        defer { inflateEnd(&stream) }

        let capacity = max(expectedSize, data.count * 4)
        var output = Data(count: capacity)
        let decodedSize: Int = output.withUnsafeMutableBytes { outputBuffer in
            stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress!
            stream.avail_out = uInt(capacity)
            status = inflate(&stream, Z_FINISH)
            return capacity - Int(stream.avail_out)
        }
        guard status == Z_STREAM_END || status == Z_OK, decodedSize > 0 else {
            throw PopTrackerPackError.installFailed("Could not decompress ZIP entry.")
        }
        output.count = decodedSize
        return output
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
