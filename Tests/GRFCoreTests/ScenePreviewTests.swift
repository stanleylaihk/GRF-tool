import Foundation
import Testing
@testable import GRFCore

struct ScenePreviewTests {
    func u(_ n: Int) -> Data { var value = UInt32(truncatingIfNeeded: n).littleEndian; return withUnsafeBytes(of: &value) { Data($0) } }
    func f(_ n: Float) -> Data { u(Int(n.bitPattern)) }
    func name(_ s: String, _ length: Int) -> Data { Data(s.utf8) + Data(count: length - s.utf8.count) }
    func imf() -> Data { f(1.01) + u(0) + u(1) + u(1) + u(7) + u(-12) + u(24) }
    func model() -> Data {
        var d = Data("GRSM".utf8) + Data([1, 4]) + u(0) + u(0) + Data([255]) + Data(count: 16)
        d += u(1) + name("wall.bmp", 40) + name("root", 40) + u(1)
        d += name("root", 40) + name("", 40) + u(1) + u(0)
        for value: Float in [1,0,0,0,1,0,0,0,1, 0,0,0, 0,0,0, 0, 0,1,0, 1,1,1] { d += f(value) }
        d += u(3)
        for value: Float in [0,0,0, 1,0,0, 0,1,0] { d += f(value) }
        d += u(1) + Data(count: 12) + u(1)
        d += Data([0,0,1,0,2,0, 0,0,0,0,0,0, 0,0,0,0]) + u(0) + u(0)
        d += u(0)
        return d
    }
    @Test func layerOriginsAndJSON() throws {
        let doc = try ScenePreviewDocument.decode(imf(), extension: "imf")
        #expect(doc.markers.count == 1)
        #expect(doc.markers[0].position.x == -12)
        #expect(doc.markers[0].position.y == 24)
        #expect(try doc.json().contains("Layer 0"))
    }
    @Test func modelTriangle() throws {
        let doc = try ScenePreviewDocument.decode(model(), extension: "rsm")
        #expect(doc.meshes.count == 1)
        #expect(doc.meshes[0].indices == [0, 1, 2])
        #expect(doc.references == ["wall.bmp"])
    }
    @Test func worldModelPlacement() throws {
        var d = Data("GRSW".utf8) + Data([2, 1])
        for s in ["", "town.gnd", "town.gat", ""] { d += name(s, 40) }
        d += Data(count: 24 + 36 + 16) + u(1) + u(1)
        d += name("Tree", 40) + Data(count: 12) + name("tree.rsm", 80) + name("", 80)
        d += f(10) + f(-20) + f(30) + Data(count: 24)
        let doc = try ScenePreviewDocument.decode(d, extension: "rsw")
        #expect(doc.markers.count == 1)
        #expect(doc.markers[0].resource == "tree.rsm")
        #expect(doc.markers[0].position.z == 30)
        #expect(doc.references[1] == "town.gnd")
    }
    @Test func rejectsTruncationAndHostileCounts() throws {
        for (ext, bytes) in [("imf", imf()), ("rsm", model())] {
            for n in 0..<bytes.count {
                #expect(throws: (any Error).self) { _ = try ScenePreviewDocument.decode(Data(bytes.prefix(n)), extension: ext) }
            }
        }
        #expect(throws: (any Error).self) { _ = try ScenePreviewDocument.decode(f(1.01) + u(0) + u(-1), extension: "imf") }
    }
    @Test func localSceneResources() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_SCENE_ARCHIVE"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        for ext in ["rsw", "rsm", "imf"] {
            let entries = archive.entries.filter { ($0.path as NSString).pathExtension.lowercased() == ext }
            for entry in entries.prefix(30) {
                let bytes = try archive.data(for: entry)
                let doc = try ScenePreviewDocument.decode(bytes, extension: ext)
                if entry.id == entries.first?.id, let directory = ProcessInfo.processInfo.environment["GRF_SCENE_SAMPLES"] {
                    try bytes.write(to: URL(fileURLWithPath: directory).appendingPathComponent("sample." + ext))
                }
                #expect(doc.kind == ext.uppercased())
            }
            print("Validated \(min(30, entries.count)) \(ext) resources")
        }
    }
}
