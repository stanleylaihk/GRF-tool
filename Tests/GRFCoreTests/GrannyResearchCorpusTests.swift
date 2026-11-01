import Foundation
import Testing
@testable import GRFCore

struct GrannyResearchCorpusTests {
    @Test func exportLocalCorpusForDifferentialResearch() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_SCENE_ARCHIVE"],
              let destination = ProcessInfo.processInfo.environment["GRF_GRANNY_CORPUS"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        let directory = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifest: [String: String] = [:]
        for entry in archive.entries where (entry.path as NSString).pathExtension.lowercased() == "gr2" {
            let name = "\(entry.id).gr2"
            try archive.data(for: entry).write(to: directory.appendingPathComponent(name))
            manifest[name] = entry.path
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("paths.json"))
        #expect(!manifest.isEmpty)
    }
}
