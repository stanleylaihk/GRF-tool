import Foundation
import Darwin

public enum MapKind: String, Codable, Sendable { case gat = "GAT", gnd = "GND" }

public struct MapSurfaceIndices: Codable, Sendable {
    public let top: Int
    public let front: Int
    public let side: Int
}

public struct MapCell: Codable, Sendable {
    public let x: Int
    public let y: Int
    /// File order: bottom-left, bottom-right, top-left, top-right. Values are not rescaled.
    public let heights: [Float]
    public let rawTerrainType: UInt32?
    public var terrainType: Int? { rawTerrainType.map { Int($0 & 0xff) } }
    public let surfaceIndices: MapSurfaceIndices?
    public var terrainLabel: String? { terrainType.map(MapDocument.terrainLabel) }
}

public struct MapSurface: Codable, Sendable {
    public let index: Int
    public let u: [Float]
    public let v: [Float]
    public let textureIndex: Int
    public let lightmapIndex: Int
    public let colorBGRA: [UInt8]
}

public struct MapLightmaps: Codable, Sendable {
    public let count: Int
    public let width: Int
    public let height: Int
    public let gridSize: Int
    public let byteCount: Int
}

public struct MapSummary: Codable, Sendable {
    public let format: MapKind
    public let version: String
    public let width: Int
    public let height: Int
    public let cellCount: Int
    public let geometryScale: Float?
    public let minimumFileHeight: Float
    public let maximumFileHeight: Float
    public let textureCount: Int
    public let surfaceCount: Int
    public let lightmaps: MapLightmaps?
    public let terrainCounts: [String: Int]
    public let additionalByteCount: Int
    public let notes: [String]
}

public struct MapRaster: Sendable {
    public let width: Int
    public let height: Int
    /// Row zero corresponds to file row y=0. One pixel per cell, RGBA.
    public let rgba: Data
}

/// Immutable binary-backed map. Cells and surfaces are decoded on demand instead of
/// allocating millions of Swift objects. JSON export streams one record at a time.
public struct MapDocument: Sendable, Identifiable {
    public let id = UUID()
    public let summary: MapSummary
    public let textures: [String]
    private let bytes: [UInt8]
    private let cellsOffset: Int
    private let surfacesOffset: Int
    private let lightmapsOffset: Int
    private let additionalOffset: Int
    public var width: Int { summary.width }
    public var height: Int { summary.height }
    public var kind: MapKind { summary.format }

