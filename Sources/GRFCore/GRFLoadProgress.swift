import Foundation
import CGRFCrypto

public struct GRFLoadProgress: Sendable {
    public enum Stage: String, Sendable {
        case opening = "Opening archive"
        case readingIndex = "Reading file index"
        case decompressingIndex = "Decompressing file index"
        case listingFiles = "Listing files"
        case finishing = "Finishing index"
        case ready = "Index ready"
    }
    public let stage: Stage
    public let completed: Int
    public let total: Int
    public var fraction: Double {
        let part = total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
        switch stage {
        case .opening: return 0
        case .readingIndex: return 0.02 + part * 0.23
        case .decompressingIndex: return 0.25 + part * 0.25
        case .listingFiles: return 0.5 + part * 0.45
        case .finishing: return 0.97
        case .ready: return 1
        }
    }
    public var detail: String {
        switch stage {
        case .readingIndex, .decompressingIndex:
            return "\(stage.rawValue) · \(ByteCountFormatter.string(fromByteCount: Int64(completed), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))"
        case .listingFiles: return "\(stage.rawValue) · \(completed.formatted()) / \(total.formatted())"
        default: return stage.rawValue
        }
    }
}

final class LoadReporter {
    private let receive: @Sendable (GRFLoadProgress) -> Void
    private let cancelled: @Sendable () -> Bool
    private var previousStage: GRFLoadProgress.Stage?
    private var previousTime = ContinuousClock.now
    init(receive: @escaping @Sendable (GRFLoadProgress) -> Void, cancelled: @escaping @Sendable () -> Bool) {
        self.receive = receive; self.cancelled = cancelled
    }
    func checkCancellation() throws {
        if cancelled() { throw GRFError.loadingCancelled }
    }
    func report(_ stage: GRFLoadProgress.Stage, _ completed: Int = 0, _ total: Int = 0, force: Bool = false) throws {
        try checkCancellation()
        let now = ContinuousClock.now
        guard force || stage != previousStage || now - previousTime >= .milliseconds(40) else { return }
        previousStage = stage; previousTime = now
        receive(GRFLoadProgress(stage: stage, completed: completed, total: total))
    }
    func readIndex(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        try report(.readingIndex, 0, count, force: true)
        while data.count < count {
            try checkCancellation()
            guard let chunk = try handle.read(upToCount: min(1_048_576, count - data.count)), !chunk.isEmpty else {
                throw GRFError.invalid("Truncated GRF file index.")
            }
            data.append(chunk)
            try report(.readingIndex, data.count, count, force: data.count == count)
        }
        return data
    }

    func decompressIndex(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0, expectedSize <= 256 * 1024 * 1024, !data.isEmpty else {
            throw GRFError.invalid("Invalid or oversized GRF file index.")
        }
        var stream = z_stream()
        guard inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw GRFError.invalid("Could not initialize index decompression.")
        }
        defer { inflateEnd(&stream) }
        // One spare byte permits checksum processing even when the expected output is full.
        var output = Data(count: expectedSize + 1)
        let capacity = output.count
        try report(.decompressingIndex, 0, data.count, force: true)
        try data.withUnsafeBytes { source in
            try output.withUnsafeMutableBytes { destination in
                stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress!
                stream.avail_out = uInt(capacity)
                var supplied = 0
                while true {
                    try checkCancellation()
                    if stream.avail_in == 0, supplied < data.count {
                        let size = min(65536, data.count - supplied)
                        stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress!.advanced(by: supplied))
                        stream.avail_in = uInt(size)
                        supplied += size
                    }
                    let beforeInput = stream.total_in, beforeOutput = stream.total_out
                    let status = CGRFCrypto.inflate(&stream, Z_NO_FLUSH)
                    guard stream.total_out <= expectedSize else { throw GRFError.invalid("GRF index expands beyond its declared size.") }
                    try report(.decompressingIndex, Int(stream.total_in), data.count, force: status == Z_STREAM_END)
                    if status == Z_STREAM_END { break }
                    guard status == Z_OK,
                          stream.total_in != beforeInput || stream.total_out != beforeOutput else {
                        throw GRFError.invalid("Invalid compressed GRF file index (zlib \(status)).")
                    }
                }
            }
        }
        guard stream.total_out == expectedSize else { throw GRFError.invalid("Incorrect uncompressed GRF index size.") }
        output.count = expectedSize
        return output
    }
}
