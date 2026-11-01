import Foundation

public struct PreviewVector: Codable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float
}
public struct PreviewUV: Codable, Sendable { public let u: Float; public let v: Float }
public struct PreviewMesh: Codable, Sendable {
    public let name: String
    public let parent: String
    public let matrix: [Float]
    public let offset: PreviewVector
    public let position: PreviewVector
    public let angle: Float
    public let axis: PreviewVector
    public let scale: PreviewVector
    public let vertices: [PreviewVector]
    public let indices: [UInt32]
    public var textureCoordinates: [PreviewUV] = []
    public var textureIndices: [UInt32] = []
    public var faceTextures: [Int] = []
    public var hasMaterialBindings = true
}
public struct PreviewMarker: Codable, Sendable {
    public let name: String
    public let kind: String
    public let resource: String
    public let position: PreviewVector
    public var rotation: PreviewVector? = nil
    public var scale: PreviewVector? = nil
}
public struct ScenePreviewDocument: Codable, Sendable {
    public let kind: String
    public let version: String
    public var references: [String] = []
    public var meshes: [PreviewMesh] = []
    public var markers: [PreviewMarker] = []
    public var notes: [String] = []
    public var grannyMetadata: GrannyPreviewDocument? = nil
    public func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
    public static func decode(_ data: Data, extension ext: String, encoding: FilenameEncoding = .korean) throws -> Self {
        guard data.count <= 64 * 1024 * 1024 else { throw GRFError.invalid("Scene exceeds the 64 MiB preview limit.") }
        var r = SceneReader(data: data, encoding: encoding)
        switch ext.lowercased() {
        case "imf": return try r.imf()
        case "rsw": return try r.world()
        case "rsm": return try r.model()
        default: throw GRFError.invalid("Unsupported scene format.")
        }
    }
}
private struct SceneReader {
    var data: Data
    var encoding: FilenameEncoding
    var offset = 0
    var remaining: Int { data.count - offset }
    mutating func take(_ n: Int) throws -> Data {
        guard n >= 0, n <= remaining else { throw GRFError.invalid("Truncated scene data.") }
        defer { offset += n }; return data.subdata(in: offset..<offset+n)
    }
    mutating func skip(_ n: Int) throws { _ = try take(n) }
    mutating func byte() throws -> Int { Int(try take(1).first!) }
    mutating func short() throws -> Int { let b = Array(try take(2)); return Int(b[0]) | Int(b[1]) << 8 }
    mutating func uint() throws -> UInt32 { let b = Array(try take(4)); return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24 }
    mutating func int() throws -> Int { Int(Int32(bitPattern: try uint())) }
    mutating func float() throws -> Float {
        let f = Float(bitPattern: try uint())
        guard f.isFinite, abs(f) <= 1e12 else { throw GRFError.invalid("Invalid scene coordinate.") }; return f
    }
    mutating func vector() throws -> PreviewVector { try PreviewVector(x: float(), y: float(), z: float()) }
    mutating func name(_ n: Int) throws -> String { try encoding.decode(Data(take(n).prefix { $0 != 0 })) }
    mutating func count(stride: Int, limit: Int = 500_000) throws -> Int {
        let n = try int(); guard n >= 0, n <= limit, n <= remaining / max(1, stride) else { throw GRFError.invalid("Invalid scene record count.") }; return n
    }
    mutating func header(_ signature: String) throws -> (Int, Int) {
        guard try take(4) == Data(signature.utf8) else { throw GRFError.invalid("Invalid \(signature) signature.") }
        return try (byte(), byte())
    }
    mutating func imf() throws -> ScenePreviewDocument {
        let version = try float()
        guard abs(version - 1.01) < 0.001 else { throw GRFError.invalid("Unsupported IMF version \(version).") }
        _ = try uint()
        let layers = try count(stride: 4, limit: 10_000)
        var doc = ScenePreviewDocument(kind: "IMF", version: "1.01")
        for layer in 0..<layers {
            let frames = try count(stride: 12)
            guard doc.markers.count + frames <= 500_000 else { throw GRFError.invalid("Too many IMF frames.") }
            for frame in 0..<frames {
                let index = try int(), x = try int(), y = try int()
                doc.markers.append(PreviewMarker(name: "Layer \(layer), frame \(frame), index \(index)", kind: "Layer \(layer)", resource: "", position: PreviewVector(x: Float(x), y: Float(y), z: Float(layer))))
            }
        }
        doc.notes = ["Layer origins only; sprite artwork and animation require matching SPR/ACT resources. IMF rendering semantics are incompletely documented."]
        if remaining > 0 { doc.notes.append("\(remaining) trailing bytes are not interpreted.") }
        return doc
    }
    mutating func world() throws -> ScenePreviewDocument {
        let (major, minor) = try header("GRSW"), v = major * 10 + minor
        guard major == 1 && (2...9).contains(minor) || major == 2 && minor <= 1 else { throw GRFError.invalid("RSW \(major).\(minor) is not supported yet (supported: 1.2–2.1).") }
        var doc = ScenePreviewDocument(kind: "RSW", version: "\(major).\(minor)")
        for _ in 0..<(v >= 14 ? 4 : 3) { doc.references.append(try name(40)) }
        if v >= 13 { try skip(4) }
        if v >= 18 { try skip(16) }
        if v >= 19 { try skip(4) }
        if v >= 15 { try skip(32) }
        if v >= 17 { try skip(4) }
        if v >= 16 { try skip(16) }
        let objects = try count(stride: 4, limit: 100_000)
        for _ in 0..<objects {
            let type = try int()
            var label = "", resource = "", position: PreviewVector
            var rotation: PreviewVector?, scale: PreviewVector?
            switch type {
            case 1:
                if v >= 13 { label = try name(40); try skip(12) }
                resource = try name(80); _ = try name(80); position = try vector(); rotation = try vector(); scale = try vector()
            case 2:
                label = try name(80); position = try vector(); try skip(16)
            case 3:
                label = try name(80); resource = try name(80); position = try vector(); try skip(v >= 20 ? 20 : 16)
            case 4:
                label = try name(80); position = try vector(); try skip(24)
            default: throw GRFError.invalid("Unknown RSW object type \(type).")
            }
            doc.markers.append(PreviewMarker(name: label, kind: ["Model", "Light", "Sound", "Effect"][type-1], resource: resource, position: position, rotation: rotation, scale: scale))
        }
        doc.notes = ["Scene assembly loads ground, models and referenced textures when available. Water, effects, animation and game lighting are not reproduced."]
        return doc
    }
    mutating func model() throws -> ScenePreviewDocument {
        let (major, minor) = try header("GRSM"), v = major * 10 + minor
        guard major == 1 && (1...4).contains(minor) else { throw GRFError.invalid("RSM \(major).\(minor) is not supported yet (supported: 1.1–1.4).") }
        try skip(8); if v >= 14 { try skip(1) }; try skip(16)
        var doc = ScenePreviewDocument(kind: "RSM", version: "\(major).\(minor)")
        let textures = try count(stride: 40, limit: 10_000)
        for _ in 0..<textures { doc.references.append(try name(40)) }
        _ = try name(40)
        let nodes = try count(stride: 188, limit: 2_000)
        var totalVertices = 0, totalFaces = 0
        for _ in 0..<nodes {
            let label = try name(40), parent = try name(40)
            let textureCount = try count(stride: 4, limit: 10_000)
            var textureMap: [Int] = []
            for _ in 0..<textureCount {
                let index = try int(); guard index >= 0, index < textures else { throw GRFError.invalid("Invalid model texture reference.") }; textureMap.append(index)
            }
            var matrix: [Float] = []; for _ in 0..<9 { matrix.append(try float()) }
            let offset = try vector(), position = try vector(), angle = try float(), axis = try vector(), scale = try vector()
            let verticesCount = try count(stride: 12); totalVertices += verticesCount
            guard totalVertices <= 500_000 else { throw GRFError.invalid("Model exceeds preview vertex limit.") }
            var vertices: [PreviewVector] = []; for _ in 0..<verticesCount { vertices.append(try vector()) }
            let uvCount = try count(stride: v >= 12 ? 12 : 8)
            var uvs: [PreviewUV] = []
            for _ in 0..<uvCount { if v >= 12 { try skip(4) }; uvs.append(try PreviewUV(u: float(), v: float())) }
            let faces = try count(stride: v >= 12 ? 24 : 20); totalFaces += faces
            guard totalFaces <= 500_000 else { throw GRFError.invalid("Model exceeds preview face limit.") }
            var indices: [UInt32] = [], uvIndices: [UInt32] = []
            var faceTextures: [Int] = []
            for _ in 0..<faces {
                for _ in 0..<3 { let index = try short(); guard index < vertices.count else { throw GRFError.invalid("Invalid model vertex index.") }; indices.append(UInt32(index)) }
                for _ in 0..<3 { let index = try short(); guard index < uvCount else { throw GRFError.invalid("Invalid model UV index.") }; uvIndices.append(UInt32(index)) }
                let texture = try short(); guard texture < textureCount else { throw GRFError.invalid("Invalid model texture index.") }
                faceTextures.append(textureMap[texture])
                try skip(v >= 12 ? 10 : 6)
            }
            let rotations = try count(stride: 20); try skip(rotations * 20)
            doc.meshes.append(PreviewMesh(name: label, parent: parent, matrix: matrix, offset: offset, position: position, angle: angle, axis: axis, scale: scale, vertices: vertices, indices: indices, textureCoordinates: uvs, textureIndices: uvIndices, faceTextures: faceTextures))
        }
        doc.notes = ["Static model geometry. Wireframe is the default; textured view loads referenced images when available. Animation and collision volumes are not rendered."]
        return doc
    }
}
