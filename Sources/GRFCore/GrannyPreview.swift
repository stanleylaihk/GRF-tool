import Foundation

public struct GrannyPreviewSection: Codable, Sendable, Identifiable {
    public let id: Int
    public let compressionMode: UInt32
    public let fileOffset: UInt32
    public let storedByteCount: UInt32
    public let unpackedByteCount: UInt32
    public let alignment: UInt32
    public let relocationOffset: UInt32
    public let relocationCount: UInt32
    public let marshallingOffset: UInt32
    public let marshallingCount: UInt32
    public var compressionLabel: String {
        switch compressionMode {
        case 0: return "Uncompressed"
        case 1: return "Oodle-0"
        case 2: return "Oodle-1"
        default: return "Unknown (\(compressionMode))"
        }
    }
}

/// Physical GR2 metadata. GrannyScene separately reconstructs geometry,
/// embedded textures and a static pose for the model preview.
public struct GrannyPreviewDocument: Codable, Sendable {
    public let version: UInt32
    public let fileByteCount: Int
    public let headerByteCount: Int
    public let checksumHex: String
    public let sections: [GrannyPreviewSection]
    public let notes: [String]

    public var readableSummary: String {
        var lines = ["Granny GR2 · version \(version)",
                     "\(fileByteCount) bytes · \(sections.count) sections · little-endian, 32-bit",
                     "", "Physical metadata; use Wireframe / Textured for the model preview.", ""]
        for section in sections {
            lines.append("Section \(section.id): \(section.compressionLabel)")
            lines.append("  File offset: \(section.fileOffset) · Stored: \(section.storedByteCount) bytes · Unpacked: \(section.unpackedByteCount) bytes")
        }
        lines += [""] + notes
        return lines.joined(separator: "\n")
    }

    public func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count >= 88, data.count <= 64 * 1024 * 1024 else {
            throw GRFError.invalid("GR2 preview requires a complete file of 88 bytes to 64 MiB.")
        }
        let bytes = Array(data)
        let signature: [UInt8] = [0xb8, 0x67, 0xb0, 0xca, 0xf8, 0x6d, 0xb1, 0x0f, 0x84, 0x72, 0x8c, 0x7e, 0x5e, 0x19, 0x00, 0x1e]
        guard Array(bytes.prefix(16)) == signature else {
            throw GRFError.invalid("Unsupported GR2 signature. This preview supports RO's version 6 little-endian 32-bit format.")
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        let headerSize = Int(u32(16)), version = u32(32), fileSize = Int(u32(36))
        guard u32(20) == 0, version == 6 else {
            throw GRFError.invalid("Unsupported GR2 header compression or version (\(version)).")
        }
        guard fileSize == bytes.count else { throw GRFError.invalid("GR2 file size does not match its header.") }
        // The section-table offset is relative to the 32-byte magic structure.
        let sectionOffset = 32 + Int(u32(44)), sectionCount = Int(u32(48))
        guard sectionCount > 0, sectionCount <= 256,
              sectionOffset >= 88, headerSize <= bytes.count,
              sectionOffset <= headerSize, sectionCount <= (headerSize - sectionOffset) / 44 else {
            throw GRFError.invalid("Invalid GR2 section table.")
        }
        var sections: [GrannyPreviewSection] = []
        for i in 0..<sectionCount {
            let p = sectionOffset + i * 44
            let mode = u32(p), offset = u32(p + 4), stored = u32(p + 8), unpacked = u32(p + 12)
            guard Int(offset) <= fileSize, Int(stored) <= fileSize - Int(offset),
                  stored == 0 || Int(offset) >= headerSize,
                  mode != 0 || stored == unpacked else {
                throw GRFError.invalid("Invalid GR2 section \(i) data range or size.")
            }
            sections.append(GrannyPreviewSection(id: i, compressionMode: mode, fileOffset: offset,
                storedByteCount: stored, unpackedByteCount: unpacked, alignment: u32(p + 16),
                relocationOffset: u32(p + 28), relocationCount: u32(p + 32),
                marshallingOffset: u32(p + 36), marshallingCount: u32(p + 40)))
        }
        let modes = Set(sections.filter { $0.storedByteCount > 0 }.map(\.compressionMode))
        var notes = ["The checksum is shown as stored; it has not been verified.",
                     "Geometry, textures, skeletons and animation counts cannot be inferred from section sizes."]
        if modes.contains(1) {
            notes.insert("This file uses Oodle-0 compression. Native Oodle-0 section decompression is available. The model preview reconstructs supported meshes and embedded textures.", at: 0)
        } else {
            notes.insert("This metadata panel reads the physical header and section table; the model preview is separate.", at: 0)
        }
        return Self(version: version, fileByteCount: fileSize, headerByteCount: headerSize,
                    checksumHex: String(format: "%08X", u32(40)), sections: sections, notes: notes)
    }
}
