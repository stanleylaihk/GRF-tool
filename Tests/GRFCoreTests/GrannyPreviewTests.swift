import Foundation
import Testing
@testable import GRFCore

struct GrannyPreviewTests {
    private func sample() -> Data {
        var data = Data([0xb8, 0x67, 0xb0, 0xca, 0xf8, 0x6d, 0xb1, 0x0f, 0x84, 0x72, 0x8c, 0x7e, 0x5e, 0x19, 0x00, 0x1e])
        func u(_ n: UInt32) -> Data { var n = n.littleEndian; return withUnsafeBytes(of: &n) { Data($0) } }
        for n: UInt32 in [132, 0, 0, 0, 6, 136, 0x12345678, 56, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0] { data += u(n) }
        for n: UInt32 in [1, 132, 4, 32, 4, 0, 0, 0, 0, 0, 0] { data += u(n) }
        data += Data([1, 2, 3, 4])
        return data
    }
    @Test func physicalMetadataAndHonestLimitations() throws {
        let doc = try GrannyPreviewDocument.decode(sample())
        #expect(doc.version == 6)
        #expect(doc.headerByteCount == 132)
        #expect(doc.sections[0].compressionLabel == "Oodle-0")
        #expect(doc.sections[0].storedByteCount == 4)
        #expect(doc.sections[0].unpackedByteCount == 32)
        #expect(doc.checksumHex == "12345678")
        #expect(doc.readableSummary.contains("Wireframe / Textured"))
        #expect(try doc.json().contains("Oodle-0"))
    }
    @Test func rejectsTruncatedAndInvalidSectionRanges() throws {
        let original = sample()
        for n in 0..<original.count {
            #expect(throws: (any Error).self) { _ = try GrannyPreviewDocument.decode(Data(original.prefix(n))) }
        }
        var damaged = original
        damaged.replaceSubrange(92..<96, with: [0xff, 0xff, 0xff, 0x7f])
        #expect(throws: (any Error).self) { _ = try GrannyPreviewDocument.decode(damaged) }
        var unknown = original; unknown[0] = 0
        #expect(throws: (any Error).self) { _ = try GrannyPreviewDocument.decode(unknown) }
    }
    @Test func localGrannyResources() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_SCENE_ARCHIVE"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        let entries = archive.entries.filter { ($0.path as NSString).pathExtension.lowercased() == "gr2" }
        #expect(!entries.isEmpty)
        for entry in entries {
            let bytes = try archive.data(for: entry)
            let doc = try GrannyPreviewDocument.decode(bytes)
            #expect(doc.version == 6)
            #expect(doc.sections.count == 6)
            if entry.id == entries.first?.id, let directory = ProcessInfo.processInfo.environment["GRF_SCENE_SAMPLES"] {
                try bytes.write(to: URL(fileURLWithPath: directory).appendingPathComponent("sample.gr2"))
            }
        }
        print("Validated \(entries.count) GR2 metadata previews")
    }
}
