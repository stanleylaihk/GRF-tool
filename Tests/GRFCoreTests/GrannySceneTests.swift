import Foundation
import Testing
import SceneKit
import AppKit
import Metal
@testable import GRFCore
import GRFDesktop

struct GrannySceneTests {
    /// An authored triangle with one raw BGRA texture, no copyrighted game data.
    func triangle(index: UInt16 = 2, encoding: UInt32 = 1) -> Data {
        var section = Data(repeating: 0, count: 4), fixups: [(Int,Int)] = []
        func alloc(_ count: Int) -> Int { let offset = section.count; section += Data(repeating: 0,count: count); return offset }
        func u(_ offset: Int,_ value: UInt32) { var value = value.littleEndian; section.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: &value) { Data($0) }) }
        func string(_ value: String) -> Int { let offset = section.count; section += Data(value.utf8); section.append(0); return offset }
        func pointer(_ offset: Int,_ target: Int) { fixups.append((offset,target)) }
        let rootType = alloc(4*32), meshType = alloc(5*32), vertexType = alloc(3*32), vertexDataType = alloc(2*32)
        let topologyType = alloc(3*32), groupType = alloc(4*32), scalarType = alloc(2*32)
        let textureType = alloc(7*32), imageType = alloc(2*32), mipType = alloc(2*32), materialType = alloc(3*32), bindingType = alloc(2*32)
        func member(_ type: Int,_ slot: Int,_ kind: UInt32,_ name: String,_ target: Int = 0,_ width: UInt32 = 0) {
            let p = type+slot*32; u(p,kind); pointer(p+4,string(name)); if target != 0 { pointer(p+8,target) }; u(p+12,width)
        }
        member(rootType,0,4,"Meshes",meshType); member(rootType,1,4,"Textures",textureType); member(rootType,2,4,"Materials",materialType)
        member(meshType,0,8,"Name"); member(meshType,1,2,"PrimaryVertexData",vertexDataType); member(meshType,2,2,"PrimaryTopology",topologyType); member(meshType,3,3,"MaterialBindings",bindingType)
        member(vertexType,0,10,"Position",0,3); member(vertexType,1,10,"TextureCoordinates0",0,2)
        member(vertexDataType,0,7,"Vertices")
        member(topologyType,0,3,"Indices16",scalarType); member(topologyType,1,3,"Groups",groupType)
        member(scalarType,0,16,"Value")
        member(groupType,0,19,"MaterialIndex"); member(groupType,1,19,"TriFirst"); member(groupType,2,19,"TriCount")
        member(textureType,0,8,"FromFileName"); member(textureType,1,19,"Width"); member(textureType,2,19,"Height"); member(textureType,3,19,"Encoding"); member(textureType,4,19,"SubFormat"); member(textureType,5,3,"Images",imageType)
        member(imageType,0,3,"MIPLevels",mipType); member(mipType,0,3,"Pixels",scalarType)
        member(materialType,0,8,"Name"); member(materialType,1,2,"Texture",textureType); member(bindingType,0,2,"Material",materialType)
        let root = alloc(24), mesh = alloc(20), vertices = alloc(12), topology = alloc(16), group = alloc(12)
        let texture = alloc(28), image = alloc(8), mip = alloc(8), material = alloc(8), binding = alloc(4)
        for (slot,target) in [(root,mesh),(root+8,texture),(root+16,material)] { u(slot,1); let array = alloc(4); pointer(slot+4,array); pointer(array,target) }
        pointer(mesh,string("Triangle")); pointer(mesh+4,vertices); pointer(mesh+8,topology); u(mesh+12,1); pointer(mesh+16,binding); pointer(binding,material)
        pointer(vertices,vertexType); u(vertices+4,3)
        let vertexBuffer = alloc(60); pointer(vertices+8,vertexBuffer)
        let values: [Float] = [0,0,0,0,0, 1,0,0,1,0, 0,0,1,0,1]
        for (i,value) in values.enumerated() { u(vertexBuffer+i*4,value.bitPattern) }
        let indices = alloc(6); section.replaceSubrange(indices..<indices+6,with: [0,0,1,0,UInt8(index&255),UInt8(index>>8)])
        u(topology,3); pointer(topology+4,indices); u(topology+8,1); pointer(topology+12,group); u(group+8,1)
        let textureName = string("authored-test.tga"); pointer(texture,textureName); u(texture+4,1); u(texture+8,1); u(texture+12,encoding); u(texture+20,1); pointer(texture+24,image)
        u(image,1); pointer(image+4,mip); u(mip,4); let pixel = alloc(4); section.replaceSubrange(pixel..<pixel+4,with: [30,20,10,255]); pointer(mip+4,pixel)
        pointer(material,string("Test material")); pointer(material+4,texture)
        var file = Data([0xb8,0x67,0xb0,0xca,0xf8,0x6d,0xb1,0x0f,0x84,0x72,0x8c,0x7e,0x5e,0x19,0,0x1e])
        func append(_ value: UInt32) { var value = value.littleEndian; file += withUnsafeBytes(of: &value) { Data($0) } }
        let fixupOffset = 132+section.count, size = fixupOffset+fixups.count*12
        for value in [132,0,0,0,6,size,0,56,1,0,rootType,0,root,0,0,0,0,0] { append(UInt32(value)) }
        for value in [0,132,section.count,section.count,4,0,0,fixupOffset,fixups.count,0,0] { append(UInt32(value)) }
        file += section
        for (source,target) in fixups { append(UInt32(source)); append(0); append(UInt32(target)) }
        return file
    }
    @Test func triangleReconstructsUVsMaterialsAndRawTexture() throws {
        if let path = ProcessInfo.processInfo.environment["GRF_GR2_FIXTURE"] { try triangle().write(to: URL(fileURLWithPath: path)) }
        let scene = try GrannyScene.prepare(triangle(),path: "triangle.gr2")
        #expect(scene.document.kind == "GR2")
        #expect(scene.document.meshes.count == 1)
        let mesh = try #require(scene.document.meshes.first)
        #expect(mesh.vertices.count == 3 && mesh.indices == [0,1,2])
        #expect(mesh.textureIndices == [0,1,2] && mesh.faceTextures == [0])
        #expect(mesh.vertices[2].y == -1)
        #expect(scene.embeddedTextures["gr2-texture-0"]?.rgba == Data([10,20,30,255]))
        #expect(scene.missing.isEmpty)
    }
    @Test func badTextureKeepsWireframeAndInvalidIndicesAreRejected() throws {
        let scene = try GrannyScene.prepare(triangle(encoding: 99),path: "triangle.gr2")
        #expect(scene.document.meshes.count == 1 && scene.embeddedTextures.isEmpty)
        #expect(!scene.missing.isEmpty)
        #expect(throws: (any Error).self) { _ = try GrannyScene.prepare(triangle(index: 99),path: "bad.gr2") }
        #expect(throws: (any Error).self) { _ = try GrannyScene.prepare(Data("invalid".utf8),path: "bad.gr2") }
        #expect(throws: GRFError.self) { _ = try GrannyScene.prepare(triangle(),path: "cancelled.gr2",cancelled: { true }) }
    }
    @Test func suppliedCorpusReconstructsModelsTexturesAndActionCompanions() throws {
        guard let directory = ProcessInfo.processInfo.environment["GRF_GR2_CORPUS"] else { return }
        let root = URL(fileURLWithPath: directory)
        let paths = try JSONDecoder().decode([String:String].self,from: Data(contentsOf: root.appendingPathComponent("paths.json")))
        let files = try Dictionary(uniqueKeysWithValues: paths.map { name,path in (path.lowercased(),try GRFBuildFile.importingFile(root.appendingPathComponent(name),path: path)) })
        let expected = ["2026.gr2":(5,5),"2627.gr2":(1,1),"18046.gr2":(6,4),"37864.gr2":(4,4),"43356.gr2":(2,2),"51738.gr2":(1,1)]
        for (name,path) in paths.sorted(by: { $0.key < $1.key }) {
            let bytes = try Data(contentsOf: root.appendingPathComponent(name))
            let scene = try GrannyScene.prepare(bytes,path: path,files: files)
            #expect(!scene.document.meshes.isEmpty,"\(path)")
            #expect(!scene.embeddedTextures.isEmpty,"\(path)")
            #expect(scene.missing.isEmpty,"\(path): \(scene.missing)")
            if let (meshes,textures) = expected[name] { #expect(scene.document.meshes.count == meshes && scene.embeddedTextures.count == textures) }
            else { #expect(scene.document.notes.contains { $0.hasPrefix("Matched model:") }) }
            print("GR2 scene: \(path) · \(scene.document.meshes.count) meshes · \(scene.embeddedTextures.count) textures")
        }
        #expect(paths.count == 21)
    }
    @MainActor @Test func renderAuthoredAndSuppliedScenes() throws {
        guard let output = ProcessInfo.processInfo.environment["GRF_GR2_RENDER_DIRECTORY"] else { return }
        let destination = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: destination,withIntermediateDirectories: true)
        var scenes = [("triangle",try GrannyScene.prepare(triangle(),path: "triangle.gr2"))]
        if let corpus = ProcessInfo.processInfo.environment["GRF_GR2_CORPUS"] {
            for name in ["2026","18046","2627","37864","43356","51738"] {
                scenes.append((name,try GrannyScene.prepare(Data(contentsOf: URL(fileURLWithPath: corpus).appendingPathComponent(name+".gr2")),path: name+".gr2")))
            }
        }
        let device = try #require(MTLCreateSystemDefaultDevice())
        for (name,prepared) in scenes {
            for wire in [true,false] {
                let scene = SceneAssembler.build(prepared,wireframe: wire)
                var count = 0, hidden = 0
                scene.rootNode.enumerateChildNodes { node,_ in if let geometry = node.geometry { count += 1; if node.isHidden { hidden += 1 }; #expect(geometry.materials.allSatisfy { $0.fillMode == (wire ? .lines : .fill) }) } }
                #expect(count == prepared.document.meshes.count)
                #expect(hidden == (wire ? 0 : prepared.document.meshes.filter { !$0.hasMaterialBindings }.count))
                let renderer = SCNRenderer(device: device,options: nil); renderer.scene = scene
                renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                let image = renderer.snapshot(atTime: 0,with: CGSize(width: 720,height: 720),antialiasingMode: .multisampling4X)
                let tiff = try #require(image.tiffRepresentation), bitmap = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(bitmap.representation(using: .png,properties: [:])); try png.write(to: destination.appendingPathComponent(name+(wire ? "-wire.png" : "-textured.png")))
            }
        }
    }
}
