import Foundation
import Testing
@testable import GRFCore

struct LocalArchivePreviewTests {
    // Opt-in tests against local game assets; none are copied into the project.
    @Test func realArchiveSpritePreviews() throws {
        guard let directory = ProcessInfo.processInfo.environment["GRF_SAMPLE_DIRECTORY"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: directory).appendingPathComponent("cloud_sprite.grf"))
        let sprites = archive.entries.filter { $0.path.lowercased().hasSuffix(".spr") }
        #expect(!sprites.isEmpty)
        for entry in sprites.prefix(20) {
            do {
                let frames = try SpriteDecoder.frames(from: archive.data(for: entry))
                #expect(!frames.isEmpty, "No frames for \(entry.path)")
            } catch {
                Issue.record("Cannot preview \(entry.path): \(error.localizedDescription)")
            }
        }
    }
}
