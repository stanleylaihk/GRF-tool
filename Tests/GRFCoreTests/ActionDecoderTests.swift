import Foundation
import Testing
@testable import GRFCore

struct ActionDecoderTests {
    @Test func parsesModernLayersAnchorsSoundsAndTiming() throws {
        let document = try ActionDecoder.decode(fixture(version: 0x205))
        #expect(document.version == 0x205)
        #expect(document.sounds == ["test.wav"])
        #expect(document.actions.count == 1)
        #expect(abs(document.actions[0].frameDuration - 0.144) < 0.00001)
        let frame = document.actions[0].frames[0]
        #expect(frame.soundIndex == 0)
        #expect(frame.anchors[0].x == 17)
        #expect(frame.anchors[0].y == -4)
        let layer = frame.layers[0]
        #expect(layer.offsetX == 3 && layer.offsetY == -2)
        #expect(layer.color == [255, 128, 64, 255])
        #expect(layer.width == 2 && layer.height == 1)
    }

    @Test func parsesVersionDependentFields() throws {
        for version in [0x101, 0x200, 0x201, 0x202, 0x203, 0x204, 0x205] {
            let doc = try ActionDecoder.decode(fixture(version: version))
            let frame = doc.actions[0].frames[0]
            #expect(frame.layers.count == 1)
            #expect(frame.anchors.count == (version >= 0x203 ? 1 : 0))
            #expect(doc.sounds.count == (version >= 0x201 ? 1 : 0))
            #expect(frame.soundIndex == (version >= 0x200 ? 0 : -1))
        }
    }

    @Test func rejectsTruncationHugeCountsAndInvalidFloatingPoint() throws {
        var data = fixture(version: 0x205)
        data.removeLast()
        #expect(throws: Error.self) { try ActionDecoder.decode(data) }
        data = fixture(version: 0x205)
        data[16] = 255; data[17] = 255; data[18] = 255; data[19] = 255
        #expect(throws: Error.self) { try ActionDecoder.decode(data) }
        data = fixture(version: 0x205)
        // Layer scale begins after header, frame header and four int32 layer fields.
        data.replaceSubrange(76..<80, with: [0, 0, 192, 127])
        #expect(throws: Error.self) { try ActionDecoder.decode(data) }
        #expect(throws: Error.self) { try ActionDecoder.decode(Data("not ACT".utf8)) }
    }

    @Test func rendersMirrorTintAndCommonCanvas() throws {
        let sprite = SpriteFrame(width: 2, height: 2, rgba: Data([
            255, 0, 0, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 0, 255, 0, 255]))
        let first = ActionFrame(layers: [layer(x: 0, mirror: true, color: [255, 128, 255, 255])], anchors: [], soundIndex: -1)
        let second = ActionFrame(layers: [layer(x: 2)], anchors: [], soundIndex: -1)
        let frames = try ActionRenderer.render(action: SpriteAction(frames: [first, second], frameDuration: 0.1), sprites: [sprite], indexedCount: 1)
        #expect(frames.count == 2 && frames[0].width == 4 && frames[1].width == 4)
        #expect(frames[0].height == 2)
        #expect(Array(frames[0].rgba.prefix(8)) == [0, 128, 0, 255, 255, 0, 0, 255])
        #expect(frames[0].rgba[11] == 0)
        #expect(frames[1].rgba[3] == 0)
        #expect(Array(frames[1].rgba[8..<16]) == [255, 0, 0, 255, 0, 255, 0, 255])
    }

    @Test func rendersTruecolorIndicesRotationScaleAndAlphaOver() throws {
        let red = SpriteFrame(width: 2, height: 2, rgba: Data(Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 4).flatMap { $0 }))
        let blue = SpriteFrame(width: 2, height: 2, rgba: Data(Array(repeating: [UInt8](arrayLiteral: 0, 0, 255, 128), count: 4).flatMap { $0 }))
        let trueLayer = ActionLayer(offsetX: 0, offsetY: 0, spriteIndex: 0, isTruecolor: true, mirror: false,
                                    scaleX: 2, scaleY: 2, rotation: 90, color: [255, 255, 255, 255], width: 0, height: 0)
        let frame = ActionFrame(layers: [layer(x: 0, scale: 2), trueLayer], anchors: [], soundIndex: -1)
        let rendered = try ActionRenderer.render(action: SpriteAction(frames: [frame], frameDuration: 0.1), sprites: [red, blue], indexedCount: 1)
        #expect(rendered[0].width == 4 && rendered[0].height == 4)
        #expect(Array(rendered[0].rgba.prefix(4)) == [127, 0, 128, 255])
    }

    @Test func rejectsMissingImagesAndOversizedCanvas() throws {
        let missing = ActionFrame(layers: [layer(x: 0)], anchors: [], soundIndex: -1)
        #expect(throws: Error.self) {
            try ActionRenderer.render(action: SpriteAction(frames: [missing], frameDuration: 0.1), sprites: [], indexedCount: 0)
        }
        let sprite = SpriteFrame(width: 2, height: 2, rgba: Data(repeating: 255, count: 16))
        let huge = ActionFrame(layers: [layer(x: 0, scale: 3000)], anchors: [], soundIndex: -1)
        #expect(throws: Error.self) {
            try ActionRenderer.render(action: SpriteAction(frames: [huge], frameDuration: 0.1), sprites: [sprite], indexedCount: 1)
        }
    }

    private func layer(x: Int, mirror: Bool = false, scale: Double = 1, color: [UInt8] = [255,255,255,255]) -> ActionLayer {
        ActionLayer(offsetX: x, offsetY: 0, spriteIndex: 0, isTruecolor: false, mirror: mirror,
                    scaleX: scale, scaleY: scale, rotation: 0, color: color, width: 0, height: 0)
    }

    private func fixture(version: Int) -> Data {
        var d = Data([0x41, 0x43, UInt8(version & 255), UInt8(version >> 8), 1, 0])
        d.append(Data(repeating: 0, count: 10))
        append(1, to: &d)
        d.append(Data(repeating: 0, count: 32))
        append(1, to: &d)
        append(3, to: &d); append(-2, to: &d); append(0, to: &d); append(0, to: &d)
        if version >= 0x200 {
            d.append(contentsOf: [255, 128, 64, 255])
            appendFloat(1, to: &d)
            if version >= 0x204 { appendFloat(1, to: &d) }
            append(0, to: &d); append(0, to: &d)
            if version >= 0x205 { append(2, to: &d); append(1, to: &d) }
            append(0, to: &d)
        }
        if version >= 0x203 {
            append(1, to: &d); append(0, to: &d)
            append(17, to: &d); append(-4, to: &d); append(0, to: &d)
        }
        if version >= 0x201 {
            append(1, to: &d)
            d.append(Data("test.wav".utf8)); d.append(Data(repeating: 0, count: 32))
        }
        if version >= 0x202 { appendFloat(6, to: &d) }
        return d
    }
    private func append(_ value: Int, to data: inout Data) {
        let value = UInt32(truncatingIfNeeded: value)
        data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func appendFloat(_ value: Float, to data: inout Data) { append(Int(value.bitPattern), to: &data) }
}
