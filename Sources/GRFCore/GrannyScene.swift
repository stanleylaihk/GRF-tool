import Foundation
import JavaScriptCore

/// Reconstructs RO's 32-bit GR2 v6 object graph after native Oodle-0 section
/// decoding. The bundled, MIT-licensed reader runs in a fresh JavaScriptCore
/// context without file, network or process APIs. No game DLL is executed.
public enum GrannyScene {
    private struct Payload {
        let file: String
        let sections: [String]
        let path: String
        var value: [String: Any] { ["file": file, "sections": sections, "path": path] }
        init(_ data: Data, path: String) throws {
            file = data.base64EncodedString()
            sections = try GrannySectionDecoder.decode(data).map { $0.base64EncodedString() }
            self.path = path
        }
    }
    private struct Output: Decodable {
        struct Mesh: Decodable {
            struct Group: Decodable { let materialIndex: Int; let triFirst: Int; let triCount: Int }
            let name: String
            let positions: [[Float]]
            let indices: [UInt32]
            let uvs: [[Float]]
            let materials: [String]
            let groups: [Group]
        }
        struct Texture: Decodable { let key: String; let width: Int; let height: Int; let rgba: Data; let name: String }
        let meshes: [Mesh]
        let textures: [Texture]
        let missing: [String]
        let notes: [String]
        let upAxis: [Float]
        let skeletonCount: Int
        let boneCount: Int
        let animationName: String
    }
    public static func prepare(_ data: Data, path: String, files: [String: GRFBuildFile] = [:], localRoot: URL? = nil,
                               cancelled: @Sendable () -> Bool = { false }) throws -> PreparedScene {
        if cancelled() { throw GRFError.cancelled }
        let input = try Payload(data, path: path)
        let companion = try companion(path: path, files: files, localRoot: localRoot).map { try Payload($0.1, path: $0.0) }
        if cancelled() { throw GRFError.cancelled }
        let output: Output = try autoreleasepool {
            guard let context = JSContext(),
                  let url = Bundle.module.url(forResource: "granny-preview", withExtension: "js") else {
                throw GRFError.invalid("The bundled GR2 preview reader is unavailable.")
            }
            let script = try String(contentsOf: url, encoding: .utf8)
            context.evaluateScript(script, withSourceURL: url)
            guard context.exception == nil,
                  let function = context.objectForKeyedSubscript("GRFGranny")?.forProperty("preview"), !function.isUndefined else {
                throw GRFError.invalid("The GR2 preview reader could not be initialized.")
            }
            let result = function.call(withArguments: [input.value, companion?.value as Any? ?? NSNull()])
            if let exception = context.exception {
                throw GRFError.invalid("GR2 model decoding failed: \(exception.toString() ?? "unknown error")")
            }
            guard let json = result?.toString(), let bytes = json.data(using: .utf8), bytes.count <= 96 * 1024 * 1024 else {
                throw GRFError.invalid("GR2 model output exceeds the preview limit.")
            }
            return try JSONDecoder().decode(Output.self, from: bytes)
        }
        if cancelled() { throw GRFError.cancelled }
        var document = ScenePreviewDocument(kind: "GR2", version: "6")
        document.grannyMetadata = try GrannyPreviewDocument.decode(data)
        document.notes = output.notes + ["\(output.skeletonCount) \(output.skeletonCount == 1 ? "skeleton" : "skeletons") · \(output.boneCount) bones"]
        if !output.animationName.isEmpty { document.notes.append("Pose source: \(output.animationName)") }
        if path.lowercased().contains("3dmob_bone/"), companion == nil {
            document.notes.append("Matching base model unavailable; this action file may contain only helper geometry.")
        }
        var textures: [String: PreviewTexture] = [:]
        for texture in output.textures {
            guard texture.width > 0, texture.height > 0, texture.width <= 4096, texture.height <= 4096,
                  texture.rgba.count == texture.width * texture.height * 4 else { throw GRFError.invalid("Invalid decoded GR2 texture.") }
            textures[texture.key] = PreviewTexture(width: texture.width, height: texture.height, rgba: texture.rgba)
            document.references.append(texture.key)
        }
        let zero = PreviewVector(x: 0,y: 0,z: 0), one = PreviewVector(x: 1,y: 1,z: 1)
        let zUp = output.upAxis.count == 3 && abs(output.upAxis[2]) > 0.9
        for mesh in output.meshes {
            guard mesh.positions.count <= 500_000, mesh.indices.count <= 3_000_000, mesh.indices.count % 3 == 0,
                  mesh.indices.allSatisfy({ Int($0) < mesh.positions.count }),
                  mesh.positions.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && abs($0) <= 1e12 } }),
                  mesh.uvs.isEmpty || mesh.uvs.count == mesh.positions.count && mesh.uvs.allSatisfy({ $0.count >= 2 && $0.allSatisfy { $0.isFinite && abs($0) <= 1e12 } }) else {
                throw GRFError.invalid("Invalid GR2 vertex, UV or triangle buffer.")
            }
            // Reuse the RO scene renderer's downward-Y convention. Its final
            // axis conversion maps authoring Z-up to SceneKit (x,z,-y).
            let vertices = mesh.positions.map { zUp ? PreviewVector(x: $0[0],y: -$0[2],z: $0[1]) : PreviewVector(x: $0[0],y: -$0[1],z: -$0[2]) }
            var preview = PreviewMesh(name: mesh.name, parent: "", matrix: [1,0,0,0,1,0,0,0,1], offset: zero, position: zero,
                                      angle: 0, axis: PreviewVector(x: 0,y: 1,z: 0), scale: one, vertices: vertices, indices: mesh.indices)
            // Granny UVs use the opposite V convention from RSM. The shared
            // renderer flips V once when creating SceneKit texture coordinates.
            preview.hasMaterialBindings = !mesh.materials.isEmpty
            preview.textureCoordinates = mesh.uvs.map { PreviewUV(u: $0[0],v: 1-$0[1]) }
            if !mesh.uvs.isEmpty { preview.textureIndices = mesh.indices }
            preview.faceTextures = Array(repeating: -1, count: mesh.indices.count / 3)
            for group in mesh.groups {
                guard group.triFirst >= 0, group.triCount >= 0, group.triFirst <= preview.faceTextures.count,
                      group.triCount <= preview.faceTextures.count - group.triFirst else { throw GRFError.invalid("Invalid GR2 material triangle range.") }
                let texture = mesh.materials.indices.contains(group.materialIndex) ? mesh.materials[group.materialIndex] : ""
                let slot = document.references.firstIndex(of: texture) ?? -1
                for face in group.triFirst..<(group.triFirst+group.triCount) { preview.faceTextures[face] = slot }
            }
            document.meshes.append(preview)
        }
        if document.meshes.isEmpty { document.notes.append("This GR2 contains no renderable mesh. A separate base model is required for animation-only files.") }
        var scene = PreparedScene(document: document)
        scene.embeddedTextures = textures; scene.missing = output.missing
        scene.loadedBytes = data.count + textures.values.reduce(0) { $0 + $1.rgba.count }
        return scene
    }
    /// RO stores action files as N_action.gr2 and base models as name_N.gr2.
    /// Resolve only an unambiguous sibling model inside the active source/data root.
    static func companion(path: String, files: [String: GRFBuildFile], localRoot: URL?) throws -> (String, Data)? {
        let name = (path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent.lowercased()
        guard let separator = name.firstIndex(of: "_"), !name[..<separator].isEmpty,
              name[..<separator].allSatisfy(\.isNumber) else { return nil }
        let suffix = "_" + name[..<separator] + ".gr2"
        let candidates = files.values.filter { $0.path.lowercased().contains("/3dmob/") && $0.path.lowercased().hasSuffix(suffix) }
        if candidates.count == 1 { return (candidates[0].path, try candidates[0].data(limit: 32 * 1024 * 1024)) }
        guard candidates.isEmpty, let root = localRoot else { return nil }
        for relative in ["data/model/3dmob", "model/3dmob", "3dmob"] {
            let directory = root.appendingPathComponent(relative)
            guard directory.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { continue }
            let matches = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter { $0.lastPathComponent.lowercased().hasSuffix(suffix) } ?? []
            if matches.count == 1 {
                let file = try GRFBuildFile.importingFile(matches[0]); return (relative + "/" + matches[0].lastPathComponent, try file.data(limit: 32 * 1024 * 1024))
            }
        }
        return nil
    }
}
