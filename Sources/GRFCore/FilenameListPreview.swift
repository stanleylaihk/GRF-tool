import Foundation

/// RO FNA files contain repeated little-endian lengths followed by encoded paths.
/// These are historical resource references, not paths to open on the host machine.
public struct FilenameListPreview: Codable, Sendable {
    public let files: [String]
    public var readableSummary: String {
        (["FNA resource references · \(files.count) files", "",
          "This file lists sprite resources; it contains no image or animation frames.",
          "Original authoring paths are shown as stored and are not opened automatically.", ""]
          + files.enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n")
    }
    public func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
    public static func decode(_ data: Data, encoding: FilenameEncoding = .korean) throws -> Self {
        guard data.count <= 2 * 1024 * 1024 else { throw GRFError.invalid("FNA preview exceeds the 2 MiB limit.") }
        var reader = BinaryReader(data), files: [String] = []
        while reader.remaining > 0 {
            let length = try reader.u32()
            guard length > 0, length <= 32_768, files.count < 10_000 else { throw GRFError.invalid("Invalid FNA path length or count.") }
            let bytes = try reader.take(length)
            guard bytes.last == 0, !bytes.dropLast().contains(0) else { throw GRFError.invalid("Invalid FNA path terminator.") }
            files.append(try encoding.decode(Data(bytes.dropLast())))
        }
        return Self(files: files)
    }
}
