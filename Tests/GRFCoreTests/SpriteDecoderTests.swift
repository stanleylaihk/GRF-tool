import Testing
import Foundation
@testable import GRFCore

final class SpriteDecoderTests {
    @Test func testSPR21IndexedRLEUsesPaletteAndTransparentZero() throws {
        // 2x2 indexed frame: [red, transparent, transparent, green].
        var data = Data([0x53, 0x50, 1, 2, 1, 0, 0, 0,
                         2, 0, 2, 0, 4, 0, 1, 0, 2, 2])
        data.append(palette())
        let frames = try SpriteDecoder.frames(from: data)
        expectEqual(frames.count, 1)
        expectEqual(frames[0].width, 2)
        expectEqual(frames[0].height, 2)
        expectEqual(frames[0].rgba, Data([255, 0, 0, 255, 0, 0, 0, 0,
                                           0, 0, 0, 0, 0, 255, 0, 255]))
    }

    @Test func testSPR20UncompressedIndexedFrame() throws {
        var data = Data([0x53, 0x50, 0, 2, 1, 0, 0, 0,
                         2, 0, 1, 0, 1, 2])
        data.append(palette())
        let frame = try requireValue(SpriteDecoder.frames(from: data).first)
        expectEqual(frame.rgba, Data([255, 0, 0, 255, 0, 255, 0, 255]))
    }

    @Test func testSPR21TruecolorConvertsABGRAndFlipsBottomUpRows() throws {
        let data = Data([0x53, 0x50, 1, 2, 0, 0, 1, 0,
                         1, 0, 2, 0,
                         128, 33, 22, 11, 255, 66, 55, 44])
        let frame = try requireValue(SpriteDecoder.frames(from: data).first)
        expectEqual(frame.width, 1)
        expectEqual(frame.height, 2)
        expectEqual(frame.rgba, Data([44, 55, 66, 255, 11, 22, 33, 128]))
    }

    @Test func testMalformedRunsAndOverlappingPaletteAreRejected() throws {
        for compressed: [UInt8] in [[0, 0], [0, 5], [0], [1, 1, 1, 1, 1], [1]] {
            var data = Data([0x53, 0x50, 1, 2, 1, 0, 0, 0, 2, 0, 2, 0,
                             UInt8(compressed.count), 0])
            data.append(contentsOf: compressed)
            data.append(palette())
            expectThrowsError(try SpriteDecoder.frames(from: data))
        }
        var overlap = Data([0x53, 0x50, 0, 2, 1, 0, 0, 0, 2, 0, 2, 0])
        overlap.append(palette())
        expectThrowsError(try SpriteDecoder.frames(from: overlap))
    }

    @Test func testUnsupportedVersionInvalidMagicAndZeroDimensionsAreRejected() throws {
        for bytes: [UInt8] in [[], [0x53], [0, 0, 1, 2, 0, 0, 0, 0],
                              [0x53, 0x50, 2, 2, 0, 0, 0, 0],
                              [0x53, 0x50, 1, 2, 0, 0, 1, 0, 0, 0, 1, 0]] {
            expectThrowsError(try SpriteDecoder.frames(from: Data(bytes)))
        }
    }

    private func palette() -> Data {
        var bytes = [UInt8](repeating: 0, count: 1024)
        bytes[4] = 255
        bytes[9] = 255
        return Data(bytes)
    }
}
