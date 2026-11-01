import Foundation
import CoreFoundation
import Darwin

public enum FilenameEncoding: String, CaseIterable, Sendable {
    case korean, utf8, traditionalChinese, latin1
    public var label: String {
        switch self {
        case .korean: return "Korean (CP949)"
        case .utf8: return "Unicode (UTF-8)"
        case .traditionalChinese: return "Traditional Chinese (Big5)"
        case .latin1: return "Western (Latin-1)"
        }
    }
    public func decode(_ data: Data) throws -> String {
        let encoding: String.Encoding
        switch self {
        case .korean:
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        case .utf8: encoding = .utf8
        case .traditionalChinese:
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertWindowsCodepageToEncoding(950)))
        case .latin1: encoding = .isoLatin1
        }
        guard let string = String(data: data, encoding: encoding) else {
            throw GRFError.invalid("Cannot decode a filename using \(label). Choose another filename encoding and reopen.")
        }
        return string
    }
}

public struct GRFEntry: Identifiable, Hashable, Sendable {
    public static func listing(id: Int, path: String, size: Int, compressedSize: Int = 0) -> Self {
        Self(id: id, path: path, size: size, compressedSize: compressedSize, rawName: Data(path.utf8), storedSize: 0, position: 0, flags: 1)
    }
    public var name: String { (path as NSString).lastPathComponent }
    public let id: Int
    public let path: String
    public let size: Int
    public let compressedSize: Int
    public let rawName: Data
    let storedSize: Int
    let position: UInt64
    let flags: UInt8
}

public enum ExtractionFilenameMode: String, CaseIterable, Sendable {
    case unicode, originalBytes
    public var label: String { self == .unicode ? "Unicode (recommended)" : "Original bytes (UTF-8-compatible names only)" }
}

public struct GRFExtractionReport: Sendable {
    public struct Failure: Sendable {
        public let path: String
        public let reason: String
    }
    public let extractedCount: Int
    public let failures: [Failure]
}

/// Immutable index; each read uses an independent handle so preview and extraction can overlap.
public final class GRFArchive: @unchecked Sendable {
    public let url: URL
    public let entries: [GRFEntry]
    public let version: Int
    private let fileSize: UInt64
    private let identity: stat
    private let entriesByID: [Int: GRFEntry]
    public init(url: URL, encoding: FilenameEncoding = .korean,
                progress: @escaping @Sendable (GRFLoadProgress) -> Void = { _ in },
                cancelled: @escaping @Sendable () -> Bool = { false }) throws {
        self.url = url
        let reporter = LoadReporter(receive: progress, cancelled: cancelled)
        try reporter.report(.opening, force: true)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(handle.fileDescriptor, &metadata) == 0 else { throw GRFError.invalid("Cannot inspect archive metadata.") }
        identity = metadata
        fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard fileSize >= 46, let header = try handle.read(upToCount: 46), header.count == 46,
              header.prefix(15) == Data("Master of Magic".utf8) else {
            throw GRFError.invalid("This file is not a valid GRF/GPF archive.")
        }
        var reader = BinaryReader(header)
        reader.offset = 30
        let tablePosition = UInt64(try reader.u32()) + 46
        let seed = try reader.u32()
        let count = try reader.u32() - seed - 7
        version = try reader.u32()
        guard [0x100, 0x101, 0x102, 0x103, 0x200].contains(version) else {
            throw GRFError.invalid(String(format: "Unsupported GRF version 0x%X.", version))
        }
        guard count >= 0, count <= 2_000_000, tablePosition <= fileSize else {
            throw GRFError.invalid("Invalid GRF file count or file-table position.")
        }
        try handle.seek(toOffset: tablePosition)
        let table: Data
        if version == 0x200 {
            guard fileSize - tablePosition >= 8 else { throw GRFError.invalid("Missing GRF file table.") }
            guard let sizes = try handle.read(upToCount: 8), sizes.count == 8 else { throw GRFError.invalid("Missing GRF file table.") }
            var lengths = BinaryReader(sizes)
            let compressed = try lengths.u32(), expanded = try lengths.u32()
            guard compressed <= 256 * 1024 * 1024, UInt64(compressed) <= fileSize - tablePosition - 8 else {
                throw GRFError.invalid("Truncated or oversized GRF file table.")
            }
            let bytes = try reporter.readIndex(handle, count: compressed)
            table = try reporter.decompressIndex(bytes, expectedSize: expanded)
        } else {
            let length = fileSize - tablePosition
            guard length <= 256 * 1024 * 1024 else {
                throw GRFError.invalid("Truncated or oversized legacy GRF file table.")
            }
            table = try reporter.readIndex(handle, count: Int(length))
        }
        var index = BinaryReader(table)
        guard count <= table.count / (version == 0x200 ? 18 : 27) else {
            throw GRFError.invalid("The GRF file count exceeds its index size.")
        }
        var result: [GRFEntry] = []
        result.reserveCapacity(count)
        try reporter.report(.listingFiles, 0, count, force: true)
        for id in 0..<count {
            if id % 256 == 0 { try reporter.report(.listingFiles, id, count) }
            let name: Data
            if version == 0x200 {
                name = try index.terminatedName()
            } else {
                let length = try index.u32()
                guard length >= 6, length <= 264 else { throw GRFError.invalid("Invalid legacy GRF filename length.") }
                let encoded = try index.take(length)
                if version == 0x100 {
                    name = Data(encoded.prefix(while: { $0 != 0 }).map { ($0 << 4) | ($0 >> 4) })
                } else {
                    let swapped = Data(encoded[2..<(length - 4)].map { ($0 << 4) | ($0 >> 4) })
                    let decoded = try decrypt(swapped, flags: 2, compressedSize: swapped.count, filename: true)
                    name = Data(decoded.prefix(while: { $0 != 0 }))
                }
            }
            var compressed = try index.u32(), stored = try index.u32()
            let size = try index.u32()
            var flags = try index.u8()
            let position = UInt64(try index.u32()) + 46
            if version != 0x200 {
                compressed -= size + 715
                stored -= 37579
            }
            guard flags & 1 != 0 else { continue }
            let path = try encoding.decode(name).replacingOccurrences(of: "\\", with: "/")
            if version != 0x200 {
                flags |= ["gnd", "gat", "act", "str"].contains((path as NSString).pathExtension.lowercased()) ? 4 : 2
            }
            guard !path.isEmpty, compressed >= 0, stored >= compressed,
                  position <= fileSize, UInt64(stored) <= fileSize - position else {
                throw GRFError.invalid("Invalid data range for \(path).")
            }
            result.append(GRFEntry(id: id, path: path, size: size, compressedSize: compressed,
                                   rawName: name, storedSize: stored, position: position, flags: flags))
        }
        try reporter.report(.listingFiles, count, count, force: true)
        try reporter.report(.finishing, force: true)
        entries = result
        entriesByID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        try validate(handle)
        try reporter.report(.ready, force: true)
    }

