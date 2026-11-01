import Foundation
import Testing
@testable import GRFCore

struct LuaPreviewTests {
    @Test func textLUBAndKoreanLuaAreReadable() throws {
        let source = "-- source text in either .lua or .lub\nvalue = '한글'\n"
        #expect(try LuaPreviewer.preview(Data(source.utf8)).text == source)
        let cp949 = Data([0x2d, 0x2d, 0x20, 0xb0, 0xa1, 0x0a])
        #expect(try LuaPreviewer.preview(cp949).text == "-- 가\n")
        let big5 = Data([0x2d, 0x2d, 0x20, 0xa4, 0xa4, 0xa4, 0xe5, 0x0a])
        #expect(try LuaPreviewer.preview(big5, encoding: .traditionalChinese).text == "-- 中文\n")
    }

    @Test func compiled51ListsConstantsInstructionsAndNestedFunctions() throws {
        for little in [true, false] {
            for stringSize in [4, 8] {
                let listing = try LuaPreviewer.preview(chunk(little: little, stringSize: stringSize))
                #expect(listing.format == "Lua 5.1 bytecode")
                #expect(listing.text.contains("disassembly, not recovered source"))
                #expect(listing.text.contains("answer") && listing.text.contains("42.0"))
                #expect(listing.text.contains("LOADK") && listing.text.contains("RETURN"))
                #expect(listing.text.contains("function main.0"))
            }
        }
    }

    @Test func malformedAndUnsupportedChunksDoNotBecomeGarbledText() throws {
        let valid = chunk()
        for length in [4, 11, 20, valid.count - 1] {
            #expect(throws: (any Error).self) { try LuaPreviewer.preview(Data(valid.prefix(length))) }
        }
        var unsupported = valid
        unsupported[4] = 0x54
        let preview = try LuaPreviewer.preview(unsupported)
        #expect(preview.text.contains("Lua 5.4") && preview.text.contains("00000000"))
        var invalid = valid
        invalid[8] = 3 // unsupported size_t layout
        #expect(throws: (any Error).self) { try LuaPreviewer.preview(invalid) }
        #expect(try LuaPreviewer.preview(Data([0, 1, 2, 3])).format == "Binary script")
    }

    @Test func textPreviewIsBoundedAtMultibyteBoundary() throws {
        let text = String(repeating: "가", count: 200000)
        let preview = try LuaPreviewer.preview(Data(text.utf8))
        #expect(preview.text.contains("Preview truncated"))
        #expect(!preview.text.contains("�"))
        #expect(preview.text.utf8.count < 525000)
        let constant = try LuaPreviewer.preview(chunk(constantString: String(repeating: "가", count: 200)))
        #expect(constant.text.contains("가") && constant.text.contains("…"))
        #expect(!constant.text.contains("\\x"))
    }

    @Test func suppliedLuaAndLUBPreview() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        let base = URL(fileURLWithPath: root).appendingPathComponent("RO 私服/System")
        let samples = [("optioninfo.lub", "Lua source"), ("Towninfo.lub", "Lua source"), ("LuaFiles514/OptionInfo.lub", "Lua 5.1 bytecode")]
        for (name, format) in samples {
            let url = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let preview = try LuaPreviewer.preview(Data(contentsOf: url))
            #expect(preview.format == format)
            #expect(!preview.text.isEmpty)
        }
    }

    private func chunk(little: Bool = true, stringSize: Int = 4, constantString: String = "answer") -> Data {
        func integer(_ n: UInt64, _ size: Int = 4) -> Data {
            let bytes = (0..<size).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }
            return Data(little ? bytes : bytes.reversed())
        }
        func string(_ text: String) -> Data { integer(UInt64(text.utf8.count + 1), stringSize) + Data(text.utf8) + Data([0]) }
        func function(child: Bool) -> Data {
            var b = string("@sample.lua") + integer(0) + integer(0) + Data([0, 0, 2, 2])
            b += integer(2) + integer(1) + integer(30 | 1 << 23) // LOADK A0 K0; RETURN A0 B1
            b += integer(2) + Data([4]) + string(constantString) + Data([3]) + integer(42.0.bitPattern, 8)
            b += integer(child ? 0 : 1)
            if !child { b += function(child: true) }
            b += integer(2) + integer(1) + integer(2) // line table
            b += integer(0) + integer(0) // locals and upvalue names
            return b
        }
        return Data([0x1b, 0x4c, 0x75, 0x61, 0x51, 0, little ? 1 : 0, 4, UInt8(stringSize), 4, 8, 0]) + function(child: false)
    }
}
