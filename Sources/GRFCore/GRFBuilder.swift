import Foundation
import CoreFoundation
import Darwin
import CGRFCrypto

public struct GRFBuildFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let source: URL
    public let size: Int64
    let modified: Date?
    let sourceSize: Int64
    enum Origin: Sendable { case disk, archive(GRFArchive, GRFEntry) }
    let origin: Origin

    private init(path: String, source: URL, size: Int64, modified: Date?, sourceSize: Int64? = nil, origin: Origin = .disk) {
        self.path = path; self.source = source; self.size = size; self.modified = modified
        self.sourceSize = sourceSize ?? size; self.origin = origin
    }

    public var compressedSize: Int { if case .archive(_, let entry) = origin { return entry.compressedSize }; return 0 }
    public func renamed(to path: String) throws -> Self {
        try validateBuildPath(path)
        return Self(path: path.precomposedStringWithCanonicalMapping, source: source, size: size,
                    modified: modified, sourceSize: sourceSize, origin: origin)
    }
    public static func importingFile(_ url: URL, path: String? = nil) throws -> Self {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw GRFError.invalid("Choose a regular file, not a symbolic link.") }
        let path = path ?? url.lastPathComponent
        try validateBuildPath(path)
        let size = Int64(values.fileSize ?? 0)
        guard size <= 512 * 1024 * 1024 else { throw GRFError.invalid("Imported file exceeds 512 MiB.") }
        return Self(path: path, source: url.standardizedFileURL, size: size, modified: values.contentModificationDate)
    }
    public func data(limit: Int = 64 * 1024 * 1024) throws -> Data {
        guard size <= limit else { throw GRFError.invalid("Resource exceeds the \(limit / 1024 / 1024) MiB read limit.") }
        switch origin {
        case .archive(let archive, let entry): return try archive.data(for: entry)
        case .disk:
            let fd = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw GRFError.invalid("Cannot read \(path).") }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var before = stat()
            guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size == sourceSize else { throw GRFError.invalid("Source changed: \(path)") }
            var live = source; live.removeAllCachedResourceValues()
            guard try live.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified else { throw GRFError.invalid("Source changed: \(path)") }
            let bytes = try handle.read(upToCount: limit + 1) ?? Data()
            var after = stat()
            guard bytes.count == size, fstat(fd, &after) == 0, before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw GRFError.invalid("Source changed while reading: \(path)") }
            return bytes
        }
    }

    public static func fromArchive(_ archive: GRFArchive, validatingPaths: Bool = true, cancelled: () -> Bool = { false }) throws -> [GRFBuildFile] {
        try archive.validateUnchanged()
        var url = archive.url.resolvingSymlinksInPath()
        url.removeAllCachedResourceValues()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let files = try archive.entries.map { entry -> GRFBuildFile in
            if cancelled() { throw GRFBuildError.cancelled }
            if validatingPaths { try validateBuildPath(entry.path) }
            return GRFBuildFile(path: entry.path.precomposedStringWithCanonicalMapping, source: url,
                                size: Int64(entry.size), modified: values.contentModificationDate,
                                sourceSize: Int64(values.fileSize ?? 0), origin: .archive(archive, entry))
        }
        return validatingPaths ? try combining([], with: files) : files.sorted { $0.path < $1.path }
    }

    public static func removing(_ files: [GRFBuildFile], paths: Set<String>) -> [GRFBuildFile] {
        let keys = Set(paths.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        return files.filter { !keys.contains($0.path.precomposedStringWithCanonicalMapping.lowercased()) }
    }

    public static func merging(_ existing: [GRFBuildFile], with added: [GRFBuildFile], policy: GRFMergePolicy) throws -> [GRFBuildFile] {
        _ = try combining([], with: existing)
        _ = try combining([], with: added)
        var result = Dictionary(uniqueKeysWithValues: existing.map { ($0.path.precomposedStringWithCanonicalMapping.lowercased(), $0) })
        for file in added {
            let key = file.path.precomposedStringWithCanonicalMapping.lowercased()
            if result[key] != nil {
                switch policy {
                case .keepExisting: continue
                case .replaceExisting: break
                case .reject: throw GRFError.invalid("Duplicate archive path: \(file.path). Nothing was imported.")
                }
            }
            result[key] = file
        }
        guard result.count <= 2_000_000 else { throw GRFError.invalid("Too many files to build a GRF.") }
        return result.values.sorted { $0.path < $1.path }
    }

    /// Keeps the selected folder itself: choosing `data` imports `data/...`.
    public static func importing(_ folder: URL, cancelled: () -> Bool = { false }) throws -> [GRFBuildFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let selected = folder.standardizedFileURL
        let attributes = try selected.resourceValues(forKeys: keys)
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            throw GRFError.invalid("Choose a real folder, not a symbolic link.")
        }
        let root = selected.resolvingSymlinksInPath()
        var enumerationError: Error?
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, error in enumerationError = error; return false }) else {
            throw GRFError.invalid("Could not read the selected folder.")
        }
        var files: [GRFBuildFile] = []
        for case let url as URL in iterator {
            if cancelled() { throw GRFBuildError.cancelled }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw GRFError.invalid("Symbolic links cannot be imported: \(url.lastPathComponent)") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw GRFError.invalid("Only regular files can be imported: \(url.lastPathComponent)") }
            let relative = url.pathComponents.suffix(iterator.level).joined(separator: "/")
            let path = (root.lastPathComponent + "/" + relative).precomposedStringWithCanonicalMapping
            try validateBuildPath(path)
            let size = Int64(values.fileSize ?? 0)
            guard size <= 512 * 1024 * 1024 else { throw GRFError.invalid("File exceeds the 512 MiB supported resource limit: \(path)") }
            files.append(GRFBuildFile(path: path, source: url, size: size, modified: values.contentModificationDate))
            guard files.count <= 2_000_000 else { throw GRFError.invalid("Too many files to build a GRF.") }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { $0.path < $1.path }
    }

    /// Import is transactional: duplicate game paths never silently overwrite a staged file.
    public static func combining(_ existing: [GRFBuildFile], with added: [GRFBuildFile]) throws -> [GRFBuildFile] {
        var names = Set<String>()
        for file in existing + added {
            let key = file.path.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(key).inserted else { throw GRFError.invalid("Duplicate archive path: \(file.path). Nothing was imported.") }
        }
        return (existing + added).sorted { $0.path < $1.path }
    }
}

