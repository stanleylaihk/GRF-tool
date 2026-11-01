import Foundation

public enum SpriteExporter {
    /// Indexed frames export as 256-color BMP when opaque; otherwise use V5 RGBA BMP.
    public static func bmp(frame: SpriteFrame, transparent: Bool = true) throws -> Data {
        guard frame.width > 0, frame.height > 0, frame.width <= 65535, frame.height <= 65535,
              frame.width * frame.height <= 16_777_216, frame.rgba.count == frame.width * frame.height * 4 else {
            throw GRFError.invalid("Cannot export invalid sprite dimensions or pixels.")
        }
        if !transparent, let indices = frame.indexedPixels, let palette = frame.palette,
           indices.count == frame.width * frame.height, palette.count == 1024 {
            let stride = (frame.width + 3) & ~3
            let imageBytes = stride * frame.height
            var out = Data([0x42, 0x4d])
            out.le32(14 + 40 + 1024 + imageBytes); out.le32(0); out.le32(14 + 40 + 1024)
            out.le32(40); out.le32(frame.width); out.le32(frame.height)
            out.le16(1); out.le16(8); out.le32(0); out.le32(imageBytes)
            out.le32(2835); out.le32(2835); out.le32(256); out.le32(256)
            let p = Array(palette), pixels = Array(indices)
            for color in 0..<256 {
                out.append(contentsOf: [p[color * 4 + 2], p[color * 4 + 1], p[color * 4], 0])
            }
            for y in (0..<frame.height).reversed() {
                out.append(contentsOf: pixels[(y * frame.width)..<((y + 1) * frame.width)])
                out.append(Data(repeating: 0, count: stride - frame.width))
            }
            return out
        }
        let imageBytes = frame.rgba.count
        var out = Data([0x42, 0x4d])
        out.le32(14 + 124 + imageBytes); out.le32(0); out.le32(14 + 124)
        out.le32(124); out.le32(frame.width); out.le32(frame.height)
        out.le16(1); out.le16(32); out.le32(3); out.le32(imageBytes)
        out.le32(2835); out.le32(2835); out.le32(0); out.le32(0)
        out.le32(0x00ff0000); out.le32(0x0000ff00); out.le32(0x000000ff); out.le32(0xff000000)
        out.le32(0x73524742) // LCS_sRGB; endpoints and gamma are unused.
        out.append(Data(repeating: 0, count: 48))
        // ImageIO accepts V5 with alpha masks, but rejects otherwise-valid V4 BMPs.
        out.le32(4); out.le32(0); out.le32(0); out.le32(0)
        let pixels = Array(frame.rgba)
        for y in (0..<frame.height).reversed() {
            for x in 0..<frame.width {
                let p = (y * frame.width + x) * 4
                out.append(contentsOf: [pixels[p + 2], pixels[p + 1], pixels[p], transparent ? pixels[p + 3] : 255])
            }
        }
        return out
    }
}

private extension Data {
    mutating func le16(_ n: Int) { append(contentsOf: [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8)]) }
    mutating func le32(_ n: Int) { append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
}
