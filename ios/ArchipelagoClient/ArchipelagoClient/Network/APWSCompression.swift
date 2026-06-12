import Foundation
import Starscream
import zlib

/// Archipelago-compatible permessage-deflate handler.
///
/// Starscream's built-in `WSCompression` defaults to 15 window bits, but Archipelago
/// servers negotiate 11. When the server omits `server_max_window_bits` in its
/// handshake response, the mismatch can corrupt decompression. Starscream then treats
/// compressed bytes as UTF-8 and closes the socket with protocol error 1002.
final class APWSCompression: CompressionHandler {
    private let headerWSExtensionName = "Sec-WebSocket-Extensions"
    private var decompressor: APWebSocketDecompressor?
    private var compressor: APWebSocketCompressor?
    private var decompressorTakeOver = false
    private var compressorTakeOver = false

    /// Archipelago MultiServer uses 11 for both compressor and decompressor.
    private let defaultWindowBits = 11

    init() {
        decompressor = APWebSocketDecompressor(windowBits: defaultWindowBits)
        compressor = APWebSocketCompressor(windowBits: defaultWindowBits)
    }

    func load(headers: [String: String]) {
        guard let extensionHeader = headers[headerWSExtensionName] else { return }
        decompressorTakeOver = false
        compressorTakeOver = false

        var serverWindowBits = defaultWindowBits
        var clientWindowBits = defaultWindowBits

        let parts = extensionHeader.components(separatedBy: ";")
        for part in parts {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("server_max_window_bits=") {
                if let value = Int(token.split(separator: "=").last ?? "") {
                    serverWindowBits = value
                }
            } else if token.hasPrefix("client_max_window_bits=") {
                if let value = Int(token.split(separator: "=").last ?? "") {
                    clientWindowBits = value
                }
            } else if token == "client_no_context_takeover" {
                compressorTakeOver = true
            } else if token == "server_no_context_takeover" {
                decompressorTakeOver = true
            }
        }

        decompressor = APWebSocketDecompressor(windowBits: serverWindowBits)
        compressor = APWebSocketCompressor(windowBits: clientWindowBits)
    }

    func decompress(data: Data, isFinal: Bool) -> Data? {
        guard let decompressor else { return nil }
        if let result = attemptDecompress(decompressor, data: data, isFinal: isFinal) {
            return result
        }

        // Recover from a corrupted zlib stream instead of returning nil, which
        // makes Starscream fall back to raw compressed bytes and trigger code 1002.
        do {
            try decompressor.reset()
            return attemptDecompress(decompressor, data: data, isFinal: isFinal)
        } catch {
            return nil
        }
    }

    func compress(data: Data) -> Data? {
        guard let compressor else { return nil }
        do {
            let compressedData = try compressor.compress(data)
            if compressorTakeOver {
                try compressor.reset()
            }
            return compressedData
        } catch {
            return nil
        }
    }

    private func attemptDecompress(
        _ decompressor: APWebSocketDecompressor,
        data: Data,
        isFinal: Bool
    ) -> Data? {
        do {
            let decompressedData = try decompressor.decompress(data, finish: isFinal)
            if decompressorTakeOver {
                try decompressor.reset()
            }
            return decompressedData
        } catch {
            return nil
        }
    }
}

private final class APWebSocketDecompressor {
    private var strm = z_stream()
    private var buffer: [UInt8]
    private var inflateInitialized = false
    private let windowBits: Int

    init?(windowBits: Int, bufferSize: Int = 0x10000) {
        self.windowBits = windowBits
        self.buffer = [UInt8](repeating: 0, count: bufferSize)
        guard initInflate() else { return nil }
    }

    private func initInflate() -> Bool {
        if Z_OK == zlib.inflateInit2_(
            &strm,
            -CInt(windowBits),
            ZLIB_VERSION,
            CInt(MemoryLayout<z_stream>.size)
        ) {
            inflateInitialized = true
            return true
        }
        return false
    }

