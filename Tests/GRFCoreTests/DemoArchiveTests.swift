import Foundation
import Testing
@testable import GRFCore

/// Optional local integration test; user game assets are never committed.
struct DemoArchiveTests {
    @Test func suppliedFdataFullyExtracts() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        for name in ["fdata.grf", "RO 私服/fdata.grf"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let archive = try GRFArchive(url: url)
            let broken = try #require(archive.entries.first { $0.path == "data/etcinfo.txt" })
            do {
                _ = try archive.data(for: broken)
                Issue.record("The supplied truncated etcinfo.txt must not be accepted as complete.")
            } catch GRFError.unreadableResource(let path, let reason) {
                #expect(path == broken.path)
                #expect(reason.contains("zlib"))
            }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: output) }
            let report = try archive.extract(entries: archive.entries, to: output, skipUnreadableFiles: true)
            #expect(report.extractedCount == 189)
            #expect(report.failures.map(\.path) == ["data/etcinfo.txt"])
            #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent(broken.path).path))
            for entry in archive.entries where entry.id != broken.id {
                #expect(try Data(contentsOf: output.appendingPathComponent(entry.path)) == archive.data(for: entry))
            }
        }
    }

    @Test func suppliedSpritesDecode() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        for filename in ["adata.grf", "fdata.grf"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let archive = try GRFArchive(url: url)
            let sprites = archive.entries.filter { $0.path.lowercased().hasSuffix(".spr") }
            #expect(!sprites.isEmpty)
            for entry in sprites {
                do {
                    let frames = try SpriteDecoder.frames(from: archive.data(for: entry))
                    #expect(!frames.isEmpty, "\(filename): \(entry.path)")
                } catch {
                    Issue.record("\(filename): \(entry.path): \(error.localizedDescription)")
                }
            }
        }
    }

    @Test func customPayloadArchivesGiveActionableErrors() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        for filename in ["cloud_sprite.grf", "cloud_hair.grf", "cloud_main.grf", "cloud_big.grf", "cloud_pal.grf", "cloud_update.grf"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let archive = try GRFArchive(url: url)
            let entry = try #require(archive.entries.first)
            do {
                _ = try archive.data(for: entry)
                Issue.record("Expected the supplied custom-encoded archive to report its unsupported payload.")
            } catch {
                #expect(error.localizedDescription.contains("client decoder/key"))
            }
        }
    }
}