public enum GRFMergePolicy: String, CaseIterable, Sendable {
    case keepExisting, replaceExisting, reject
    public var label: String {
        switch self {
        case .keepExisting: return "Keep existing"
        case .replaceExisting: return "Replace with imported"
        case .reject: return "Reject duplicates"
        }
    }
}

public enum GRFBuildError: LocalizedError {
    case cancelled
    public var errorDescription: String? { "Building cancelled. No output archive was changed." }
}

public struct GRFBuildProgress: Sendable {
    public let fraction: Double
    public let detail: String
}

public enum GRFBuilder {
    /// Builds a standard, unencrypted GRF 2.0 using bounded streaming compression.
    /// Publishes only after completion; cancellation/errors remove the temporary sibling.
    public static func write(_ files: [GRFBuildFile], to destination: URL, encoding: FilenameEncoding = .korean,
                             overwrite: Bool = false, compressionLevel: Int = -1,
                             progress: @escaping @Sendable (GRFBuildProgress) -> Void = { _ in },
                             cancelled: @escaping @Sendable () -> Bool = { false }) throws {
        guard (-1...9).contains(compressionLevel) else { throw GRFError.invalid("Compression level must be Default (-1) or 0–9.") }
        guard files.count <= 2_000_000 else { throw GRFError.invalid("Too many files to build a GRF.") }
        _ = try GRFBuildFile.combining([], with: files)
        let names = try files.map { file -> Data in
            try validateBuildPath(file.path)
            guard file.source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
                throw GRFError.invalid("The output archive cannot replace an imported source file.")
            }
            return try encodedBuildName(file.path, encoding: encoding)
        }
        if !overwrite && FileManager.default.fileExists(atPath: destination.path) { throw GRFError.invalid("The output file already exists.") }
        var template = Array(destination.deletingLastPathComponent().appendingPathComponent(".grf-build-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = URL(fileURLWithPath: String(cString: template))
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        func check() throws { if cancelled() { throw GRFBuildError.cancelled } }
        try check()
        try output.write(contentsOf: Data(count: 46))
        var table = Data()
        let total = max(1, files.reduce(Int64(0)) { $0 + $1.size })
        var completed: Int64 = 0
        var lastUpdate = Date.distantPast
        for (index, file) in files.enumerated() {
            try check()
            let inputFD = Darwin.open(file.source.path, O_RDONLY | O_NOFOLLOW)
            guard inputFD >= 0 else { throw GRFError.invalid("Cannot open imported file: \(file.path)") }
            let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
            defer { try? input.close() }
            var before = stat()
            guard fstat(inputFD, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
                  before.st_size == file.sourceSize, file.size >= 0, file.size <= 512 * 1024 * 1024 else {
                throw GRFError.invalid("Imported file changed. Create a new draft and import it again: \(file.path)")
            }
            var liveSource = file.source
            liveSource.removeAllCachedResourceValues()
            let values = try liveSource.resourceValues(forKeys: [.contentModificationDateKey])
            guard values.contentModificationDate == file.modified else { throw GRFError.invalid("Imported file changed: \(file.path)") }
            let position = try output.offset() - 46
            var read: Int64 = 0
            let readChunk: () throws -> Data
            switch file.origin {
            case .disk: readChunk = { try input.read(upToCount: 64 * 1024) ?? Data() }
            case .archive(let archive, let entry):
                let payload = try archive.data(for: entry)
                try check()
                var offset = 0
                readChunk = {
                    let end = min(payload.count, offset + 64 * 1024)
                    defer { offset = end }
                    return payload.subdata(in: offset..<end)
                }
            }
            let compressed = try compressStream(readChunk: readChunk, output: output, level: Int32(compressionLevel), check: check) { bytes in
                read += Int64(bytes)
                guard read <= file.size else { throw GRFError.invalid("Imported file grew while packing: \(file.path)") }
                if Date().timeIntervalSince(lastUpdate) >= 0.04 {
                    lastUpdate = Date()
                    progress(GRFBuildProgress(fraction: min(0.94, Double(completed + read) / Double(total) * 0.94), detail: "Packing \(index + 1)/\(files.count) · \(file.path)"))
                }
            }
            guard compressed <= 512 * 1024 * 1024 else { throw GRFError.invalid("Compressed resource exceeds the supported 512 MiB limit: \(file.path)") }
            var after = stat()
            guard read == file.size, fstat(inputFD, &after) == 0,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_size == after.st_size else { throw GRFError.invalid("Imported file changed while packing: \(file.path)") }
            completed += file.size
            table += names[index]; table.append(0)
            try table.appendBuild32(compressed); try table.appendBuild32(compressed)
            try table.appendBuild32(UInt64(file.size)); table.append(1); try table.appendBuild32(position)
            guard table.count <= 256 * 1024 * 1024, try output.offset() <= UInt64(UInt32.max) else { throw GRFError.invalid("The archive exceeds the supported GRF 2.0 size limit (4 GiB).") }
        }
        try check()
        progress(GRFBuildProgress(fraction: 0.95, detail: "Writing file index…"))
        let tablePosition = try output.offset() - 46
        var compressedLength = compressBound(uLong(table.count))
        var compressedTable = Data(count: Int(compressedLength))
        let result = compressedTable.withUnsafeMutableBytes { dest in
            table.withUnsafeBytes { source in
                compress2(dest.bindMemory(to: UInt8.self).baseAddress!, &compressedLength, source.bindMemory(to: UInt8.self).baseAddress, uLong(table.count), Int32(compressionLevel))
            }
        }
        guard result == Z_OK else { throw GRFError.invalid("Could not compress the GRF file index.") }
        compressedTable.count = Int(compressedLength)
        guard compressedTable.count <= 256 * 1024 * 1024 else { throw GRFError.invalid("Compressed index exceeds the supported 256 MiB limit.") }
        var sizes = Data(); try sizes.appendBuild32(UInt64(compressedTable.count)); try sizes.appendBuild32(UInt64(table.count))
        try output.write(contentsOf: sizes); try output.write(contentsOf: compressedTable)
        guard try output.offset() <= UInt64(UInt32.max) else { throw GRFError.invalid("The archive exceeds the supported 4 GiB size limit.") }
        var header = Data("Master of Magic".utf8); header.append(0)
        header += Data(0..<14)
        try header.appendBuild32(tablePosition); try header.appendBuild32(0)
        try header.appendBuild32(UInt64(files.count + 7)); try header.appendBuild32(0x200)
        try output.seek(toOffset: 0); try output.write(contentsOf: header)
        try output.synchronize(); try output.close()
        try check()
        // renamex_np with RENAME_EXCL also protects against a destination appearing during the build.
        let published = overwrite ? rename(temporary.path, destination.path) : renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL))
        guard published == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        progress(GRFBuildProgress(fraction: 1, detail: "Saved \(files.count) files."))
    }

