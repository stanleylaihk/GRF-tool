import Foundation

/// Decompresses GR2 v6 sections without applying pointer fixups, marshalling,
/// or interpreting the resulting object tree. Returned indices match the file.
public enum GrannySectionDecoder {
    public static func decode(_ data: Data) throws -> [Data] {
        let document = try GrannyPreviewDocument.decode(data)
        let limit = 64 * 1024 * 1024
        var total = 0
        for section in document.sections {
            guard Int(section.unpackedByteCount) <= limit - total else {
                throw GRFError.invalid("GR2 decompressed sections exceed the 64 MiB preview limit.")
            }
            total += Int(section.unpackedByteCount)
        }
        let bytes = Array(data)
        func u32(_ p: Int) -> Int {
            Int(bytes[p]) | Int(bytes[p+1]) << 8 | Int(bytes[p+2]) << 16 | Int(bytes[p+3]) << 24
        }
        let table = 32 + u32(44)
        return try document.sections.map { section in
            let start = Int(section.fileOffset), count = Int(section.storedByteCount)
            let input = Data(bytes[start..<start+count])
            if section.unpackedByteCount == 0 {
                guard count == 0 else { throw GRFError.invalid("Nonempty GR2 section declares zero expanded size.") }
                return Data()
            }
            switch section.compressionMode {
            case 0: return input
            case 1:
                let p = table + section.id * 44
                return try Oodle0Decoder.decompress(input, expandedSize: Int(section.unpackedByteCount),
                    first16Bit: u32(p+20), first8Bit: u32(p+24))
            default: throw GRFError.invalid("GR2 section \(section.id) uses unsupported \(section.compressionLabel) compression.")
            }
        }
    }
}
