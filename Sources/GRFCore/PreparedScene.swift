import Foundation

/// Resource bytes are prepared off the main thread; SceneKit nodes/images stay
/// on the UI thread. References resolve only inside the selected source.
public struct PreviewTexture: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data
}

public struct PreparedScene: Sendable {
    public let document: ScenePreviewDocument
    public var ground: MapDocument?
    public var models: [String: ScenePreviewDocument] = [:]
    public var textures: [String: Data] = [:]
    public var embeddedTextures: [String: PreviewTexture] = [:]
    public var missing: [String] = []
    public var loadedBytes = 0
    public static func prepare(_ document: ScenePreviewDocument, files: [String: GRFBuildFile], localRoot: URL?, encoding: FilenameEncoding, cancelled: @Sendable () -> Bool = { false }) -> Self {
        var scene = Self(document: document)
        var missing = Set<String>(), attempted = Set<String>()
        var modelTriangles = 0
        func normalized(_ path: String) -> String { path.replacingOccurrences(of: "\\", with: "/").precomposedStringWithCanonicalMapping.lowercased() }
        func read(_ reference: String, category: String) -> Data? {
            if cancelled() { return nil }
            let name = normalized(reference)
            let parts = name.split(separator: "/")
            guard !name.hasPrefix("/"), !name.contains(":"), !parts.contains(".."), !parts.contains(".") else { missing.insert(reference + " (unsafe reference)"); return nil }
            let candidates = [name, "data/" + category + "/" + name, category + "/" + name, "data/" + name]
            var file = candidates.compactMap { files[$0] }.first
            if file == nil, let root = localRoot {
                for path in candidates {
                    let url = root.appendingPathComponent(path)
                    guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { continue }
                    if let found = try? GRFBuildFile.importingFile(url) { file = found; break }
                }
            }
            guard let file else { missing.insert(reference); return nil }
            guard scene.loadedBytes + Int(file.size) <= 192 * 1024 * 1024 else { missing.insert(reference + " (scene memory limit)"); return nil }
            do { let data = try file.data(limit: 32 * 1024 * 1024); scene.loadedBytes += data.count; return data }
            catch { missing.insert(reference + ": " + error.localizedDescription); return nil }
        }
        func textures(_ references: [String]) {
            for reference in references where !cancelled() {
                let key = normalized(reference)
                if scene.textures[key] != nil { continue }
                if let bytes = read(reference, category: "texture") { scene.textures[key] = bytes }
            }
        }
        if document.kind == "RSM" { textures(document.references) }
        if document.kind == "RSW" {
            if let name = document.references.first(where: { $0.lowercased().hasSuffix(".gnd") }), let bytes = read(name, category: "") {
                do {
                    let ground = try MapDocument.decode(bytes, encoding: encoding)
                    if ground.width * ground.height <= 262_144 { scene.ground = ground; textures(ground.textures) }
                    else { missing.insert(name + " (3D ground limit: 262144 cells; use GND height preview)") }
                } catch { missing.insert(name + ": " + error.localizedDescription) }
            } else { missing.insert("Ground (.gnd)") }
            for marker in document.markers where marker.kind == "Model" && !cancelled() {
                let key = normalized(marker.resource)
                if !attempted.insert(key).inserted { continue }
                if let bytes = read(marker.resource, category: "model") {
                    do {
                        let model = try ScenePreviewDocument.decode(bytes, extension: "rsm", encoding: encoding)
                        let triangles = model.meshes.reduce(0) { $0 + $1.indices.count / 3 }
                        guard modelTriangles + triangles <= 2_000_000 else { missing.insert(marker.resource + " (model detail limit)"); continue }
                        modelTriangles += triangles
                        scene.models[key] = model; textures(model.references)
                    } catch { missing.insert(marker.resource + ": " + error.localizedDescription) }
                }
            }
        }
        scene.missing = missing.sorted()
        return scene
    }
}