    public static func decode(_ data: Data, encoding: FilenameEncoding = .korean) throws -> MapDocument {
        guard data.count <= 64 * 1024 * 1024 else { throw GRFError.invalid("Map preview exceeds the 64 MiB limit.") }
        var r = MapReader(bytes: Array(data))
        let signature = try r.take(4)
        let kind: MapKind
        if signature == Array("GRAT".utf8) { kind = .gat }
        else if signature == Array("GRGN".utf8) { kind = .gnd }
        else { throw GRFError.invalid("Invalid GAT / GND signature.") }
        let major = Int(try r.byte()), minor = Int(try r.byte())
        guard major == 1, (kind == .gat ? [2, 3] : [6, 7, 8, 9]).contains(minor) else {
            throw GRFError.invalid("Unsupported \(kind.rawValue) version \(major).\(minor). Supported: GAT 1.2–1.3; GND 1.6–1.9.")
        }
        let width = try r.uint(), height = try r.uint()
        guard width > 0, height > 0, width <= 2048, height <= 2048, width * height <= 1_000_000 else {
            throw GRFError.invalid("Invalid or oversized map dimensions (maximum 2,048 per axis and 1,000,000 cells).")
        }
        var scale: Float?, textures: [String] = [], lightmaps: MapLightmaps?
        var lightmapsOffset = 0, surfacesOffset = 0, surfaceCount = 0
        if kind == .gnd {
            scale = try r.float()
            guard let scale, scale > 0, scale <= 1_000_000 else { throw GRFError.invalid("Invalid GND geometry scale.") }
            let count = try r.uint(), length = try r.uint()
            guard count <= 16_384, length > 0, length <= 1024, count * length <= r.remaining else { throw GRFError.invalid("Invalid GND texture table.") }
            for _ in 0..<count {
                let raw = Data(try r.take(length).prefix { $0 != 0 })
                textures.append(String(data: raw, encoding: .utf8) ?? (try? encoding.decode(raw)) ?? String(decoding: raw, as: UTF8.self))
            }
            let n = try r.uint(), w = try r.uint(), h = try r.uint(), grid = try r.uint()
            guard n <= 1_000_000, (1...1024).contains(w), (1...1024).contains(h), (1...16).contains(grid),
                  n * w * h * grid * 4 <= r.remaining else { throw GRFError.invalid("Invalid or truncated GND lightmaps.") }
            lightmaps = MapLightmaps(count: n, width: w, height: h, gridSize: grid, byteCount: n * w * h * grid * 4)
            lightmapsOffset = r.offset
            try r.skip(lightmaps!.byteCount)
            surfaceCount = try r.uint()
            guard surfaceCount <= 1_000_000, surfaceCount * 40 <= r.remaining else { throw GRFError.invalid("Invalid GND surface table.") }
            surfacesOffset = r.offset
            for _ in 0..<surfaceCount {
                for _ in 0..<8 { _ = try r.float() }
                try r.skip(8)
            }
        }
        let cellsOffset = r.offset, stride = kind == .gat ? 20 : 28, count = width * height
        guard count * stride <= r.remaining else { throw GRFError.invalid("Truncated \(kind.rawValue) cell grid.") }
        var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
        var types: [String: Int] = [:]
        for _ in 0..<count {
            for _ in 0..<4 { let h = try r.float(); low = min(low, h); high = max(high, h) }
            if kind == .gat { types[String(try r.uint() & 0xff), default: 0] += 1 }
            else { try r.skip(12) }
        }
        let additional = r.offset
        guard kind == .gnd || r.remaining == 0 else { throw GRFError.invalid("Unexpected trailing GAT data.") }
        let notes = ["Coordinates are zero-based file coordinates; row y=0 is shown at the top.",
                     "Heights are raw file values in bottom-left, bottom-right, top-left, top-right order. Visual elevation uses their negative mean.",
                     kind == .gat ? "Colors use conventional low-byte GAT types. Raw type bits are preserved; water levels from RSW are not inferred." : "Height preview only. Textures, lighting, walls, water and scene objects are not rendered. Additional data is preserved as base64 in JSON."]
        let summary = MapSummary(format: kind, version: "\(major).\(minor)", width: width, height: height, cellCount: count,
                                 geometryScale: scale, minimumFileHeight: low, maximumFileHeight: high,
                                 textureCount: textures.count, surfaceCount: surfaceCount, lightmaps: lightmaps,
                                 terrainCounts: types, additionalByteCount: r.remaining, notes: notes)
        return MapDocument(summary: summary, textures: textures, bytes: r.bytes, cellsOffset: cellsOffset,
                           surfacesOffset: surfacesOffset, lightmapsOffset: lightmapsOffset, additionalOffset: additional)
    }