    public func validateUnchanged() throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try validate(handle)
    }

    private func validate(_ handle: FileHandle) throws {
        var current = stat()
        guard fstat(handle.fileDescriptor, &current) == 0,
              current.st_dev == identity.st_dev, current.st_ino == identity.st_ino,
              current.st_size == identity.st_size,
              current.st_mtimespec.tv_sec == identity.st_mtimespec.tv_sec,
              current.st_mtimespec.tv_nsec == identity.st_mtimespec.tv_nsec else {
            throw GRFError.invalid("Archive changed on disk. Reopen it before continuing.")
        }
    }

    public func data(for entry: GRFEntry) throws -> Data {
        guard entriesByID[entry.id] == entry else { throw GRFError.invalid("The selected file does not belong to this archive.") }
        guard entry.size <= 512 * 1024 * 1024, entry.storedSize <= 512 * 1024 * 1024 else {
            throw GRFError.invalid("This file exceeds the 512 MiB per-file memory limit.")
        }
        if entry.size == 0 { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try validate(handle)
        guard try handle.seekToEnd() == fileSize else { throw GRFError.invalid("Archive changed on disk. Reopen it before continuing.") }
        try handle.seek(toOffset: entry.position)
        guard var bytes = try handle.read(upToCount: entry.storedSize), bytes.count == entry.storedSize else {
            throw GRFError.invalid("Truncated file data: \(entry.path).")
        }
        try validate(handle)
        if entry.flags & 6 != 0 { bytes = try decrypt(bytes, flags: entry.flags, compressedSize: entry.compressedSize) }
        let header = Array(bytes.prefix(2))
        guard header.count == 2, header[0] & 0x0f == 8, header[0] >> 4 <= 7,
              (Int(header[0]) * 256 + Int(header[1])) % 31 == 0 else {
            throw GRFError.unreadableResource(path: entry.path, reason: "The archive index is readable, but this resource is not standard zlib data after normal GRF decoding. It may use custom encryption or compression. Supply an unencrypted archive or the matching client decoder/key; changing the filename encoding will not fix this.")
        }
        do {
            return try inflate(Data(bytes.prefix(entry.compressedSize)), expectedSize: entry.size)
        } catch {
            throw GRFError.unreadableResource(path: entry.path, reason: error.localizedDescription)
        }
    }

    @discardableResult
    public func extract(entries selected: [GRFEntry], to destination: URL,
                        filenameMode: ExtractionFilenameMode = .unicode,
                        skipUnreadableFiles: Bool = false,
                        progress: @Sendable (Int, Int) -> Void = { _, _ in },
                        cancelled: @Sendable () -> Bool = { false }) throws -> GRFExtractionReport {
        // Work relative to directory descriptors, rejecting symlinks and existing files.
        // This also prevents archives escaping the destination through ../ or symlink races.
        let root = open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard root >= 0 else { throw GRFError.invalid("Cannot open the extraction folder.") }
        defer { close(root) }
        var paths = Set<Data>()
        for entry in selected {
            _ = try Self.safeComponents(entry.path)
            if filenameMode == .originalBytes && String(data: entry.rawName, encoding: .utf8) == nil {
                throw GRFError.invalid("macOS cannot create this original ANSI filename: \(entry.path). Choose Unicode extraction instead.")
            }
            let key = filenameMode == .unicode ? Data(entry.path.precomposedStringWithCanonicalMapping.lowercased().utf8) : entry.rawName
            guard paths.insert(key).inserted else {
                throw GRFError.invalid("Duplicate output filename: \(entry.path). Extract these files separately.")
            }
        }
        var failures: [GRFExtractionReport.Failure] = []
        progress(0, selected.count)
        for (i, entry) in selected.enumerated() {
            if cancelled() { throw GRFError.cancelled }
            let components: [Data]
            if filenameMode == .unicode {
                components = try Self.safeComponents(entry.path).map { Data($0.utf8) }
            } else {
                let rawPath = entry.rawName.map { $0 == 0x5c ? UInt8(0x2f) : $0 }
                components = rawPath.split(separator: 0x2f, omittingEmptySubsequences: false).map { Data($0) }
                guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && !$0.contains(0) && !$0.contains(0x3a) && $0 != Data([0x2e]) && $0 != Data([0x2e, 0x2e]) }) else {
                    throw GRFError.invalid("Unsafe original filename bytes: \(entry.path).")
                }
            }
            let bytes: Data
            do {
                bytes = try data(for: entry)
            } catch GRFError.unreadableResource(let path, let reason) where skipUnreadableFiles {
                if cancelled() { throw GRFError.cancelled }
                failures.append(.init(path: path, reason: reason))
                progress(i + 1, selected.count)
                continue
            }
            if cancelled() { throw GRFError.cancelled }
            var directory = dup(root)
            guard directory >= 0 else { throw GRFError.invalid("Cannot access extraction folder.") }
            defer { close(directory) }
            for component in components.dropLast() {
                if Self.withCName(component, { mkdirat(directory, $0, 0o755) }) != 0 && errno != EEXIST {
                    throw GRFError.invalid("Cannot create folder for \(entry.path).")
                }
                let next = Self.withCName(component) { openat(directory, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
                guard next >= 0 else { throw GRFError.invalid("Unsafe or inaccessible output folder for \(entry.path).") }
                close(directory)
                directory = next
            }
            let filename = components.last!
            let output = Self.withCName(filename) { openat(directory, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644) }
            guard output >= 0 else { throw GRFError.invalid("Cannot create \(entry.path). Existing files are never overwritten.") }
            var success = false
            defer {
                close(output)
                if !success { _ = Self.withCName(filename) { unlinkat(directory, $0, 0) } }
            }
            try bytes.withUnsafeBytes { raw in
                var written = 0
                while written < raw.count {
                    if cancelled() { throw GRFError.cancelled }
                    let amount = Darwin.write(output, raw.baseAddress!.advanced(by: written), min(1_048_576, raw.count - written))
                    if amount < 0 && errno == EINTR { continue }
                    guard amount > 0 else { throw GRFError.invalid("Failed to write \(entry.path).") }
                    written += amount
                }
            }
            success = true
            progress(i + 1, selected.count)
        }
        return GRFExtractionReport(extractedCount: selected.count - failures.count, failures: failures)
    }

    private static func withCName<T>(_ data: Data, _ body: (UnsafePointer<CChar>) -> T) -> T {
        (data + Data([0])).withUnsafeBytes { body($0.bindMemory(to: CChar.self).baseAddress!) }
    }

    static func safeComponents(_ path: String) throws -> [String] {
        let parts = path.components(separatedBy: "/")
        guard !path.contains("\0"), !path.contains(":"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw GRFError.invalid("Unsafe output path: \(path).")
        }
        return parts
    }
}
