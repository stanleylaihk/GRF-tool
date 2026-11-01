import Foundation
import Testing
@testable import GRFCore

private final class MapExportStop: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func stop() { lock.lock(); value = true; lock.unlock() }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct MapPreviewTests {
    private func u32(_ value: Int) -> Data {
        var raw = UInt32(truncatingIfNeeded: value).littleEndian
        return withUnsafeBytes(of: &raw) { Data($0) }
    }
    private func f32(_ value: Float) -> Data { u32(Int(value.bitPattern)) }
    private func gat(width: Int = 3, height: Int = 2, minor: UInt8 = 2) -> Data {
        var data = Data("GRAT".utf8) + Data([1, minor]) + u32(width) + u32(height)
        for i in 0..<(width * height) {
            for j in 0..<4 { data += f32(Float(i * 10 + j)) }
            data += u32([0, 1, 3, 5, 99, 0x8001][i % 6])
        }
        return data
    }
    private func gnd(minor: UInt8 = 7, grid: Int = 1) -> Data {
        var data = Data("GRGN".utf8) + Data([1, minor]) + u32(3) + u32(2) + f32(10)
        data += u32(1) + u32(80)
        data += Data("grass.bmp".utf8) + Data(count: 71)
        data += u32(1) + u32(8) + u32(8) + u32(grid)
        data += Data(repeating: 0xab, count: 256 * grid)
        data += u32(1)
        for f: Float in [0, 1, 0, 1, 0, 0, 1, 1] { data += f32(f) }
        data += Data([0, 0, 0, 0, 1, 2, 3, 4])
        for i in 0..<6 {
            for j in 0..<4 { data += f32(-Float(i * 10 + j)) }
            data += u32(i == 0 ? -1 : 0) + u32(-1) + u32(0)
        }
        return data
    }
    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("grf-map-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func gatKeepsRowOrderCornerHeightsRawFlagsAndUnknownTypes() throws {
        let map = try MapDocument.decode(gat(minor: 3))
        #expect(map.kind == .gat && map.width == 3 && map.height == 2)
        #expect(map.summary.version == "1.3")
        #expect(map.summary.minimumFileHeight == 0 && map.summary.maximumFileHeight == 53)
        let selected = try #require(map.cell(x: 2, y: 1))
        #expect(selected.heights == [50, 51, 52, 53])
        #expect(selected.rawTerrainType == 0x8001 && selected.terrainType == 1)
        #expect(selected.terrainLabel == "Blocked")
        #expect(map.cell(x: 1, y: 1)?.terrainLabel == "Type 99")
        #expect(map.summary.terrainCounts == ["0": 1, "1": 2, "3": 1, "5": 1, "99": 1])
        #expect(map.cell(x: -1, y: 0) == nil && map.cell(x: 3, y: 0) == nil && map.cell(x: 0, y: 2) == nil)
        let pixels = Array(map.raster().rgba)
        #expect(Array(pixels[0..<4]) == [81, 179, 118, 255])
        #expect(Array(pixels[8..<12]) == [65, 149, 231, 255])
        #expect(Array(pixels[12..<16]) == [231, 165, 66, 255])
        let json = try #require(JSONSerialization.jsonObject(with: Data(map.previewJSON(x: 2, y: 1).utf8)) as? [String: Any])
        let cell = try #require(json["selectedCell"] as? [String: Any])
        #expect(cell["x"] as? Int == 2 && cell["rawTerrainType"] as? Int == 0x8001)
    }

    @Test func gndSkipsLightmapsAndDecodesSurfaceReferencesAndSignedElevation() throws {
        for minor: UInt8 in [6, 7, 8, 9] {
            let map = try MapDocument.decode(gnd(minor: minor, grid: 2) + Data([0xde, 0xad]))
            #expect(map.kind == .gnd && map.summary.geometryScale == 10)
            #expect(map.textures == ["grass.bmp"])
            #expect(map.summary.lightmaps?.byteCount == 512)
            #expect(map.summary.additionalByteCount == 2)
            let cell = try #require(map.cell(x: 2, y: 1))
            #expect(cell.heights == [-50, -51, -52, -53])
            #expect(cell.surfaceIndices?.top == 0 && cell.surfaceIndices?.front == -1)
            let tile = try #require(map.surface(at: 0))
            #expect(tile.u == [0, 1, 0, 1] && tile.v == [0, 0, 1, 1])
            #expect(tile.colorBGRA == [1, 2, 3, 4] && tile.textureIndex == 0 && tile.lightmapIndex == 0)
            #expect(map.surface(at: -1) == nil && map.surface(at: 1) == nil)
            let pixels = Array(map.raster().rgba)
            #expect(Array(pixels[0..<4]) == [48, 51, 59, 255])
            #expect(pixels[20] > pixels[4]) // More negative file height means higher visible elevation.
        }
    }

