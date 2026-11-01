import Foundation
import CGRFCrypto

public enum GRFError: LocalizedError {
    case invalid(String)
    case cancelled
    case loadingCancelled
    case unreadableResource(path: String, reason: String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unreadableResource(let path, let reason): return "Cannot read \(path): \(reason)"
        case .cancelled: return "Extraction cancelled. Files already extracted are kept."
        case .loadingCancelled: return "Archive loading cancelled."
        }
    }
}

struct BinaryReader {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    var remaining: Int { bytes.count - offset }
    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else { throw GRFError.invalid("Truncated or invalid binary data.") }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }
    mutating func u8() throws -> UInt8 { try take(1)[0] }
    mutating func u16() throws -> Int {
        let b = try take(2)
        return Int(b[0]) | Int(b[1]) << 8
    }
    mutating func u32() throws -> Int {
        let b = try take(4)
        return Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
    }
    mutating func terminatedName() throws -> Data {
        guard let end = bytes[offset...].firstIndex(of: 0), end - offset < 256 else {
            throw GRFError.invalid("Invalid GRF filename.")
        }
        let result = Data(try take(end - offset))
        _ = try u8()
        return result
    }
}

func inflate(_ data: Data, expectedSize: Int, limit: Int = 512 * 1024 * 1024) throws -> Data {
    guard expectedSize >= 0, expectedSize <= limit, !data.isEmpty else {
        throw GRFError.invalid("Compressed data exceeds the supported size limit or is empty.")
    }
    var output = Data(count: max(1, expectedSize))
    var actual = uLongf(output.count)
    let status = output.withUnsafeMutableBytes { dest in
        data.withUnsafeBytes { source in
            uncompress(dest.bindMemory(to: UInt8.self).baseAddress!, &actual,
                       source.bindMemory(to: UInt8.self).baseAddress!, uLong(data.count))
        }
    }
    guard status == Z_OK, actual == expectedSize else {
        throw GRFError.invalid("Invalid compressed data or incorrect uncompressed size (zlib \(status)).")
    }
    output.count = expectedSize
    return output
}

func decrypt(_ data: Data, flags: UInt8, compressedSize: Int, filename: Bool = false) throws -> Data {
    guard data.count % 8 == 0 else { throw GRFError.invalid("Encrypted GRF data must contain complete 8-byte blocks.") }
    if data.isEmpty { return data }
    var output = Data(count: data.count)
    let schedule = [CChar](repeating: 0, count: 128)
    output.withUnsafeMutableBytes { dest in
        data.withUnsafeBytes { source in
            schedule.withUnsafeBufferPointer { key in
                if filename {
                    _ = GRF_MixedProcess(dest.bindMemory(to: CChar.self).baseAddress!, source.bindMemory(to: CChar.self).baseAddress!,
                                         UInt32(data.count), 1, key.baseAddress!, 1)
                } else {
                    _ = GRF_Process(dest.bindMemory(to: CChar.self).baseAddress!, source.bindMemory(to: CChar.self).baseAddress!,
                                    UInt32(data.count), flags, UInt32(compressedSize), key.baseAddress!, 1)
                }
            }
        }
    }
    return output
}
