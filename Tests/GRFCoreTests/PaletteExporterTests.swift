import Foundation
import Testing
import ImageIO
@testable import GRFCore

struct PaletteExporterTests {
    @Test func paletteKeepsAllChannelsAndRejectsWrongLength() throws {
        var bytes = Data(repeating: 0, count: 1024)
        bytes.replaceSubrange(4..<8, with: [12, 34, 56, 78])
        let colors = try PaletteDecoder.colors(from: bytes)
        #expect(colors.count == 256)
        #expect(colors[1].red == 12 && colors[1].green == 34 && colors[1].blue == 56 && colors[1].alpha == 78)
        #expect(throws: (any Error).self) { try PaletteDecoder.colors(from: Data(repeating: 0, count: 1023)) }
    }

    @Test func paletteOverrideOnlyChangesIndexedFrames() throws {
        // SPR 2.0: one indexed pixel and one ABGR truecolor pixel.
        var spr = Data([0x53, 0x50, 0, 2, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 255, 9, 8, 7])
        var original = Data(repeating: 0, count: 1024)
        original.replaceSubrange(4..<8, with: [255, 0, 0, 0])
        spr.append(original)
        var override = original
        override.replaceSubrange(4..<8, with: [0, 255, 0, 255])
        let normal = try SpriteDecoder.document(from: spr)
        let changed = try SpriteDecoder.document(from: spr, palette: override)
        #expect(normal.indexedFrameCount == 1)
        #expect(normal.frames[0].rgba == Data([255, 0, 0, 255]))
        #expect(changed.frames[0].rgba == Data([0, 255, 0, 255]))
        #expect(changed.frames[1].rgba == normal.frames[1].rgba)
        #expect(changed.frames[0].indexedPixels == Data([1]))
        #expect(changed.palette == override)
    }

    @Test func exportedBMPIsDecodableWithCorrectDimensions() throws {
        let pixels = Data([255, 0, 0, 255, 0, 255, 0, 0, 0, 0, 255, 128, 10, 20, 30, 255])
        let frame = SpriteFrame(width: 2, height: 2, rgba: pixels)
        for transparent in [true, false] {
            let bmp = try SpriteExporter.bmp(frame: frame, transparent: transparent)
            #expect(bmp.prefix(2) == Data("BM".utf8))
            #expect(bmp.count == 138 + 16)
            let source = try #require(CGImageSourceCreateWithData(bmp as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 2 && image.height == 2)
            // Stored rows are bottom-up BGRA. Alpha is preserved or explicitly made opaque.
            #expect(Array(bmp.suffix(16).prefix(4)) == [255, 0, 0, transparent ? 128 : 255])
        }
    }

    @Test func indexedBMPPreservesPaletteIndicesAndRowPadding() throws {
        var palette = Data(repeating: 0, count: 1024)
        palette.replaceSubrange(4..<8, with: [11, 22, 33, 0])
        let frame = SpriteFrame(width: 1, height: 2, rgba: Data([11, 22, 33, 255, 0, 0, 0, 0]),
                                indexedPixels: Data([1, 0]), palette: palette)
        let bmp = try SpriteExporter.bmp(frame: frame, transparent: false)
        #expect(bmp[28] == 8)
        #expect(bmp.count == 1078 + 8)
        #expect(Array(bmp[58..<62]) == [33, 22, 11, 0])
        #expect(Array(bmp.suffix(8)) == [0, 0, 0, 0, 1, 0, 0, 0])
        let source = try #require(CGImageSourceCreateWithData(bmp as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1 && image.height == 2)
    }
}
