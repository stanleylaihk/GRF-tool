import Foundation
import CGRFCrypto
import Testing
@testable import GRFCore

private final class LoadingEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [GRFLoadProgress] = []
    private var stop = false
    let cancelAt: GRFLoadProgress.Stage?
    init(cancelAt: GRFLoadProgress.Stage? = nil) { self.cancelAt = cancelAt }
    func append(_ event: GRFLoadProgress) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
        if event.stage == cancelAt { stop = true }
    }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stop }
    var values: [GRFLoadProgress] { lock.lock(); defer { lock.unlock() }; return events }
}

struct GRFLoadingTests {
    @Test func progressDescribesActualIndexWorkAndCompletesMonotonically() throws {
        let fixture = try archiveFixture(count: 4096)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".grf")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture.bytes.write(to: url)
        let events = LoadingEvents()
        let archive = try GRFArchive(url: url, progress: { events.append($0) })
        #expect(archive.entries.count == 4096)
        #expect(events.values.first?.stage == .opening && events.values.last?.stage == .ready)
        #expect(events.values.map(\.fraction) == events.values.map(\.fraction).sorted())
        for stage: GRFLoadProgress.Stage in [.readingIndex, .decompressingIndex, .listingFiles] {
            let updates = events.values.filter { $0.stage == stage }
            #expect(!updates.isEmpty)
            #expect(updates.last?.completed == updates.last?.total)
        }
        #expect(events.values.last(where: { $0.stage == .listingFiles })?.total == 4096)
    }

    @Test func cancellationStopsEveryLongIndexPhaseBeforeReady() throws {
        let fixture = try archiveFixture(count: 64)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".grf")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture.bytes.write(to: url)
        for stage: GRFLoadProgress.Stage in [.readingIndex, .decompressingIndex, .listingFiles] {
            let events = LoadingEvents(cancelAt: stage)
            do {
                _ = try GRFArchive(url: url, progress: { events.append($0) }, cancelled: { events.cancelled })
                Issue.record("Loading must stop when cancelled at \(stage).")
            } catch GRFError.loadingCancelled {} catch { Issue.record(error) }
            #expect(!events.values.contains { $0.stage == .ready })
        }
    }

    @Test func gigabyteSparseArchiveOnlyReadsItsSmallIndex() throws {
        let fixture = try archiveFixture(count: 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".grf")
        defer { try? FileManager.default.removeItem(at: url) }
        let indexOffset = 1_610_612_736 // Sparse 1.5 GiB fixture, not a 1.5 GiB allocation.
        var prefix = Data(fixture.bytes.prefix(fixture.indexPosition))
        prefix.replaceSubrange(30..<34, with: le(indexOffset - 46))
        try prefix.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seek(toOffset: UInt64(indexOffset))
        try handle.write(contentsOf: fixture.bytes.suffix(from: fixture.indexPosition))
        try handle.close()
        let events = LoadingEvents()
        let archive = try GRFArchive(url: url, progress: { events.append($0) })
        #expect(archive.entries.count == 2)
        #expect(try archive.data(for: archive.entries[0]) == Data("payload".utf8))
        #expect(events.values.filter { $0.stage == .readingIndex }.allSatisfy { $0.total < 1_048_576 })
    }

    @Test func suppliedGigabyteArchiveReportsEntriesWithoutReadingAllPayloads() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("RO 私服/data.grf")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let events = LoadingEvents()
        let archive = try GRFArchive(url: url, progress: { events.append($0) })
        #expect(!archive.entries.isEmpty)
        #expect(events.values.last?.stage == .ready)
        #expect(events.values.filter { $0.stage == .readingIndex }.allSatisfy { $0.total <= 256 * 1024 * 1024 })
        let scripts = archive.entries.filter { ["lua", "lub"].contains(($0.path as NSString).pathExtension.lowercased()) }
        for entry in scripts.prefix(8) {
            let preview = try LuaPreviewer.preview(archive.data(for: entry))
            #expect(!preview.text.isEmpty)
        }
    }

    private func le(_ n: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
    private func compressed(_ data: Data) throws -> Data {
        var size = compressBound(uLong(data.count))
        var output = Data(count: Int(size))
        let result = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compress(target.bindMemory(to: UInt8.self).baseAddress!, &size, source.bindMemory(to: UInt8.self).baseAddress!, uLong(data.count))
            }
        }
        guard result == Z_OK else { throw GRFError.invalid("Test compression failed.") }
        output.count = Int(size)
        return output
    }
    private func archiveFixture(count: Int) throws -> (bytes: Data, indexPosition: Int) {
        let payload = try compressed(Data("payload".utf8))
        var table = Data()
        for index in 0..<count {
            table += Data("data/file_\(index).txt".utf8) + Data([0])
            table += le(payload.count) + le(payload.count) + le(7) + Data([1]) + le(0)
        }
        let index = try compressed(table)
        var bytes = Data("Master of Magic".utf8) + Data((0..<15).map { UInt8($0) })
        bytes += le(payload.count) + le(0) + le(count + 7) + le(0x200)
        bytes += payload + le(index.count) + le(table.count) + index
        return (bytes, 46 + payload.count)
    }
}
