import Foundation
import Testing
@testable import GRFCore

struct ActionDemoTests {
    @Test func suppliedActionsDecodeAndRender() throws {
        guard let root = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        var decodedCount = 0, pairedCount = 0, actionCount = 0, frameCount = 0, layerCount = 0
        var missingCompanions = 0, emptyActions = 0
        for filename in ["adata.grf", "fdata.grf"] {
            let url = URL(fileURLWithPath: root).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let archive = try GRFArchive(url: url)
            let byPath = Dictionary(archive.entries.map { ($0.path.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            for entry in archive.entries where entry.path.lowercased().hasSuffix(".act") {
                do {
                    let document = try ActionDecoder.decode(archive.data(for: entry))
                    decodedCount += 1
                    actionCount += document.actions.count
                    frameCount += document.actions.reduce(0) { $0 + $1.frames.count }
                    layerCount += document.actions.flatMap(\.frames).reduce(0) { $0 + $1.layers.count }
                    let spritePath = String(entry.path.dropLast(4)).lowercased() + ".spr"
                    guard let companion = byPath[spritePath] else { missingCompanions += 1; continue }
                    let sprites = try SpriteDecoder.document(from: archive.data(for: companion))
                    guard let action = document.actions.first(where: { $0.frames.contains { $0.layers.contains { $0.spriteIndex >= 0 } } }) else { emptyActions += 1; continue }
                    let rendered = try ActionRenderer.render(action: action, sprites: sprites.frames, indexedCount: sprites.indexedFrameCount)
                    #expect(!rendered.isEmpty, "\(filename): \(entry.path)")
                    #expect(rendered.contains { $0.rgba.enumerated().contains { $0.offset % 4 == 3 && $0.element > 0 } }, "Blank action: \(entry.path)")
                    pairedCount += 1
                } catch {
                    Issue.record("\(filename): \(entry.path): \(error.localizedDescription)")
                }
            }
        }
        print("ACT demo integration: decoded=\(decodedCount), rendered=\(pairedCount), missingCompanions=\(missingCompanions), emptyActions=\(emptyActions), actions=\(actionCount), frames=\(frameCount), layers=\(layerCount)")
        #expect(decodedCount > 0)
        #expect(pairedCount > 0)
    }
}