    private static func compressStream(readChunk: () throws -> Data, output: FileHandle, level: Int32, check: () throws -> Void,
                                       consumed: (Int) throws -> Void) throws -> UInt64 {
        var stream = z_stream()
        guard deflateInit_(&stream, level, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw GRFError.invalid("Could not start GRF compression.")
        }
        defer { deflateEnd(&stream) }
        var written: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try check()
            let chunk = try readChunk()
            let finishing = chunk.isEmpty
            try chunk.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                stream.avail_in = uInt(chunk.count)
                repeat {
                    try check()
                    let status = buffer.withUnsafeMutableBufferPointer { target -> Int32 in
                        stream.next_out = target.baseAddress; stream.avail_out = uInt(target.count)
                        return deflate(&stream, finishing ? Z_FINISH : Z_NO_FLUSH)
                    }
                    guard status == Z_OK || status == Z_STREAM_END else { throw GRFError.invalid("Could not compress an imported file.") }
                    let count = buffer.count - Int(stream.avail_out)
                    try output.write(contentsOf: Data(buffer.prefix(count))); written += UInt64(count)
                    if status == Z_STREAM_END { break }
                } while stream.avail_in > 0 || stream.avail_out == 0 || finishing
            }
            try consumed(chunk.count)
            if finishing { return written }
        }
    }
}

private func validateBuildPath(_ path: String) throws {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty, !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
          parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw GRFError.invalid("This path cannot be stored in a game archive: \(path)")
    }
}

private func encodedBuildName(_ path: String, encoding: FilenameEncoding) throws -> Data {
    let value = path.replacingOccurrences(of: "/", with: "\\")
    let native: String.Encoding
    switch encoding {
    case .korean: native = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
    case .traditionalChinese: native = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertWindowsCodepageToEncoding(950)))
    case .utf8: native = .utf8
    case .latin1: native = .isoLatin1
    }
    guard let bytes = value.data(using: native, allowLossyConversion: false), bytes.count < 256,
          try encoding.decode(bytes) == value else { throw GRFError.invalid("Filename cannot be represented in \(encoding.label), or is over 255 bytes: \(path)") }
    return bytes
}

private extension Data {
    mutating func appendBuild32(_ value: UInt64) throws {
        guard value <= UInt32.max else { throw GRFError.invalid("GRF 2.0 has a 32-bit size/offset limit.") }
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}
