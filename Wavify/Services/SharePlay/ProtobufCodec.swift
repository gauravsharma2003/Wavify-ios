//
//  ProtobufCodec.swift
//  Wavify
//
//  Encodes/decodes protobuf Envelope wire format with gzip compression.
//  Matches metroserver's Go codec behavior exactly.
//

import Foundation
import SwiftProtobuf
import zlib

nonisolated enum ProtobufCodec {

    private static let compressionThreshold = 100

    // MARK: - Encode

    static func encode(type: String, payload: (any SwiftProtobuf.Message)?) throws -> Data {
        var payloadBytes = Data()

        if let payload {
            payloadBytes = try payload.serializedData()
        }

        var compressed = false
        if payloadBytes.count > compressionThreshold {
            if let gzipped = gzipCompress(payloadBytes), gzipped.count < payloadBytes.count {
                payloadBytes = gzipped
                compressed = true
            }
        }

        var envelope = LT_Envelope()
        envelope.type = type
        envelope.payload = payloadBytes
        envelope.compressed = compressed
        return try envelope.serializedData()
    }

    // MARK: - Decode

    static func decode(data: Data) throws -> (type: String, payload: Data) {
        let envelope = try LT_Envelope(serializedData: data)
        var payloadBytes = envelope.payload

        if envelope.compressed {
            guard let decompressed = gzipDecompress(payloadBytes) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Failed to gzip decompress payload"))
            }
            payloadBytes = decompressed
        }

        return (envelope.type, payloadBytes)
    }

    // MARK: - Gzip (RFC 1952) using zlib

    private static func gzipCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // windowBits = 15 + 16 = 31 → gzip format
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        let bufferSize = deflateBound(&stream, UInt(data.count))
        var output = Data(count: Int(bufferSize))

        let result: Int32 = data.withUnsafeBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(data.count)
                stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(bufferSize)
                return deflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }

    private static func gzipDecompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // windowBits = 15 + 32 → auto-detect gzip/zlib
        guard inflateInit2_(&stream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: data.count * 4)
        let chunkSize = 16384
        var buffer = Data(count: chunkSize)

        data.withUnsafeBytes { inputPtr in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)

            repeat {
                buffer.withUnsafeMutableBytes { bufPtr in
                    stream.next_out = bufPtr.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(chunkSize)
                }

                let status = inflate(&stream, Z_NO_FLUSH)
                guard status == Z_OK || status == Z_STREAM_END else { return }

                let have = chunkSize - Int(stream.avail_out)
                output.append(buffer.prefix(have))

                if status == Z_STREAM_END { break }
            } while stream.avail_out == 0
        }

        return output.isEmpty ? nil : output
    }
}
