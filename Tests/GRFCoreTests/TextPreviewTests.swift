import Foundation
import Testing
@testable import GRFCore

struct TextPreviewTests {
    @Test func unicodeBOMAndLegacyTextUseIndependentContentEncodings() throws {
        #expect(try TextPreviewDecoder.preview(Data("hello 世界".utf8)).text == "hello 世界")
        let utf16 = Data([0xff, 0xfe, 0x41, 0, 0x42, 0])
        #expect(try TextPreviewDecoder.preview(utf16).text == "AB")
        let korean = Data([0xb0, 0xa1])
        #expect(try TextPreviewDecoder.preview(korean, encoding: .korean).text == "가")
        let chinese = Data([0xb1, 0x4e, 0xac, 0xf5, 0xa6, 0xe2])
        let result = try TextPreviewDecoder.preview(chinese)
        #expect(result.text == "將紅色")
        #expect(result.encodingLabel.contains("CP950"))
        #expect(throws: GRFError.self) { try TextPreviewDecoder.preview(chinese, encoding: .utf8) }
        #expect(try TextPreviewDecoder.preview(chinese, encoding: .traditionalChinese).text == "將紅色")
    }

    @Test func truncatedUnicodeIsBoundedWithoutReplacementCharacters() throws {
        let text = String(repeating: "界", count: TextPreviewDecoder.limit / 3 + 8)
        let result = try TextPreviewDecoder.preview(Data(text.utf8))
        #expect(result.encodingLabel == "UTF-8")
        #expect(result.text.contains("Preview truncated"))
        #expect(!result.text.contains("�"))
    }

    @Test func suppliedItemDescriptionsDecodeWithoutChangingKoreanArchiveNames() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        for path in ["adata.grf", "fdata.grf", "RO 私服/data.grf"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let archive = try GRFArchive(url: url, encoding: .korean)
            let entry = try #require(archive.entries.first { $0.path == "data/num2itemdesctable.txt" })
            let bytes = try archive.data(for: entry)
            #expect((try? FilenameEncoding.korean.decode(bytes)) == nil)
            let result = try TextPreviewDecoder.preview(bytes)
            #expect(result.encodingLabel.contains("CP950"))
            #expect(result.text.contains("將紅色的藥草搗碎製成的體力恢復劑"))
            #expect(!result.text.contains("�"))
            #expect(archive.entries.contains { $0.path.contains("몽크") })
            #expect(try TextPreviewDecoder.preview(bytes, encoding: .traditionalChinese).text == result.text)
        }
    }
}
