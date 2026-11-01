import Foundation

public struct PaletteColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8
}

public enum PaletteDecoder {
    /// RO PAL files are exactly 256 RGBA entries. Alpha is ignored for indexed SPRs.
    public static func colors(from data: Data) throws -> [PaletteColor] {
        guard data.count == 1024 else { throw GRFError.invalid("A PAL file must contain 256 RGBA colors (1024 bytes).") }
        let b = Array(data)
        return stride(from: 0, to: b.count, by: 4).map {
            PaletteColor(red: b[$0], green: b[$0 + 1], blue: b[$0 + 2], alpha: b[$0 + 3])
        }
    }
}
