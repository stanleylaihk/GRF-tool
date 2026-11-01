import Foundation
import Testing
import CGRFCrypto
@testable import GRFCore

private final class BuildEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var values: [Double] = []
    let stopAt: Double?
    init(stopAt: Double? = nil) { self.stopAt = stopAt }
    func receive(_ progress: GRFBuildProgress) {
        lock.lock(); defer { lock.unlock() }
        values.append(progress.fraction)
        if let stopAt, progress.fraction >= stopAt { stopped = true }
    }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    var fractions: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

struct GRFBuilderTests {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grf-builder-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func put(_ bytes: Data, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
    }

    @Test func mergePoliciesAndDeletionSaveAnIndependentArchive() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try put(Data("keep".utf8), "base/data/keep.txt", in: root)
        try put(Data("old".utf8), "base/data/shared.txt", in: root)
        try put(Data("new".utf8), "patch/data/shared.txt", in: root)
        try put(Data("return true".utf8), "patch/data/added.lua", in: root)
        let baseURL = root.appendingPathComponent("base.grf"), patchURL = root.appendingPathComponent("patch.grf")
        try GRFBuilder.write(GRFBuildFile.importing(root.appendingPathComponent("base/data")), to: baseURL, encoding: .utf8)
        try GRFBuilder.write(GRFBuildFile.importing(root.appendingPathComponent("patch/data")), to: patchURL, encoding: .utf8)
        let originalBase = try Data(contentsOf: baseURL), originalPatch = try Data(contentsOf: patchURL)
        let base = try GRFBuildFile.fromArchive(GRFArchive(url: baseURL, encoding: .utf8))
        let added = try GRFBuildFile.fromArchive(GRFArchive(url: patchURL, encoding: .utf8))
        #expect(throws: GRFError.self) { try GRFBuildFile.merging(base, with: added, policy: .reject) }
        let kept = try GRFBuildFile.merging(base, with: added, policy: .keepExisting)
        let keepURL = root.appendingPathComponent("kept.grf")
        try GRFBuilder.write(kept, to: keepURL, encoding: .utf8)
        let keepArchive = try GRFArchive(url: keepURL, encoding: .utf8)
        let shared = try #require(keepArchive.entries.first { $0.path == "data/shared.txt" })
        #expect(try keepArchive.data(for: shared) == Data("old".utf8))
        let merged = try GRFBuildFile.merging(base, with: added, policy: .replaceExisting)
        let removed = GRFBuildFile.removing(merged, paths: ["DATA/KEEP.TXT"])
        let output = root.appendingPathComponent("merged.grf")
        try GRFBuilder.write(removed, to: output, encoding: .utf8, compressionLevel: 9)
        let archive = try GRFArchive(url: output, encoding: .utf8)
        #expect(Set(archive.entries.map(\.path)) == ["data/shared.txt", "data/added.lua"])
        for entry in archive.entries {
            #expect(try archive.data(for: entry) == Data((entry.path.hasSuffix("shared.txt") ? "new" : "return true").utf8))
        }
        #expect(try Data(contentsOf: baseURL) == originalBase)
        #expect(try Data(contentsOf: patchURL) == originalPatch)
        #expect(throws: GRFError.self) { try GRFBuilder.write(merged, to: baseURL, overwrite: true) }
    }

    @Test func repackReclaimsUnreferencedBytesAndHonorsEveryCompressionLevel() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let content = Data(String(repeating: "Ragnarok resource content\n", count: 8192).utf8)
        try put(content, "data/text.txt", in: root)
        let source = root.appendingPathComponent("source.grf")
        try GRFBuilder.write(GRFBuildFile.importing(root.appendingPathComponent("data")), to: source, encoding: .utf8)
        var padded = try Data(contentsOf: source); padded += Data(repeating: 0x7f, count: 1_000_000)
        try padded.write(to: source)
        let files = try GRFBuildFile.fromArchive(GRFArchive(url: source, encoding: .utf8))
        var sizes: [Int: Int] = [:]
        for level in -1...9 {
            let output = root.appendingPathComponent("level-\(level).grf")
            try GRFBuilder.write(files, to: output, encoding: .utf8, compressionLevel: level)
            let archive = try GRFArchive(url: output, encoding: .utf8)
            let entry = try #require(archive.entries.first)
            #expect(try archive.data(for: entry) == content)
            let bytes = try Data(contentsOf: output)
            sizes[level] = bytes.count
            #expect(bytes.count < padded.count)
        }
        #expect(sizes[0]! > sizes[9]!)
        #expect(try Data(contentsOf: source) == padded)
        for invalid in [-2, 10, Int.max] {
            let url = root.appendingPathComponent("invalid.grf")
            #expect(throws: GRFError.self) { try GRFBuilder.write(files, to: url, compressionLevel: invalid) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func archiveEditsRejectChangedSourcesAndCancellationPreservesOutput() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try put(Data(repeating: 8, count: 400_000), "data/content.bin", in: root)
        let source = root.appendingPathComponent("source.grf")
        try GRFBuilder.write(GRFBuildFile.importing(root.appendingPathComponent("data")), to: source)
        let archive = try GRFArchive(url: source)
        let files = try GRFBuildFile.fromArchive(archive)
        let output = root.appendingPathComponent("output.grf"), original = Data("existing output".utf8)
        try original.write(to: output)
        let events = BuildEvents(stopAt: 0.01)
        #expect(throws: GRFBuildError.self) {
            try GRFBuilder.write(files, to: output, overwrite: true, progress: { events.receive($0) }, cancelled: { events.cancelled })
        }
        #expect(try Data(contentsOf: output) == original)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: source.path)
        #expect(throws: GRFError.self) { try GRFBuildFile.fromArchive(archive) }
        #expect(throws: GRFError.self) { try GRFBuilder.write(files, to: output, overwrite: true) }
        #expect(try Data(contentsOf: output) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".grf-build-") })
    }

    @Test func damagedFdataRequiresExplicitRemovalBeforeRepack() throws {
        guard let location = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        let source = URL(fileURLWithPath: location).appendingPathComponent("fdata.grf")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let archive = try GRFArchive(url: source)
        let files = try GRFBuildFile.fromArchive(archive)
        let output = root.appendingPathComponent("repacked.grf")
        #expect(throws: GRFError.self) { try GRFBuilder.write(files, to: output, compressionLevel: 9) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let cleaned = GRFBuildFile.removing(files, paths: ["data/etcinfo.txt"])
        try GRFBuilder.write(cleaned, to: output, compressionLevel: 9)
        let result = try GRFArchive(url: output)
        #expect(result.entries.count == 189)
        for entry in result.entries {
            let sourceEntry = try #require(archive.entries.first { $0.path == entry.path })
            #expect(try result.data(for: entry) == archive.data(for: sourceEntry))
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func emptyArchiveAndIndependentHeaderLayout() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("empty.grf")
        try GRFBuilder.write([], to: output)
        let bytes = try Data(contentsOf: output)
        #expect(bytes.prefix(16) == Data("Master of Magic\0".utf8))
        #expect(Array(bytes[16..<30]) == Array(UInt8(0)..<14))
        var header = BinaryReader(bytes); header.offset = 30
        #expect(try header.u32() == 0) // Empty payload, index immediately after 46-byte header.
        #expect(try header.u32() == 0)
        #expect(try header.u32() == 7)
        #expect(try header.u32() == 0x200)
        let archive = try GRFArchive(url: output)
        #expect(archive.entries.isEmpty)
    }

    @Test func importsNestedFilesAndStreamsMultipleBlocksWithStandardIndex() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        var random = Data(); var seed: UInt32 = 42
        for _ in 0..<(2 * 1024 * 1024 + 3) {
            seed = seed &* 1664525 &+ 1013904223; random.append(UInt8(truncatingIfNeeded: seed >> 16))
        }
        let payloads = ["data/nested/file.bin": random, "data/empty.txt": Data(), "data/안녕.lua": Data("return 'hello'".utf8)]
        for (path, bytes) in payloads { try put(bytes, path, in: root) }
        let staged = try GRFBuildFile.importing(root.appendingPathComponent("data"))
        #expect(staged.count == 3)
        #expect(Set(staged.map(\.path)) == Set(payloads.keys))
        let output = root.appendingPathComponent("roundtrip.grf")
        let events = BuildEvents()
        try GRFBuilder.write(staged, to: output, progress: { events.receive($0) })
        let archive = try GRFArchive(url: output)
        #expect(archive.version == 0x200)
        for entry in archive.entries { #expect(try archive.data(for: entry) == payloads[entry.path]) }
        #expect(events.fractions == events.fractions.sorted())
        #expect(events.fractions.last == 1)
        // Independently decode the table and check offset/length/flags against raw zlib payloads.
        let bytes = try Data(contentsOf: output)
        var header = BinaryReader(bytes); header.offset = 30
        let tableOffset = try header.u32() + 46
        var indexSizes = BinaryReader(Data(bytes[tableOffset...])); let packed = try indexSizes.u32(); let size = try indexSizes.u32()
        let table = try inflate(Data(bytes[(tableOffset + 8)..<(tableOffset + 8 + packed)]), expectedSize: size)
        var index = BinaryReader(table)
        for file in staged {
            let name = try FilenameEncoding.korean.decode(index.terminatedName()).replacingOccurrences(of: "\\", with: "/")
            #expect(name == file.path)
            let compressed = try index.u32(); #expect(try index.u32() == compressed)
            #expect(try index.u32() == Int(file.size)); #expect(try index.u8() == 1)
            let offset = try index.u32() + 46
            let content = try inflate(Data(bytes[offset..<(offset + compressed)]), expectedSize: Int(file.size))
            #expect(content == payloads[name])
        }
        #expect(index.remaining == 0)
        // Imported sources are untouched.
        for (path, content) in payloads { #expect(try Data(contentsOf: root.appendingPathComponent(path)) == content) }
    }

    @Test func gigabyteFolderBuildUsesStreamingCompression() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        for number in 0..<3 {
            let path = "data/large_\(number).bin"
            try put(Data(), path, in: root)
            let handle = try FileHandle(forWritingTo: root.appendingPathComponent(path))
            try handle.truncate(atOffset: 384 * 1024 * 1024)
            try handle.close()
        }
        let files = try GRFBuildFile.importing(root.appendingPathComponent("data"))
        #expect(files.reduce(Int64(0)) { $0 + $1.size } > 1024 * 1024 * 1024)
        let output = root.appendingPathComponent("large.grf")
        try GRFBuilder.write(files, to: output)
        let archive = try GRFArchive(url: output)
        #expect(archive.entries.count == 3)
        #expect(archive.entries.allSatisfy { $0.size == 384 * 1024 * 1024 })
        #expect(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize! < 2 * 1024 * 1024)
    }

    @Test func encodingIsLosslessAndInvalidEncodingLeavesNoOutput() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try put(Data("hello".utf8), "data/😀.txt", in: root)
        let files = try GRFBuildFile.importing(root.appendingPathComponent("data"))
        let output = root.appendingPathComponent("utf8.grf")
        #expect(throws: (any Error).self) { try GRFBuilder.write(files, to: output, encoding: .korean) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        try GRFBuilder.write(files, to: output, encoding: .utf8)
        #expect(try GRFArchive(url: output, encoding: .utf8).entries.first?.path == "data/😀.txt")
    }

    @Test func duplicateAndUnsafeImportsAreTransactional() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try put(Data([1]), "data/Test.txt", in: root)
        let files = try GRFBuildFile.importing(root.appendingPathComponent("data"))
        #expect(throws: (any Error).self) { try GRFBuildFile.combining(files, with: files) }
        try put(Data([2]), "other/DATA/test.txt", in: root)
        let caseDuplicate = try GRFBuildFile.importing(root.appendingPathComponent("other/DATA"))
        #expect(throws: (any Error).self) { try GRFBuildFile.combining(files, with: caseDuplicate) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("data/link").path, withDestinationPath: "/etc/hosts")
        #expect(throws: (any Error).self) { try GRFBuildFile.importing(root.appendingPathComponent("data")) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("data/link"))
        try put(Data(), "data/bad\\name", in: root)
        #expect(throws: (any Error).self) { try GRFBuildFile.importing(root.appendingPathComponent("data")) }
    }

    @Test func cancelAndSourceChangesPreserveExistingDestinationAndCleanTemporaryFiles() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        try put(Data(repeating: 123, count: 300_000), "data/file.bin", in: root)
        let files = try GRFBuildFile.importing(root.appendingPathComponent("data"))
        let output = root.appendingPathComponent("existing.grf")
        let original = Data("do not replace me".utf8); try original.write(to: output)
        #expect(throws: (any Error).self) { try GRFBuilder.write(files, to: output) }
        let events = BuildEvents(stopAt: 0.01)
        #expect(throws: GRFBuildError.self) {
            try GRFBuilder.write(files, to: output, overwrite: true, progress: { events.receive($0) }, cancelled: { events.cancelled })
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(throws: (any Error).self) { try GRFBuilder.write(files, to: files[0].source, overwrite: true) }
        // Same-size edits must be detected too, even if the URL has cached resource values.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: files[0].source.path)
        #expect(throws: (any Error).self) { try GRFBuilder.write(files, to: output, overwrite: true) }
        #expect(try Data(contentsOf: output) == original)
        try put(Data([99]), "data/file.bin", in: root)
        #expect(throws: (any Error).self) { try GRFBuilder.write(files, to: output, overwrite: true) }
        #expect(try Data(contentsOf: output) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".grf-build-") })
    }
}
