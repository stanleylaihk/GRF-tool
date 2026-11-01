import Foundation
import Darwin

public enum DraftExtraction {
    public static func write(_ file: GRFBuildFile, to destination: URL, cancelled: () -> Bool = { false }) throws {
        let components = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") && !$0.contains("\\") && !$0.contains("\0") }) else { throw GRFError.invalid("Unsafe extraction path: \(file.path)") }
        var dir = Darwin.open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else { throw GRFError.invalid("Cannot access extraction folder.") }
        defer { close(dir) }
        for component in components.dropLast() {
            guard mkdirat(dir, component, 0o755) == 0 || errno == EEXIST else { throw GRFError.invalid("Cannot create output directory.") }
            let next = openat(dir, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw GRFError.invalid("Unsafe output directory.") }
            close(dir); dir = next
        }
        let bytes = try file.data(limit: 512 * 1024 * 1024)
        if cancelled() { throw GRFError.cancelled }
        let name = components.last!
        let output = openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard output >= 0 else { throw GRFError.invalid("Output already exists or cannot be created: \(file.path)") }
        var success = false
        defer { close(output); if !success { unlinkat(dir, name, 0) } }
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                if cancelled() { throw GRFError.cancelled }
                let n = Darwin.write(output, raw.baseAddress!.advanced(by: offset), min(1024 * 1024, raw.count-offset))
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw GRFError.invalid("Extraction write failed.") }; offset += n
            }
        }
        success = true
    }
}
