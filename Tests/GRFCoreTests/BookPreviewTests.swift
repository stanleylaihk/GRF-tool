import Foundation
import Testing
@testable import GRFCore

struct BookPreviewTests {
    @Test func mixedParagraphsRecoverWithoutChangingStrictModes() throws {
        let shortChinese = Data([0xb0, 0x73, 0xba, 0xeb, 0xac, 0x4f, 10])
        let bytes = shortChinese + Data([0xb1,0x4e,0xac,0xf5,0xa6,0xe2, 13,10, 0xbe,0xd7,0xc8,0xad,0xb5,0xc7,0xbe,0xee])
        let result = try TextPreviewDecoder.preview(bytes)
        #expect(result.text == "酒精是\n將紅色\r\n액화되어")
        #expect(result.warning != nil)
        #expect(!result.text.contains("�"))
        #expect(throws: GRFError.self) { try TextPreviewDecoder.preview(bytes, encoding: .traditionalChinese) }
        #expect(try TextPreviewDecoder.preview(bytes, encoding: .mixedChineseKorean).text == result.text)
        #expect(throws: GRFError.self) { try TextPreviewDecoder.preview(Data([0xff]), encoding: .mixedChineseKorean) }
    }

    @Test func suppliedBookDecodes() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_BOOK_ARCHIVE"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        let entry = try #require(archive.entries.first { $0.path.lowercased() == "data/book/7127.txt" })
        let bytes = try archive.data(for: entry)
        let result = try TextPreviewDecoder.preview(bytes)
        #expect(result.text.contains("製作酒精的基礎煉金術"))
        #expect(result.text.contains("^ff0000酒精^000000是?"))
        #expect(result.text.contains("액화되어 나온것을 빈 시험관에 담는다."))
        #expect(result.warning != nil)
        #expect(result.encodingLabel == TextPreviewEncoding.mixedChineseKorean.label)
        #expect(!result.text.contains("�"))
    }
}