    func reset() throws {
        teardownInflate()
        guard initInflate() else {
            throw WSError(type: .compressionError, message: "Error for decompressor on reset", code: 0)
        }
    }

    func decompress(_ data: Data, finish: Bool) throws -> Data {
        try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return Data()
            }
            return try decompress(bytes: baseAddress, count: rawBuffer.count, finish: finish)
        }
    }

    private func decompress(bytes: UnsafePointer<UInt8>, count: Int, finish: Bool) throws -> Data {
        var decompressed = Data()
        try runInflate(bytes: bytes, count: count, out: &decompressed)

        if finish {
            let tail: [UInt8] = [0x00, 0x00, 0xFF, 0xFF]
            try tail.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                try runInflate(bytes: baseAddress, count: rawBuffer.count, out: &decompressed)
            }
        }

        return decompressed
    }

    private func runInflate(bytes: UnsafePointer<UInt8>, count: Int, out: inout Data) throws {
        var result: CInt = 0
        strm.next_in = UnsafeMutablePointer<UInt8>(mutating: bytes)
        strm.avail_in = CUnsignedInt(count)

        repeat {
            buffer.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) in
                strm.next_out = bufferPtr.bindMemory(to: UInt8.self).baseAddress
                strm.avail_out = CUnsignedInt(bufferPtr.count)
                result = zlib.inflate(&strm, 0)
            }

            let byteCount = buffer.count - Int(strm.avail_out)
            out.append(buffer, count: byteCount)
        } while result == Z_OK && strm.avail_out == 0

        guard (result == Z_OK && strm.avail_out > 0)
            || (result == Z_BUF_ERROR && Int(strm.avail_out) == buffer.count)
        else {
            throw WSError(type: .compressionError, message: "Error on decompressing", code: 0)
        }
    }

    private func teardownInflate() {
        if inflateInitialized, Z_OK == zlib.inflateEnd(&strm) {
            inflateInitialized = false
        }
    }

    deinit {
        teardownInflate()
    }
}

private final class APWebSocketCompressor {
    private var strm = z_stream()
    private var buffer: [UInt8]
    private var deflateInitialized = false
    private let windowBits: Int

    init?(windowBits: Int, bufferSize: Int = 0x10000) {
        self.windowBits = windowBits
        self.buffer = [UInt8](repeating: 0, count: bufferSize)
        guard initDeflate() else { return nil }
    }

    private func initDeflate() -> Bool {
        if Z_OK == zlib.deflateInit2_(
            &strm,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -CInt(windowBits),
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            CInt(MemoryLayout<z_stream>.size)
        ) {
            deflateInitialized = true
            return true
        }
        return false
    }

    func reset() throws {
        teardownDeflate()
        guard initDeflate() else {
            throw WSError(type: .compressionError, message: "Error for compressor on reset", code: 0)
        }
    }

    func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return data }

        var compressed = Data()
        var result: CInt = 0
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            strm.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            strm.avail_in = CUnsignedInt(rawBuffer.count)

            repeat {
                buffer.withUnsafeMutableBytes { (bufferPtr: UnsafeMutableRawBufferPointer) in
                    strm.next_out = bufferPtr.bindMemory(to: UInt8.self).baseAddress
                    strm.avail_out = CUnsignedInt(bufferPtr.count)
                    result = zlib.deflate(&strm, Z_SYNC_FLUSH)
                }

                let byteCount = buffer.count - Int(strm.avail_out)
                compressed.append(buffer, count: byteCount)
            } while result == Z_OK && strm.avail_out == 0
        }

        guard result == Z_OK && strm.avail_out > 0
            || (result == Z_BUF_ERROR && Int(strm.avail_out) == buffer.count)
        else {
            throw WSError(type: .compressionError, message: "Error on compressing", code: 0)
        }

        compressed.removeLast(4)
        return compressed
    }

    private func teardownDeflate() {
        if deflateInitialized, Z_OK == zlib.deflateEnd(&strm) {
            deflateInitialized = false
        }
    }

    deinit {
        teardownDeflate()
    }
}
