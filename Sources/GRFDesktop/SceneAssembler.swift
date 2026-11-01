import AppKit
import SceneKit
import GRFCore

public enum SceneAssembler {
    static func key(_ name: String) -> String { name.replacingOccurrences(of: "\\", with: "/").precomposedStringWithCanonicalMapping.lowercased() }
    static func vector(_ p: PreviewVector) -> SCNVector3 { SCNVector3(p.x, p.y, p.z) }
    private final class Materials {
        let prepared: PreparedScene
        let wireframe: Bool
        var cache: [String: SCNMaterial] = [:]
        init(_ prepared: PreparedScene, wireframe: Bool) { self.prepared = prepared; self.wireframe = wireframe }
        func make(_ texture: String?) -> SCNMaterial {
            let name = texture.map(SceneAssembler.key) ?? ""
            if let cached = cache[name] { return cached }
            let material = SCNMaterial(); material.isDoubleSided = true
            material.fillMode = wireframe ? .lines : .fill; material.lightingModel = .constant
            material.diffuse.contents = wireframe ? NSColor.systemTeal : NSColor.systemGray
            if !wireframe, let texture = prepared.embeddedTextures[name],
               let provider = CGDataProvider(data: texture.rgba as CFData),
               let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: texture.width*4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                   decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                material.diffuse.contents = NSImage(cgImage: image, size: NSSize(width: texture.width,height: texture.height))
                if stride(from: 3,to: texture.rgba.count,by: 4).contains(where: { texture.rgba[$0] < 255 }) {
                    material.transparencyMode = .aOne; material.blendMode = .alpha; material.writesToDepthBuffer = false
                }
                material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
            } else if !wireframe, let bytes = prepared.textures[name], let image = NSImage(data: bytes),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width <= 8192, cg.height <= 8192 {
                // RO uses pure magenta as a cutout color in BMP textures.
                // Convert it once per source texture, shared by all instances.
                let w = cg.width, h = cg.height
                if w * h <= 16_777_216, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data {
                    context.draw(cg, in: CGRect(x: 0,y: 0,width: w,height: h))
                    let rgba = pixels.bindMemory(to: UInt8.self, capacity: w*h*4)
                    var transparent = false
                    for p in stride(from: 0,to: w*h*4,by: 4) {
                        if rgba[p] >= 254 && rgba[p+1] <= 1 && rgba[p+2] >= 254 { rgba[p] = 0; rgba[p+1] = 0; rgba[p+2] = 0; rgba[p+3] = 0 }
                        if rgba[p+3] < 255 { transparent = true }
                    }
                    if let converted = context.makeImage() { material.diffuse.contents = NSImage(cgImage: converted, size: NSSize(width: w,height: h)) }
                    if transparent { material.transparencyMode = .aOne; material.blendMode = .alpha; material.writesToDepthBuffer = false }
                } else { material.diffuse.contents = image }
                material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
                material.diffuse.magnificationFilter = .nearest
            }
            cache[name] = material
            return material
        }
    }
    private static func model(_ document: ScenePreviewDocument, materials library: Materials) -> SCNNode {
        let root = SCNNode()
        let materials = document.references.map { library.make($0) }
        let fallback = library.make(nil)
        var nodes: [SCNNode] = []
        for mesh in document.meshes {
            let node = SCNNode(); node.name = mesh.name
            node.position = vector(mesh.position); node.scale = vector(mesh.scale)
            node.rotation = SCNVector4(mesh.axis.x, mesh.axis.y, mesh.axis.z, mesh.angle)
            // Vertex and UV indices are separate in RSM. Expand face corners to
            // preserve UV seams rather than assigning one UV to a shared vertex.
            var vertices: [SCNVector3] = [], uv: [CGPoint] = [], groups: [Int: [UInt32]] = [:]
            for corner in mesh.indices.indices {
                vertices.append(vector(mesh.vertices[Int(mesh.indices[corner])]))
                if mesh.textureIndices.indices.contains(corner) {
                    let coordinate = mesh.textureCoordinates[Int(mesh.textureIndices[corner])]
                    uv.append(CGPoint(x: CGFloat(coordinate.u), y: CGFloat(1-coordinate.v)))
                } else { uv.append(.zero) }
                let face = corner / 3
                let texture = mesh.faceTextures.indices.contains(face) ? mesh.faceTextures[face] : -1
                groups[texture, default: []].append(UInt32(corner))
            }
            let slots = groups.keys.sorted()
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)], elements: slots.map { SCNGeometryElement(indices: groups[$0]!, primitiveType: .triangles) })
            geometry.materials = slots.map { materials.indices.contains($0) ? materials[$0] : fallback }
            let shape = SCNNode(geometry: geometry), m = mesh.matrix.map { CGFloat($0) }
            // GR2 skeleton exports can include unmaterialed helper boxes. Keep
            // them inspectable in wireframe without covering textured artwork.
            shape.isHidden = document.kind == "GR2" && !library.wireframe && !mesh.hasMaterialBindings
            shape.transform = SCNMatrix4(m11: m[0], m12: m[1], m13: m[2], m14: 0,
                m21: m[3], m22: m[4], m23: m[5], m24: 0,
                m31: m[6], m32: m[7], m33: m[8], m34: 0,
                m41: document.meshes.count == 1 ? 0 : CGFloat(mesh.offset.x),
                m42: document.meshes.count == 1 ? 0 : CGFloat(mesh.offset.y),
                m43: document.meshes.count == 1 ? 0 : CGFloat(mesh.offset.z), m44: 1)
            node.addChildNode(shape); nodes.append(node)
        }
        for i in nodes.indices {
            var seen: Set<Int> = [i], p = i, cyclic = false
            while let next = document.meshes.firstIndex(where: { $0.name == document.meshes[p].parent }), next != p {
                if !seen.insert(next).inserted { cyclic = true; break }; p = next
            }
            if !cyclic, let parent = document.meshes.firstIndex(where: { $0.name == document.meshes[i].parent }), parent != i { nodes[parent].addChildNode(nodes[i]) }
            else { root.addChildNode(nodes[i]) }
        }
        return root
    }
    private static func ground(_ map: MapDocument, materials library: Materials) -> SCNNode {
        let root = SCNNode()
        let scale = CGFloat(map.summary.geometryScale ?? 10)
        var vertices: [SCNVector3] = [], uvs: [CGPoint] = [], groups: [Int: [UInt32]] = [:]
        // GND corner order: SW, SE, NW, NE. Front/side faces share the current
        // tile's edge with the adjacent tile's edge.
        func quad(_ points: [SCNVector3], surface index: Int) {
            guard let surface = map.surface(at: index) else { return }
            let start = UInt32(vertices.count)
            vertices += points
            uvs += (0..<4).map { CGPoint(x: CGFloat(surface.u[$0]), y: CGFloat(1-surface.v[$0])) }
            groups[surface.textureIndex, default: []] += [start,start+1,start+2,start+2,start+1,start+3]
        }
        for y in 0..<map.height {
            for x in 0..<map.width {
                guard let cell = map.cell(x: x, y: y), let surfaces = cell.surfaceIndices else { continue }
                let left = (CGFloat(x) - CGFloat(map.width)/2) * scale, z = (CGFloat(y) - CGFloat(map.height)/2) * scale
                let h = cell.heights.map { CGFloat($0) }
                quad([SCNVector3(left,h[0],z),SCNVector3(left+scale,h[1],z),SCNVector3(left,h[2],z+scale),SCNVector3(left+scale,h[3],z+scale)], surface: surfaces.top)
                if surfaces.front >= 0, let next = map.cell(x: x, y: y+1) {
                    quad([SCNVector3(left,h[2],z+scale),SCNVector3(left+scale,h[3],z+scale),SCNVector3(left,CGFloat(next.heights[0]),z+scale),SCNVector3(left+scale,CGFloat(next.heights[1]),z+scale)], surface: surfaces.front)
                }
                if surfaces.side >= 0, let next = map.cell(x: x+1, y: y) {
                    quad([SCNVector3(left+scale,h[1],z),SCNVector3(left+scale,h[3],z+scale),SCNVector3(left+scale,CGFloat(next.heights[0]),z),SCNVector3(left+scale,CGFloat(next.heights[2]),z+scale)], surface: surfaces.side)
                }
            }
        }
        let slots = groups.keys.sorted()
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),SCNGeometrySource(textureCoordinates: uvs)], elements: slots.map { SCNGeometryElement(indices: groups[$0]!, primitiveType: .triangles) })
        geometry.materials = slots.map { library.make(map.textures.indices.contains($0) ? map.textures[$0] : nil) }
        root.addChildNode(SCNNode(geometry: geometry))
        return root
    }
    public static func build(_ prepared: PreparedScene, wireframe: Bool) -> SCNScene {
        let document = prepared.document, scene = SCNScene(), content = SCNNode()
        let library = Materials(prepared, wireframe: wireframe)
        scene.background.contents = NSColor.controlBackgroundColor
        scene.rootNode.addChildNode(content)
        if ["RSM", "GR2"].contains(document.kind) { content.addChildNode(model(document, materials: library)) }
        else if document.kind == "RSW" {
            if let map = prepared.ground { content.addChildNode(ground(map, materials: library)) }
            var templates: [String: SCNNode] = [:]
            for (name, document) in prepared.models {
                let shape = model(document, materials: library)
                let (low, high) = shape.boundingBox
                let centered = SCNNode(); centered.addChildNode(shape)
                shape.position = SCNVector3(-(low.x+high.x)/2, -high.y, -(low.z+high.z)/2)
                templates[name] = centered
            }
            for marker in document.markers where marker.kind == "Model" {
                let instance = SCNNode(); instance.position = vector(marker.position)
                // RO instance rotations apply Z, then X, then Y, in degrees.
                let z = SCNNode(), x = SCNNode(), y = SCNNode()
                if let s = marker.scale { y.scale = vector(s) }
                if let r = marker.rotation { z.eulerAngles.z = CGFloat(r.z) * .pi / 180; x.eulerAngles.x = CGFloat(r.x) * .pi / 180; y.eulerAngles.y = CGFloat(r.y) * .pi / 180 }
                instance.addChildNode(z); z.addChildNode(x); x.addChildNode(y)
                if let model = templates[key(marker.resource)] { y.addChildNode(model.clone()) }
                else {
                    let box = SCNBox(width: 8, height: 12, length: 8, chamferRadius: 0)
                    let m = SCNMaterial(); m.diffuse.contents = NSColor.systemOrange; m.lightingModel = .constant; box.materials = [m]
                    y.addChildNode(SCNNode(geometry: box))
                }
                content.addChildNode(instance)
            }
        } else {
            let points = document.markers.map { vector($0.position) }
            if !points.isEmpty {
                let element = SCNGeometryElement(indices: points.indices.map { UInt32($0) }, primitiveType: .point)
                element.pointSize = 6; element.minimumPointScreenSpaceRadius = 3; element.maximumPointScreenSpaceRadius = 6
                let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [element])
                geometry.materials = [library.make(nil)]
                content.addChildNode(SCNNode(geometry: geometry))
            }
        }
        // Convert RO's downward height axis to SceneKit's upward Y axis.
        content.scale = SCNVector3(1,-1,-1)
        let (low, high) = content.boundingBox
        let cx = (low.x+high.x)/2, cy = -(low.y+high.y)/2, cz = -(low.z+high.z)/2
        let center = SCNVector3(cx,cy,cz)
        let extent = max(1, max(high.x-low.x,max(high.y-low.y,high.z-low.z)))
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.zNear = Double(extent)/10000; camera.camera?.zFar = Double(extent)*100
        camera.position = SCNVector3(center.x+extent*0.65,center.y+extent*0.8,center.z+extent*0.9)
        camera.look(at: center); scene.rootNode.addChildNode(camera)
        return scene
    }
}
