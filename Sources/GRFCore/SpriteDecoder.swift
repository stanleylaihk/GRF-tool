import Foundation

public struct SpriteFrame: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data
    public let indexedPixels: Data?
    public let palette: Data?
    public init(width: Int, height: Int, rgba: Data, indexedPixels: Data? = nil, palette: Data? = nil) {
        self.width = width; self.height = height; self.rgba = rgba
        self.indexedPixels = indexedPixels; self.palette = palette
    }
}

public struct SpriteDocument: Sendable {
    public let frames: [SpriteFrame]
    public let indexedFrameCount: Int
    public let palette: Data?
}

public enum SpriteDecoder {
    /// SPR 1.0/1.1, 2.0 and 2.1. Indexed pixels use palette index zero for transparency.
    public static func frames(from data: Data) throws -> [SpriteFrame] {
        try document(from: data).frames
    }

    public static func document(from data: Data, palette override: Data? = nil) throws -> SpriteDocument {
        var reader = BinaryReader(data)
        guard try reader.take(2) == [0x53, 0x50] else { throw GRFError.invalid("Invalid SPR signature.") }
        let minor = try reader.u8(), major = try reader.u8()
        guard (major == 1 && minor <= 1) || (major == 2 && minor <= 1) else {
            throw GRFError.invalid("Unsupported SPR version \(major).\(minor).")
        }
        let indexedCount = try reader.u16()
        let truecolorCount = major >= 2 ? try reader.u16() : 0
        guard indexedCount + truecolorCount <= 10000 else { throw GRFError.invalid("Too many sprite frames.") }
        let palette: [UInt8]
        if indexedCount > 0 {
            guard data.count >= reader.offset + 1024 else { throw GRFError.invalid("Missing sprite palette.") }
            if let override {
                _ = try PaletteDecoder.colors(from: override)
                palette = Array(override)
            } else { palette = Array(data.suffix(1024)) }
        } else { palette = [] }
        let frameDataEnd = data.count - (indexedCount > 0 ? 1024 : 0)
        var frames: [SpriteFrame] = []
        var decodedBytes = 0
        for i in 0..<(indexedCount + truecolorCount) {
            let width = try reader.u16(), height = try reader.u16()
            let pixels = width * height
            guard width > 0, height > 0, pixels <= 16_777_216,
                  decodedBytes + pixels * 4 <= 256 * 1024 * 1024 else {
                throw GRFError.invalid("Invalid sprite dimensions or decoded sprite exceeds 256 MiB.")
            }
            decodedBytes += pixels * 4
            var rgba = [UInt8](repeating: 0, count: pixels * 4)
            var indexedPixels: Data?
            if i < indexedCount {
                let indices: [UInt8]
                if major == 2 && minor >= 1 {
                    let compressedLength = try reader.u16()
                    var compressed = BinaryReader(Data(try reader.take(compressedLength)))
                    var expanded: [UInt8] = []
                    expanded.reserveCapacity(pixels)
                    while compressed.remaining > 0 {
                        let value = try compressed.u8()
                        if value == 0 {
                            let run = Int(try compressed.u8())
                            guard run > 0, run <= pixels - expanded.count else { throw GRFError.invalid("Invalid SPR zero run.") }
                            expanded.append(contentsOf: repeatElement(0, count: run))
                        } else {
                            guard expanded.count < pixels else { throw GRFError.invalid("SPR pixels exceed frame dimensions.") }
                            expanded.append(value)
                        }
                    }
                    guard expanded.count == pixels else { throw GRFError.invalid("Truncated SPR frame.") }
                    indices = expanded
                } else {
                    indices = try reader.take(pixels)
                }
                indexedPixels = Data(indices)
                for pixel in 0..<pixels {
                    let color = Int(indices[pixel]) * 4
                    rgba[pixel * 4] = palette[color]
                    rgba[pixel * 4 + 1] = palette[color + 1]
                    rgba[pixel * 4 + 2] = palette[color + 2]
                    rgba[pixel * 4 + 3] = indices[pixel] == 0 ? 0 : 255
                }
            } else {
                let abgr = try reader.take(pixels * 4)
                // Truecolor SPR rows are stored bottom-up, with ABGR channel order.
                for y in 0..<height {
                    for x in 0..<width {
                        let src = ((height - 1 - y) * width + x) * 4
                        let dst = (y * width + x) * 4
                        rgba[dst] = abgr[src + 3]
                        rgba[dst + 1] = abgr[src + 2]
                        rgba[dst + 2] = abgr[src + 1]
                        rgba[dst + 3] = abgr[src]
                    }
                }
            }
            guard reader.offset <= frameDataEnd else { throw GRFError.invalid("SPR image overlaps its palette.") }
            frames.append(SpriteFrame(width: width, height: height, rgba: Data(rgba), indexedPixels: indexedPixels,
                                      palette: i < indexedCount ? Data(palette) : nil))
        }
        return SpriteDocument(frames: frames, indexedFrameCount: indexedCount, palette: indexedCount > 0 ? Data(palette) : nil)
    }
}
