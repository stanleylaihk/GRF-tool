import Foundation

public struct ResourceInspection: Sendable {
    public let summary: String
    public let strings: String
    public let hex: String
    public static func inspect(_ data: Data, name: String) -> Self {
        let bytes = Array(data.prefix(64 * 1024))
        var lines: [String] = []
        for p in stride(from: 0, to: bytes.count, by: 16) {
            let row = Array(bytes[p..<min(p+16, bytes.count)])
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ").padding(toLength: 47, withPad: " ", startingAt: 0)
            let chars = row.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append(String(format: "%08X  ", p) + hex + "  " + chars)
        }
        var readable: [String] = [], run: [UInt8] = []
        for b in bytes + [0] {
            if (32...126).contains(b) { run.append(b) }
            else { if run.count >= 4 { readable.append(String(decoding: run, as: UTF8.self)) }; run = [] }
        }
        let suffix = data.count > bytes.count ? "\nShowing the first 64 KiB. Extract to inspect the complete file." : ""
        return Self(summary: "\(name)\n\(data.count.formatted()) bytes\n\nNo specialized decoder recognized this content. The views below expose original bytes without changing the file." + suffix,
                    strings: readable.isEmpty ? "No ASCII strings of four or more characters in the sample." : readable.joined(separator: "\n"), hex: lines.joined(separator: "\n") + suffix)
    }
}
public struct ContentSearchHit: Identifiable, Sendable {
    public var id: Int { resourceID }
    public let resourceID: Int
    public let path: String
    public let count: Int
    public let line: Int
    public let snippet: String
}
public enum ResourceSearch {
    public static let textExtensions: Set<String> = ["txt","json","xml","csv","tsv","ini","cfg","conf","log","md","lua","lub","yaml","yml","toml","sql","bat","html","htm","js","css","fx","glsl"]
    public static func matchesName(_ path: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if query.contains("*") || query.contains("?") {
            let pattern = "^" + NSRegularExpression.escapedPattern(for: query).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return [path, (path as NSString).lastPathComponent].contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
        return path.localizedCaseInsensitiveContains(query)
    }
    public static func hit(_ data: Data, resourceID: Int, path: String, query: String) throws -> ContentSearchHit? {
        guard !query.isEmpty else { return nil }
        guard data.count <= 16 * 1024 * 1024 else { throw GRFError.invalid("Content search limit: 16 MiB per file.") }
        let text = try TextPreviewDecoder.preview(data, maximumBytes: 16 * 1024 * 1024).text
        let ns = text as NSString
        var remaining = NSRange(location: 0, length: ns.length), count = 0, first: NSRange?
        while remaining.length > 0 {
            let match = ns.range(of: query, options: [.caseInsensitive], range: remaining)
            if match.location == NSNotFound { break }
            if first == nil { first = match }; count += 1
            let next = match.location + max(1, match.length)
            remaining = NSRange(location: next, length: ns.length - next)
        }
        guard let first else { return nil }
        let line = ns.substring(to: first.location).filter { $0 == "\n" }.count + 1
        let snippetStart = max(0, first.location-65), snippetEnd = min(ns.length, first.location + first.length + 95)
        let snippet = ns.substring(with: NSRange(location: snippetStart, length: snippetEnd-snippetStart)).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ⏎ ")
        return ContentSearchHit(resourceID: resourceID, path: path, count: count, line: line, snippet: snippet)
    }
}
