import Foundation
import Starscream
import zlib

/// Archipelago-compatible permessage-deflate handler.
///
/// Starscream compresses every outbound frame, including automatic pong replies to
/// server pings. RFC 7692 forbids compressing control frames; a strict server closes
/// the connection with protocol error 1002 when it receives a compressed pong.
///
/// This handler only decompresses inbound data frames and never compresses outbound
/// traffic, which Archipelago servers accept (RSV1 simply stays unset).
final class APWSCompression: CompressionHandler {
    private let headerWSExtensionName = "Sec-WebSocket-Extensions"
    private var decompressor: APWebSocketDecompressor?
    private var decompressorTakeOver = false

    /// RFC 7692 default when the server omits explicit window-bit parameters.
    private let fallbackWindowBits = 15

    init() {
        decompressor = APWebSocketDecompressor(windowBits: fallbackWindowBits)
    }

    func load(headers: [String: String]) {
        guard let extensionHeader = headers[headerWSExtensionName] else { return }
        decompressorTakeOver = false

        var serverWindowBits = fallbackWindowBits
        let parts = extensionHeader.components(separatedBy: ";")
        for part in parts {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("server_max_window_bits="),
               let value = Int(token.split(separator: "=").last ?? "") {
                serverWindowBits = value
            } else if token == "server_no_context_takeover" {
                decompressorTakeOver = true
            }
        }

        decompressor = APWebSocketDecompressor(windowBits: serverWindowBits)
    }

    func decompress(data: Data, isFinal: Bool) -> Data? {
        guard let decompressor else { return nil }
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

    func compress(data: Data) -> Data? {
        // Never compress outbound frames. Starscream uses this for text frames and
        // for automatic pong replies; only the latter is a protocol violation, but
        // sending all client traffic uncompressed is valid and avoids code 1002.
        nil
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
