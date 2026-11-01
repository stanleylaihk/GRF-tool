import Foundation

public enum TextPreviewEncoding: String, CaseIterable, Sendable {
    case automatic, utf8, korean, traditionalChinese, utf16, latin1, mixedChineseKorean
    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .mixedChineseKorean: return "Mixed Big5 / Korean (per line)"
        case .utf8: return "UTF-8"
        case .korean: return "Korean (CP949)"
        case .traditionalChinese: return "Traditional Chinese (CP950 / Big5)"
        case .utf16: return "UTF-16"
        case .latin1: return "Western (Latin-1)"
        }
    }
}

public struct TextPreview: Sendable {
    public let text: String
    public let encodingLabel: String
    public let warning: String?
    public init(text: String, encodingLabel: String, warning: String? = nil) {
        self.text = text; self.encodingLabel = encodingLabel; self.warning = warning
    }
}

/// Content encodings are independent of the archive's filename encoding.
public enum TextPreviewDecoder {
    public static let limit = 2 * 1024 * 1024
    public static func preview(_ data: Data, encoding: TextPreviewEncoding = .automatic, maximumBytes: Int = limit) throws -> TextPreview {
        let sample = Data(data.prefix(max(0, maximumBytes)))
        let truncated = sample.count < data.count
        let suffix = truncated ? "\n\n[Preview truncated at 2 MiB. Extract the file to read the complete text.]" : ""
        if encoding == .mixedChineseKorean {
            return try mixedPreview(sample, truncated: truncated, suffix: suffix)
        }
        let candidates: [TextPreviewEncoding]
        if encoding != .automatic { candidates = [encoding] }
        else if sample.starts(with: [0xff, 0xfe]) || sample.starts(with: [0xfe, 0xff]) { candidates = [.utf16] }
        else { candidates = [.utf8, .korean, .traditionalChinese] }
        for candidate in candidates {
            for trim in 0...(truncated ? min(3, sample.count) : 0) {
                let bytes = Data(sample.dropLast(trim))
                let text: String?
                switch candidate {
                case .utf8: text = String(data: bytes, encoding: .utf8)
                case .utf16: text = String(data: bytes, encoding: .utf16)
                case .korean: text = try? FilenameEncoding.korean.decode(bytes)
                case .traditionalChinese: text = try? FilenameEncoding.traditionalChinese.decode(bytes)
                case .latin1: text = try? FilenameEncoding.latin1.decode(bytes)
                case .automatic, .mixedChineseKorean: text = nil
                }
                if let text {
                    return TextPreview(text: text + suffix, encodingLabel: candidate.label)
                }
            }
        }
        if encoding == .automatic, !sample.starts(with: [0xff, 0xfe]), !sample.starts(with: [0xfe, 0xff]),
           let recovered = try? mixedPreview(sample, truncated: truncated, suffix: suffix) {
            return recovered
        }
        throw GRFError.invalid("Unable to decode this text using \(encoding.label). Choose another Text Encoding in the preview. Text encoding does not change archive filenames.")
    }

    // Recovery is deliberately separate from strict single-encoding modes. Some
    // translated RO books retain Korean source paragraphs after Big5 paragraphs.
    private static func mixedPreview(_ sample: Data, truncated: Bool, suffix: String) throws -> TextPreview {
        let lines = sample.split(separator: 10, omittingEmptySubsequences: false)
        var decoded: [String] = []
        var usedChinese = false, usedKorean = false
        for (index, line) in lines.enumerated() {
            var bytes = Data(line)
            var chosen: String?
            for trim in 0...((truncated && index == lines.count - 1) ? min(1, bytes.count) : 0) {
                bytes = Data(line.dropLast(trim))
                if let unicode = String(data: bytes, encoding: .utf8) { chosen = unicode; break }
                let chinese = try? FilenameEncoding.traditionalChinese.decode(bytes)
                let korean = try? FilenameEncoding.korean.decode(bytes)
                let nonASCII: [Unicode.Scalar] = Array((korean ?? "").unicodeScalars).filter { $0.value >= 128 }
                let hangul = nonASCII.filter { (0xac00...0xd7a3).contains($0.value) }.count
                if let korean, chinese == nil || (hangul >= 6 && Double(hangul) / Double(nonASCII.count) >= 0.7) {
                    chosen = korean; usedKorean = true; break
                }
                if let chinese { chosen = chinese; usedChinese = true; break }
            }
            guard let chosen else { throw GRFError.invalid("Cannot recover mixed text at line \(index + 1). Choose a single text encoding or extract the original file.") }
            decoded.append(chosen)
        }
        guard usedChinese && usedKorean else {
            throw GRFError.invalid("No recoverable Big5 / Korean mixture found. Choose a single text encoding.")
        }
        return TextPreview(text: decoded.joined(separator: "\n") + suffix,
            encodingLabel: TextPreviewEncoding.mixedChineseKorean.label,
            warning: "Mixed encodings recovered per line using a language heuristic. Ambiguous lines may be misidentified; choose a single encoding to inspect the original interpretation. The file is unchanged.")
    }

}
