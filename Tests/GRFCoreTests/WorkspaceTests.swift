import Foundation
import Testing
@testable import GRFCore

struct WorkspaceTests {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grf-workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func file(_ root: URL, name: String, text: String) throws -> GRFBuildFile {
        let url = root.appendingPathComponent(name); try Data(text.utf8).write(to: url)
        return try GRFBuildFile.importingFile(url, path: "data/" + name)
    }
    @Test func duplicateOriginalPathsRemainProtectedAfterOneIsRemoved() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try file(root, name: "same.txt", text: "original")
        var draft = ArchiveDraft(files: [a, a])
        draft.delete([0])
        #expect(draft.files.count == 1)
        #expect(throws: GRFError.self) { try draft.add([a]) }
        draft.undoLast()
        try draft.rename(0, to: "data/other.txt")
        #expect(throws: GRFError.self) { try draft.add([a]) }
        draft.revertAll(); #expect(draft.files.count == 2)
    }
    @Test func renameReplaceDeleteAndPerItemUndoPreserveOriginal() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try file(root, name: "a.txt", text: "original"), b = try file(root, name: "b.txt", text: "replacement")
        var draft = ArchiveDraft(files: [a])
        try draft.rename(0, to: "data/renamed.txt")
        try draft.replace(0, with: b)
        #expect(draft.changes.count == 1 && draft.changes[0].status == "Replaced · Renamed")
        #expect(try String(decoding: draft.files[0].data(), as: UTF8.self) == "replacement")
        draft.delete([0]); #expect(draft.files.isEmpty && draft.changes[0].status == "Deleted")
        draft.undoLast(); #expect(draft.files[0].path == "data/renamed.txt")
        try draft.revert(0); #expect(draft.changes.isEmpty)
        #expect(try String(decoding: draft.files[0].data(), as: UTF8.self) == "original")
        #expect(try String(contentsOf: a.source, encoding: .utf8) == "original")
    }
    @Test func importsAreAtomicAndUndoAvoidsNameCollisions() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try file(root, name: "a.txt", text: "A")
        var draft = ArchiveDraft(files: [a])
        #expect(throws: GRFError.self) { try draft.add([a]) }; #expect(draft.changes.isEmpty)
        try draft.rename(0, to: "data/b.txt"); try draft.add([a])
        #expect(throws: GRFError.self) { try draft.revert(0) }
        #expect(draft.files.count == 2)
        draft.undoLast(); try draft.revert(0); #expect(draft.files.count == 1 && draft.changes.isEmpty)
        #expect(throws: GRFError.self) { try draft.rename(0, to: "../escape") }
    }
    @Test func saveAndExtractUseStagedDataAndProtectExistingFiles() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = try file(root, name: "a.txt", text: "hello"), b = try file(root, name: "b.txt", text: "new contents")
        var draft = ArchiveDraft(files: [a]); try draft.replace(0, with: b); try draft.rename(0, to: "data/renamed.txt")
        let archiveURL = root.appendingPathComponent("copy.grf")
        try GRFBuilder.write(draft.files, to: archiveURL, encoding: .utf8)
        let archive = try GRFArchive(url: archiveURL, encoding: .utf8)
        #expect(archive.entries.map(\.path) == ["data/renamed.txt"])
        #expect(try String(decoding: archive.data(for: archive.entries[0]), as: UTF8.self) == "new contents")
        let output = root.appendingPathComponent("extracted"); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try DraftExtraction.write(draft.files[0], to: output)
        #expect(try String(contentsOf: output.appendingPathComponent("data/renamed.txt"), encoding: .utf8) == "new contents")
        #expect(throws: GRFError.self) { try DraftExtraction.write(draft.files[0], to: output) }
        let unsafe = root.appendingPathComponent("unsafe"); try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: unsafe.appendingPathComponent("data"), withDestinationURL: root)
        #expect(throws: GRFError.self) { try DraftExtraction.write(draft.files[0], to: unsafe) }
    }
    @Test func contentSearchIncludesTextPastPreviewLimitAndLegacyContent() throws {
        let text = String(repeating: "padding ", count: 300_000) + "\nRareMatch and rarematch"
        let hit = try #require(try ResourceSearch.hit(Data(text.utf8), resourceID: 3, path: "data/long.json", query: "RareMatch"))
        #expect(hit.count == 2 && hit.line == 2 && hit.resourceID == 3)
        #expect(hit.snippet.contains("RareMatch"))
        #expect(ResourceSearch.matchesName("data/book/7127.txt", query: "*.txt"))
        #expect(!ResourceSearch.matchesName("data/book/7127.txt", query: "*.spr"))
        #expect(try ResourceSearch.hit(Data([0xb1,0x4e,0xac,0xf5,0xa6,0xe2]), resourceID: 1, path: "book.txt", query: "將紅色")?.count == 1)
    }
    @Test func rawInspectionIsBoundedAndDoesNotLoseOriginalBytes() {
        let bytes = Data([0,0x41,0x42,0x43,0x44,0xff])
        let inspection = ResourceInspection.inspect(bytes, name: "unknown.bin")
        #expect(inspection.strings == "ABCD")
        #expect(inspection.hex.contains("00 41 42 43 44 FF"))
        #expect(inspection.summary.contains("6 bytes"))
    }
}
