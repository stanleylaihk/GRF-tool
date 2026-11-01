import Testing
import Foundation
import Darwin
import CGRFCrypto
@testable import GRFCore

final class GRFCoreTests {
    private var temporary: URL!

    init() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GRFToolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: temporary)
    }

    private func archive(_ files: [FixtureFile], version: Int = 0x200) throws -> GRFArchive {
        let url = temporary.appendingPathComponent("\(UUID().uuidString).grf")
        try fixture(files, version: version).write(to: url)
        return try GRFArchive(url: url, encoding: .utf8)
    }

    private func outputFolder() throws -> URL {
        let url = temporary.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testV2ListsReadsAndExtractsNestedFilesAndEmptyFile() throws {
        let payload = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) })
        let grf = try archive([.init("data\\example.bin", payload), .init("data/empty.txt", Data())])
        expectEqual(grf.version, 0x200)
        expectEqual(grf.entries.map(\.path), ["data/example.bin", "data/empty.txt"])
        expectEqual(try grf.data(for: grf.entries[0]), payload)
        expectEqual(try grf.data(for: grf.entries[1]), Data())
        let folder = try outputFolder()
        let progress = ProgressRecorder()
        try grf.extract(entries: grf.entries, to: folder, progress: { progress.add($0, $1) })
        expectEqual(try Data(contentsOf: folder.appendingPathComponent("data/example.bin")), payload)
        expectEqual(try Data(contentsOf: folder.appendingPathComponent("data/empty.txt")), Data())
        expectEqual(progress.values.map { $0.0 }, [0, 1, 2])
        expectEqual(progress.values.map { $0.1 }, [2, 2, 2])
    }

    @Test func bulkExtractionReportsCorruptResourceAndContinuesWithLaterFiles() throws {
        let before = Data("before".utf8), broken = Data("checksum protected".utf8), after = Data("after".utf8)
        var bytes = try fixture([.init("before.txt", before), .init("broken.txt", broken), .init("after.txt", after)])
        let checksumByte = 46 + (try zlib(before)).count + (try zlib(broken)).count - 1
        bytes[checksumByte] ^= 1
        let url = temporary.appendingPathComponent("corrupt.grf")
        try bytes.write(to: url)
        let grf = try GRFArchive(url: url, encoding: .utf8)
        let strict = try outputFolder()
        #expect(throws: GRFError.self) { try grf.extract(entries: grf.entries, to: strict) }
        #expect(!FileManager.default.fileExists(atPath: strict.appendingPathComponent("after.txt").path))
        let folder = try outputFolder()
        let progress = ProgressRecorder()
        let report = try grf.extract(entries: grf.entries, to: folder, skipUnreadableFiles: true, progress: { progress.add($0, $1) })
        #expect(report.extractedCount == 2)
        #expect(report.failures.map(\.path) == ["broken.txt"])
        #expect(report.failures.first?.reason.contains("zlib") == true)
        #expect(try Data(contentsOf: folder.appendingPathComponent("before.txt")) == before)
        #expect(try Data(contentsOf: folder.appendingPathComponent("after.txt")) == after)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("broken.txt").path))
        #expect(progress.values.map { $0.0 } == [0, 1, 2, 3])
        let unsafe = try archive([.init("../escape.txt", before)])
        #expect(throws: GRFError.self) { try unsafe.extract(entries: unsafe.entries, to: folder, skipUnreadableFiles: true) }
        #expect(throws: GRFError.self) { try grf.extract(entries: grf.entries, to: folder, skipUnreadableFiles: true) }
        do {
            _ = try grf.extract(entries: grf.entries, to: folder, skipUnreadableFiles: true, cancelled: { true })
            Issue.record("Cancellation must stop bulk extraction.")
        } catch GRFError.cancelled {}
    }

    @Test func testEmptyArchiveIsValid() throws {
        let grf = try archive([])
        expectTrue(grf.entries.isEmpty)
    }

    @Test func testCP949FilenameAndOriginalBytesArePreserved() throws {
        let raw = Data([0xB0, 0xA1]) + Data(".txt".utf8)
        let url = temporary.appendingPathComponent("korean.grf")
        try fixture([FixtureFile(rawName: raw, data: Data("Korean filename".utf8), flags: 1)]).write(to: url)
        let grf = try GRFArchive(url: url, encoding: .korean)
        expectEqual(grf.entries.first?.path, "가.txt")
        expectEqual(grf.entries.first?.rawName, raw)
        expectThrowsError(try GRFArchive(url: url, encoding: .utf8))
    }

    @Test func testOriginalFilenameModeRejectsCP949BeforeWritingAndAcceptsASCII() throws {
        let raw = Data([0xB0, 0xA1]) + Data(".txt".utf8)
        let payload = Data("original encoded filename".utf8)
        let url = temporary.appendingPathComponent("korean-raw.grf")
        try fixture([FixtureFile(rawName: raw, data: payload, flags: 1)]).write(to: url)
        let grf = try GRFArchive(url: url, encoding: .korean)
        let folder = try outputFolder()
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder, filenameMode: .originalBytes))
        expectTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        let ascii = try archive([.init("data/ascii.txt", payload)])
        try ascii.extract(entries: ascii.entries, to: folder, filenameMode: .originalBytes)
        expectEqual(try Data(contentsOf: folder.appendingPathComponent("data/ascii.txt")), payload)
    }

    @Test func testInvalidSignatureUnsupportedVersionAndTruncatedTableThrow() throws {
        var invalid = try fixture([.init("a.txt", Data("test".utf8))])
        invalid[0] = 0
        let url = temporary.appendingPathComponent("invalid.grf")
        try invalid.write(to: url)
        expectThrowsError(try GRFArchive(url: url))
        invalid = try fixture([], version: 0x300)
        try invalid.write(to: url)
        expectThrowsError(try GRFArchive(url: url))
        invalid = try fixture([.init("a.txt", Data("test".utf8))])
        invalid.removeLast(3)
        try invalid.write(to: url)
        expectThrowsError(try GRFArchive(url: url))
    }

    @Test func testCorruptContentZlibIsRejectedRatherThanExported() throws {
        var bytes = try fixture([.init("a.txt", Data("test payload".utf8))])
        bytes[46] ^= 0xff
        let url = temporary.appendingPathComponent("corrupt.grf")
        try bytes.write(to: url)
        let grf = try GRFArchive(url: url)
        expectThrowsError(try grf.data(for: grf.entries[0]))
        let folder = try outputFolder()
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder))
        expectFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("a.txt").path))
    }

    @Test func testCorruptTableZlibAndMissingTableAreRejected() throws {
        var bytes = try fixture([])
        bytes[54] ^= 0xff
        let url = temporary.appendingPathComponent("bad-table.grf")
        try bytes.write(to: url)
        expectThrowsError(try GRFArchive(url: url))
        try bytes.prefix(46).write(to: url)
        expectThrowsError(try GRFArchive(url: url))
    }

    @Test func testTraversalAndAbsolutePathsAreRejectedBeforeCreatingFiles() throws {
        for path in ["../escape.txt", "/absolute.txt", "data/../../escape.txt", "C:/escape.txt", "data//bad.txt", "./bad.txt"] {
            let grf = try archive([.init(path, Data("escape".utf8))])
            let folder = try outputFolder()
            expectThrowsError(try grf.extract(entries: grf.entries, to: folder), path)
            expectTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }

    @Test func testSymlinkDirectoryCannotEscapeExtractionRoot() throws {
        let grf = try archive([.init("linked/escape.txt", Data("escape".utf8))])
        let folder = try outputFolder(), outside = try outputFolder()
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked"), withDestinationURL: outside)
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder))
        expectTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func testExistingFilesAndSymlinkFilesAreNeverOverwritten() throws {
        let grf = try archive([.init("existing.txt", Data("replacement".utf8))])
        let folder = try outputFolder()
        let existing = folder.appendingPathComponent("existing.txt")
        let original = Data("original".utf8)
        try original.write(to: existing)
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder))
        expectEqual(try Data(contentsOf: existing), original)
        try FileManager.default.removeItem(at: existing)
        let outside = temporary.appendingPathComponent("outside.txt")
        try original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: existing, withDestinationURL: outside)
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder))
        expectEqual(try Data(contentsOf: outside), original)
    }

    @Test func testCaseCollidingNamesAreRejectedBeforeAnyOutput() throws {
        let grf = try archive([.init("data/A.txt", Data([1])), .init("data/a.txt", Data([2]))])
        let folder = try outputFolder()
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder))
        expectTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func testCancellationStopsExtractionAndKeepsCompletedFiles() throws {
        let grf = try archive([.init("first.txt", Data([1])), .init("second.txt", Data([2]))])
        let folder = try outputFolder(), progress = ProgressRecorder()
        expectThrowsError(try grf.extract(entries: grf.entries, to: folder,
                                             progress: { progress.add($0, $1) }, cancelled: { progress.completed >= 1 })) {
            guard case GRFError.cancelled = $0 else { return recordFailure("Expected cancellation, got \($0)") }
        }
        expectEqual(try Data(contentsOf: folder.appendingPathComponent("first.txt")), Data([1]))
        expectFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("second.txt").path))
    }

    @Test func testArchiveSizeChangeAndForeignEntryAreRejected() throws {
        let grf = try archive([.init("a.txt", Data([1]))])
        let other = try archive([.init("b.txt", Data([2]))])
        expectThrowsError(try grf.data(for: other.entries[0]))
        let handle = try FileHandle(forWritingTo: grf.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        expectThrowsError(try grf.data(for: grf.entries[0]))
    }

    @Test func testHeaderAndMixedEncryptedV2EntriesRoundTrip() throws {
        let payload = Data((0..<16000).map { UInt8(truncatingIfNeeded: ($0 * 17) ^ ($0 >> 3)) })
        for flag: UInt8 in [3, 5] {
            let grf = try archive([FixtureFile(rawName: Data("encrypted.bin".utf8), data: payload, flags: flag)])
            expectEqual(try grf.data(for: grf.entries[0]), payload)
        }
    }

    @Test func testLegacy102EncryptedFilenameAndDataAreReadable() throws {
        let payload = Data("legacy data".utf8)
        let grf = try archive([.init("legacy.txt", payload)], version: 0x102)
        expectEqual(grf.version, 0x102)
        expectEqual(grf.entries.first?.path, "legacy.txt")
        expectEqual(try grf.data(for: grf.entries[0]), payload)
    }

    private struct FixtureFile {
        let rawName: Data
        let data: Data
        let flags: UInt8
        init(_ name: String, _ data: Data) { rawName = Data(name.utf8); self.data = data; flags = 1 }
        init(rawName: Data, data: Data, flags: UInt8) { self.rawName = rawName; self.data = data; self.flags = flags }
    }

    private func fixture(_ files: [FixtureFile], version: Int = 0x200) throws -> Data {
        var content = Data(), table = Data()
        for file in files {
            let compressed = try zlib(file.data)
            let flags: UInt8 = version == 0x102 ? 3 : file.flags
            var stored = compressed
            if flags & 6 != 0 {
                stored.append(Data(repeating: 0, count: (8 - stored.count % 8) % 8))
                stored = crypt(stored, flags: flags, compressedSize: compressed.count)
            }
            if version == 0x102 {
                var name = file.rawName + Data([0])
                name.append(Data(repeating: 0, count: (8 - name.count % 8) % 8))
                name = crypt(name, flags: 2, compressedSize: name.count, filename: true)
                name = Data(name.map { ($0 << 4) | ($0 >> 4) })
                table.appendLE(name.count + 6)
                table.append(contentsOf: [0, 0])
                table.append(name)
                table.append(contentsOf: [0, 0, 0, 0])
                table.appendLE(compressed.count + file.data.count + 715)
                table.appendLE(stored.count + 37579)
            } else {
                table.append(file.rawName)
                table.append(0)
                table.appendLE(compressed.count)
                table.appendLE(stored.count)
            }
            table.appendLE(file.data.count)
            table.append(flags)
            table.appendLE(content.count)
            content.append(stored)
        }
        var header = Data("Master of Magic".utf8)
        header.append(contentsOf: (0..<15).map { UInt8($0) })
        header.appendLE(content.count)
        header.appendLE(0)
        header.appendLE(files.count + 7)
        header.appendLE(version)
        if version == 0x102 { return header + content + table }
        let packedTable = try zlib(table)
        var lengths = Data()
        lengths.appendLE(packedTable.count)
        lengths.appendLE(table.count)
        return header + content + lengths + packedTable
    }

    private func zlib(_ data: Data) throws -> Data {
        var size = compressBound(uLong(data.count))
        var out = Data(count: Int(size))
        // zlib accepts zero-length input; keep a non-null address for it.
        let input = data.isEmpty ? Data([0]) : data
        let status = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compress(dst.bindMemory(to: UInt8.self).baseAddress!, &size,
                         src.bindMemory(to: UInt8.self).baseAddress!, uLong(data.count))
            }
        }
        guard status == Z_OK else { throw GRFError.invalid("Fixture compression failed") }
        out.count = Int(size)
        return out
    }

    private func crypt(_ data: Data, flags: UInt8, compressedSize: Int, filename: Bool = false) -> Data {
        var out = Data(count: data.count)
        let schedule = [CChar](repeating: 0, count: 128)
        out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                schedule.withUnsafeBufferPointer { key in
                    if filename {
                        _ = GRF_MixedProcess(dst.bindMemory(to: CChar.self).baseAddress!, src.bindMemory(to: CChar.self).baseAddress!,
                                             UInt32(data.count), 1, key.baseAddress!, 0)
                    } else {
                        _ = GRF_Process(dst.bindMemory(to: CChar.self).baseAddress!, src.bindMemory(to: CChar.self).baseAddress!,
                                        UInt32(data.count), flags, UInt32(compressedSize), key.baseAddress!, 0)
                    }
                }
            }
        }
        return out
    }
}

private extension Data {
    mutating func appendLE(_ value: Int) {
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [(Int, Int)] = []
    func add(_ value: Int, _ total: Int) { lock.lock(); defer { lock.unlock() }; events.append((value, total)) }
    var values: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return events }
    var completed: Int { values.last?.0 ?? 0 }
}
