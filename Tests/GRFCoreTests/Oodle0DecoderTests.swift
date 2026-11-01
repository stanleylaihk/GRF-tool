import Foundation
import Testing
@testable import GRFCore

struct Oodle0DecoderTests {
    // Constructed literal-only bitstream, independently checked with the JS
    // reference decoder. Contains no proprietary game data.
    @Test func syntheticLiteralStreamAndSectionIntegration() throws {
        func u(_ n: UInt32) -> Data { var raw = n.littleEndian; return withUnsafeBytes(of: &raw) { Data($0) } }
        var compressed = Data()
        for _ in 0..<3 { compressed += u(256) + u(1) + u(0x01010101) }
        compressed += u(0)
        #expect(try Oodle0Decoder.decompress(compressed, expandedSize: 512, first16Bit: 0, first8Bit: 0) == Data(count: 512))
        #expect(throws: GRFError.self) { try Oodle0Decoder.decompress(compressed, expandedSize: 16, first16Bit: 10, first8Bit: 5) }
        #expect(throws: GRFError.self) { try Oodle0Decoder.decompress(compressed, expandedSize: 16, first16Bit: 0, first8Bit: 17) }
        var file = Data([0xb8,0x67,0xb0,0xca,0xf8,0x6d,0xb1,0x0f,0x84,0x72,0x8c,0x7e,0x5e,0x19,0x00,0x1e])
        for value: UInt32 in [132,0,0,0,6,172,0,56,1,0,0,0,0,0,0,0,0,0] { file += u(value) }
        for value: UInt32 in [1,132,40,512,4,0,0,0,0,0,0] { file += u(value) }
        file += compressed
        #expect(try GrannySectionDecoder.decode(file) == [Data(count: 512)])
    }

    @Test func emptyAndMalformedInputsAreBounded() throws {
        #expect(try Oodle0Decoder.decompress(Data(), expandedSize: 0, first16Bit: 0, first8Bit: 0).isEmpty)
        for size in [-1, 1, 64 * 1024 * 1024 + 1] {
            #expect(throws: GRFError.self) { try Oodle0Decoder.decompress(Data(), expandedSize: size, first16Bit: 0, first8Bit: 0) }
        }
        #expect(throws: GRFError.self) { try Oodle0Decoder.decompress(Data(repeating: 0xff, count: 40), expandedSize: 10, first16Bit: 0, first8Bit: 0) }
    }
    @Test func nativeOutputMatchesOriginalDLLBytes() throws {
        guard let corpus = ProcessInfo.processInfo.environment["GRF_GRANNY_CORPUS"],
              let oracle = ProcessInfo.processInfo.environment["GRF_OODLE_ORACLE"] else { return }
        let root = URL(fileURLWithPath: corpus), expectedRoot = URL(fileURLWithPath: oracle)
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: expectedRoot.appendingPathComponent("manifest.json"))) as? [String: Any])
        let records = try #require(manifest["sections"] as? [[String: Any]])
        #expect(!records.isEmpty)
        var compared = 0
        for record in records {
            let file = try #require(record["file"] as? String), index = try #require(record["section"] as? Int)
            let bytes = try Data(contentsOf: root.appendingPathComponent(file))
            func u(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p+1]) << 8 | Int(bytes[p+2]) << 16 | Int(bytes[p+3]) << 24 }
            let p = 32 + u(44) + index * 44
            guard u(p) == 1 else { continue }
            let compressed = bytes.subdata(in: u(p+4)..<(u(p+4)+u(p+8)))
            let actual = try Oodle0Decoder.decompress(compressed, expandedSize: u(p+12), first16Bit: u(p+20), first8Bit: u(p+24))
            let output = try #require(record["output"] as? String)
            let expected = try Data(contentsOf: expectedRoot.appendingPathComponent(output))
            #expect(actual == expected, "\(file), section \(index) differs from original DLL")
            #expect(try GrannySectionDecoder.decode(bytes)[index] == expected)
            compared += 1
        }
        #expect(compared > 0)
        print("Byte-exact native Oodle-0 parity: \(compared) original-DLL sections")
    }
}
