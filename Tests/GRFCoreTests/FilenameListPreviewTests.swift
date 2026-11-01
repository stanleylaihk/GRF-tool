import Foundation
import Testing
@testable import GRFCore

struct FilenameListPreviewTests {
    func sample() -> Data {
        var data = Data()
        for name in ["D:\\sprites\\body.spr", "head.spr"] {
            var size = UInt32(name.utf8.count + 1).littleEndian
            data += withUnsafeBytes(of: &size) { Data($0) }
            data += Data(name.utf8) + Data([0])
        }
        return data
    }
    @Test func readablePathsAndJSON() throws {
        let document = try FilenameListPreview.decode(sample())
        #expect(document.files == ["D:\\sprites\\body.spr", "head.spr"])
        #expect(document.readableSummary.contains("contains no image"))
        #expect(try document.json().contains("head.spr"))
    }
    @Test func rejectsCorruptReferences() throws {
        #expect(throws: GRFError.self) { try FilenameListPreview.decode(Data([0xff, 0xff, 0xff, 0xff])) }
        #expect(throws: GRFError.self) { try FilenameListPreview.decode(Data(sample().dropLast())) }
        var invalid = sample(); invalid[invalid.count - 1] = 65
        #expect(throws: GRFError.self) { try FilenameListPreview.decode(invalid) }
    }
    @Test func suppliedFilenameLists() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_SCENE_ARCHIVE"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        let entries = archive.entries.filter { ($0.path as NSString).pathExtension.lowercased() == "fna" }
        #expect(!entries.isEmpty)
        for entry in entries {
            let doc = try FilenameListPreview.decode(archive.data(for: entry))
            #expect(!doc.files.isEmpty)
        }
        print("Validated \(entries.count) FNA resource lists")
    }
}