    public func cell(x: Int, y: Int) -> MapCell? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        var r = MapReader(bytes: bytes, offset: cellsOffset + (y * width + x) * (kind == .gat ? 20 : 28))
        // The decoder validated every cell's complete range and finite heights.
        guard let heights = try? (0..<4).map({ _ in try r.float() }) else { return nil }
        if kind == .gat {
            return MapCell(x: x, y: y, heights: heights, rawTerrainType: UInt32(try! r.uint()), surfaceIndices: nil)
        }
        return MapCell(x: x, y: y, heights: heights, rawTerrainType: nil,
                       surfaceIndices: MapSurfaceIndices(top: try! r.signed32(), front: try! r.signed32(), side: try! r.signed32()))
    }

    public func surface(at index: Int) -> MapSurface? {
        guard kind == .gnd, (0..<summary.surfaceCount).contains(index) else { return nil }
        var r = MapReader(bytes: bytes, offset: surfacesOffset + index * 40)
        let u = try! (0..<4).map { _ in try r.float() }, v = try! (0..<4).map { _ in try r.float() }
        let texture = Int(Int16(bitPattern: UInt16(try! r.short())))
        return MapSurface(index: index, u: u, v: v, textureIndex: texture,
                          lightmapIndex: try! r.short(), colorBGRA: try! r.take(4))
    }

    public static func terrainLabel(_ type: Int) -> String {
        switch type {
        case 0: return "Walkable"
        case 1: return "Blocked"
        case 3: return "Walkable water"
        case 5: return "Blocked · ranged attacks pass"
        default: return "Type \(type)"
        }
    }

    public func raster() -> MapRaster {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let range = Double(summary.maximumFileHeight) - Double(summary.minimumFileHeight)
        for index in 0..<(width * height) {
            let offset = cellsOffset + index * (kind == .gat ? 20 : 28)
            var r = MapReader(bytes: bytes, offset: offset)
            let mean = (0..<4).reduce(0.0) { value, _ in value + Double(try! r.float()) / 4 }
            let rgb: (UInt8, UInt8, UInt8)
            if kind == .gat {
                switch try! r.uint() & 0xff {
                case 0: rgb = (81, 179, 118)
                case 1: rgb = (72, 77, 87)
                case 3: rgb = (65, 149, 231)
                case 5: rgb = (231, 165, 66)
                default: rgb = (160, 123, 189)
                }
            } else if try! r.signed32() == -1 { rgb = (48, 51, 59) }
            else {
                let t = range > 0 ? min(1, max(0, (Double(summary.maximumFileHeight) - mean) / range)) : 0.5
                rgb = (UInt8(35 + t * 205), UInt8(70 + t * 175), UInt8(105 + t * 145))
            }
            rgba[index * 4] = rgb.0; rgba[index * 4 + 1] = rgb.1; rgba[index * 4 + 2] = rgb.2
        }
        return MapRaster(width: width, height: height, rgba: Data(rgba))
    }

    public func previewJSON(x: Int, y: Int) throws -> String {
        struct Preview: Encodable { let summary: MapSummary; let selectedCell: MapCell?; let selectedSurfaces: [MapSurface] }
        let cell = cell(x: x, y: y)
        let selected = cell?.surfaceIndices.map { [$0.top, $0.front, $0.side].compactMap(surface(at:)) } ?? []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(Preview(summary: summary, selectedCell: cell, selectedSurfaces: selected)), as: UTF8.self)
    }

    /// Publishes a complete decoded grid and surface table, with binary lightmaps and
    /// extension data in base64. Memory use stays bounded even for large JSON output.
    public func writeJSON(to destination: URL, overwrite: Bool = false,
                          cancelled: @Sendable () -> Bool = { false }, progress: @Sendable (Double) -> Void = { _ in }) throws {
        var template = Array(destination.deletingLastPathComponent().appendingPathComponent(".map-json-XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = URL(fileURLWithPath: String(cString: template)), output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func write(_ text: String) throws { try output.write(contentsOf: Data(text.utf8)) }
        func encode<T: Encodable>(_ value: T) throws { try output.write(contentsOf: encoder.encode(value)) }
        func check() throws { if cancelled() { throw GRFError.invalid("JSON export cancelled. Existing output was kept.") } }
        func base64(_ start: Int, _ count: Int) throws {
            // Divisible by three so only the last chunk can contain base64 padding.
            for offset in stride(from: start, to: start + count, by: 49_152) {
                try check()
                try write(Data(bytes[offset..<min(start + count, offset + 49_152)]).base64EncodedString())
            }
        }
        try check(); try write("{\"schemaVersion\":1,\"summary\":"); try encode(summary)
        try write(",\"textures\":"); try encode(textures)
        try write(",\"surfaces\":[")
        for i in 0..<summary.surfaceCount {
            if i % 256 == 0 { try check(); progress(Double(i) / Double(max(1, summary.surfaceCount)) * 0.2) }
            if i > 0 { try write(",") }; try encode(surface(at: i)!)
        }
        try write("],\"cells\":[")
        var buffer = Data(); buffer.reserveCapacity(128 * 1024)
        for i in 0..<summary.cellCount {
            if i % 256 == 0 { try check(); progress(0.2 + Double(i) / Double(summary.cellCount) * 0.7) }
            if i > 0 { buffer.append(44) }
            buffer += try encoder.encode(cell(x: i % width, y: i / width)!)
            if buffer.count >= 64 * 1024 { try output.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
        }
        try output.write(contentsOf: buffer)
        try write("],\"lightmapDataBase64\":\"")
        if let lightmaps = summary.lightmaps { try base64(lightmapsOffset, lightmaps.byteCount) }
        try write("\",\"additionalDataBase64\":\""); try base64(additionalOffset, summary.additionalByteCount)
        try write("\"}"); try output.synchronize(); try output.close(); try check()
        let result = overwrite ? rename(temporary.path, destination.path) : renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL))
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        progress(1)
    }
}

private struct MapReader {
    let bytes: [UInt8]
    var offset = 0
    var remaining: Int { bytes.count - offset }
    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= remaining else { throw GRFError.invalid("Truncated map data.") }
        offset += count
    }
    mutating func take(_ count: Int) throws -> [UInt8] {
        let start = offset; try skip(count); return Array(bytes[start..<offset])
    }
    mutating func byte() throws -> UInt8 { try skip(1); return bytes[offset - 1] }
    mutating func short() throws -> Int {
        let p = offset; try skip(2); return Int(bytes[p]) | Int(bytes[p + 1]) << 8
    }
    mutating func uint() throws -> Int {
        let p = offset; try skip(4)
        return Int(bytes[p]) | Int(bytes[p + 1]) << 8 | Int(bytes[p + 2]) << 16 | Int(bytes[p + 3]) << 24
    }
    mutating func signed32() throws -> Int { Int(Int32(bitPattern: UInt32(try uint()))) }
    mutating func float() throws -> Float {
        let value = Float(bitPattern: UInt32(try uint()))
        guard value.isFinite, abs(value) <= 1e12 else { throw GRFError.invalid("Invalid non-finite or excessive map coordinate.") }
        return value
    }
}