    @Test func rejectsTruncationHugeDimensionsCountsAndUnsupportedVersions() throws {
        for bytes in [gat(), gnd()] {
            for count in [0, 4, 13, bytes.count - 1] {
                #expect(throws: GRFError.self) { try MapDocument.decode(bytes.prefix(count)) }
            }
        }
        var wrong = gat(); wrong[0] = 0
        #expect(throws: GRFError.self) { try MapDocument.decode(wrong) }
        wrong = gat(); wrong[5] = 9
        #expect(throws: GRFError.self) { try MapDocument.decode(wrong) }
        for width in [0, -1, 2049, 1001] {
            let bytes = Data("GRAT".utf8) + Data([1, 2]) + u32(width) + u32(1000)
            #expect(throws: GRFError.self) { try MapDocument.decode(bytes) }
        }
        wrong = gnd(); wrong.replaceSubrange(18..<22, with: u32(Int(UInt32.max)))
        #expect(throws: GRFError.self) { try MapDocument.decode(wrong) }
        #expect(throws: GRFError.self) { try MapDocument.decode(gat() + Data([0])) }
    }

    @Test func rejectsNonFiniteHeightsUVsAndInvalidScale() throws {
        for value: Float in [.nan, .infinity, -.infinity, 1e20] {
            var bytes = gat(); bytes.replaceSubrange(14..<18, with: f32(value))
            #expect(throws: GRFError.self) { try MapDocument.decode(bytes) }
            bytes = gnd(); bytes.replaceSubrange(382..<386, with: f32(value))
            #expect(throws: GRFError.self) { try MapDocument.decode(bytes) }
        }
        var bytes = gnd(); bytes.replaceSubrange(14..<18, with: f32(0))
        #expect(throws: GRFError.self) { try MapDocument.decode(bytes) }
    }

    @Test func streamedJSONPreservesEveryCellSurfaceAndBinaryExtension() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        for (i, bytes) in [gat(minor: 3), gnd() + Data([0xde, 0xad])].enumerated() {
            let doc = try MapDocument.decode(bytes), url = root.appendingPathComponent("map-\(i).json")
            try doc.writeJSON(to: url)
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let cells = try #require(json["cells"] as? [[String: Any]])
            #expect(cells.count == doc.summary.cellCount)
            #expect(cells.last?["x"] as? Int == 2 && cells.last?["y"] as? Int == 1)
            if i == 1 {
                let tiles = try #require(json["surfaces"] as? [[String: Any]])
                #expect(tiles.count == 1 && tiles[0]["textureIndex"] as? Int == 0)
                #expect(Data(base64Encoded: json["lightmapDataBase64"] as? String ?? "") == Data(repeating: 0xab, count: 256))
                #expect(Data(base64Encoded: json["additionalDataBase64"] as? String ?? "") == Data([0xde, 0xad]))
            } else { #expect(cells.last?["rawTerrainType"] as? Int == 0x8001) }
            let original = try Data(contentsOf: url)
            #expect(throws: (any Error).self) { try doc.writeJSON(to: url) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func jsonCancellationProtectsExistingOutputAndCleansTemporaryFiles() throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let doc = try MapDocument.decode(gat(width: 128, height: 128))
        let url = root.appendingPathComponent("existing.json"), original = Data("original output".utf8)
        try original.write(to: url)
        let flag = MapExportStop()
        #expect(throws: GRFError.self) {
            try doc.writeJSON(to: url, overwrite: true, cancelled: { flag.stopped }, progress: { if $0 >= 0.3 { flag.stop() } })
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["existing.json"])
    }

    @Test func actualDataGRFMapsIncludeEncryptedResources() throws {
        guard let location = ProcessInfo.processInfo.environment["GRF_DEMO_DIR"] else { return }
        let source = URL(fileURLWithPath: location).appendingPathComponent("RO 私服/data.grf")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let archive = try GRFArchive(url: source)
        let maps = archive.entries.filter { ["gat", "gnd"].contains(($0.path as NSString).pathExtension.lowercased()) }
        #expect(maps.count == 1428)
        var decoded = 0, encrypted = 0
        for ext in ["gat", "gnd"] {
            let chosen = Array(maps.filter { $0.path.hasSuffix("." + ext) && $0.flags & 6 != 0 }.prefix(2)) +
                         Array(maps.filter { $0.path.hasSuffix("." + ext) && $0.flags & 6 == 0 }.prefix(2))
            #expect(chosen.count == 4)
            for entry in chosen {
                let raw = try archive.data(for: entry), map = try MapDocument.decode(raw)
                let expectedWidth = Int(raw[6]) | Int(raw[7]) << 8 | Int(raw[8]) << 16 | Int(raw[9]) << 24
                #expect(map.width == expectedWidth)
                #expect(map.raster().rgba.count == map.width * map.height * 4)
                #expect(map.cell(x: map.width - 1, y: map.height - 1) != nil)
                if entry.flags & 6 != 0 { encrypted += 1 }
                decoded += 1
            }
        }
        print("Map demo integration: decoded=\(decoded), encrypted=\(encrypted), totalMapResources=\(maps.count)")
    }
}
