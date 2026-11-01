import Foundation
import Testing
import AppKit
import SceneKit
import Metal
@testable import GRFCore
import GRFDesktop

@MainActor
struct SceneAssemblyTests {
    @Test func localAndArchiveAssemblyLoadIdenticalGeometryAndTextures() throws {
        guard let directory = ProcessInfo.processInfo.environment["GRF_UI_DEMO_DIRECTORY"] else { return }
        let root = URL(fileURLWithPath: directory)
        let archive = try GRFArchive(url: root.appendingPathComponent("demo.grf"), encoding: .utf8)
        let files = try GRFBuildFile.fromArchive(archive, validatingPaths: false)
        let lookup = Dictionary(uniqueKeysWithValues: files.map { ($0.path.lowercased(), $0) })
        let world = try ScenePreviewDocument.decode(lookup["data/demo.rsw"]!.data(), extension: "rsw", encoding: .utf8)
        let model = try ScenePreviewDocument.decode(lookup["data/model/cube.rsm"]!.data(), extension: "rsm", encoding: .utf8)
        #expect(model.meshes[0].textureIndices.count == model.meshes[0].indices.count)
        #expect(model.meshes[0].faceTextures.count == 12)
        #expect(world.markers[0].rotation?.y == 30)
        #expect(world.markers[0].scale?.x == 1)
        let prepared = PreparedScene.prepare(world, files: lookup, localRoot: nil, encoding: .utf8)
        #expect(prepared.missing.isEmpty)
        #expect(prepared.ground?.width == 4)
        #expect(prepared.models.count == 1 && prepared.textures.count == 1)
        let local = PreparedScene.prepare(world, files: [:], localRoot: root, encoding: .utf8)
        #expect(local.missing.isEmpty)
        #expect(local.textures["wall.bmp"] == prepared.textures["wall.bmp"])
        let wire = SceneAssembler.build(PreparedScene.prepare(model, files: lookup, localRoot: nil, encoding: .utf8), wireframe: true)
        let scene = SceneAssembler.build(prepared, wireframe: false)
        var geometryCount = 0
        scene.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                geometryCount += 1
                #expect(geometry.sources(for: .texcoord).count == 1)
                #expect(geometry.materials.contains { $0.diffuse.contents is NSImage })
            }
        }
        #expect(geometryCount == 2)
        wire.rootNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry { #expect(geometry.materials.allSatisfy { $0.fillMode == .lines }) }
        }
        if let output = ProcessInfo.processInfo.environment["GRF_UI_RENDER_DIRECTORY"] {
            let destination = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for (name, scene) in [("world",scene),("wireframe",wire),("textured",SceneAssembler.build(PreparedScene.prepare(model, files: lookup, localRoot: nil, encoding: .utf8), wireframe: false))] {
                let device = try #require(MTLCreateSystemDefaultDevice(), "GPU unavailable for offscreen scene verification")
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640,height: 480), antialiasingMode: .multisampling4X)
                let tiff = try #require(image.tiffRepresentation, "Offscreen renderer returned no image")
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: destination.appendingPathComponent(name + ".png"))
            }
        }
    }
    @Test func renderSuppliedMapAndModel() throws {
        guard let path = ProcessInfo.processInfo.environment["GRF_REAL_RENDER_ARCHIVE"],
              let output = ProcessInfo.processInfo.environment["GRF_UI_RENDER_DIRECTORY"] else { return }
        let archive = try GRFArchive(url: URL(fileURLWithPath: path))
        let files = try GRFBuildFile.fromArchive(archive, validatingPaths: false)
        let lookup = Dictionary(files.map { ($0.path.precomposedStringWithCanonicalMapping.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let worldFile = try #require(lookup["data/prontera.rsw"] ?? files.first { $0.path.hasSuffix(".rsw") })
        let world = try ScenePreviewDocument.decode(worldFile.data(), extension: "rsw")
        let prepared = PreparedScene.prepare(world, files: lookup, localRoot: nil, encoding: .korean)
        #expect(prepared.ground != nil)
        #expect(!prepared.models.isEmpty && !prepared.textures.isEmpty)
        print("Real map assembled: \(prepared.models.count) unique models, \(prepared.textures.count) textures, \(prepared.missing.count) missing resources")
        print(prepared.missing.prefix(5))
        let model = try #require(prepared.models.values.first)
        let modelScene = PreparedScene.prepare(model, files: lookup, localRoot: nil, encoding: .korean)
        let destination = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let device = try #require(MTLCreateSystemDefaultDevice())
        for (name, source, wireframe) in [("real-world", prepared, false), ("real-rsm-wireframe", modelScene, true), ("real-rsm-textured", modelScene, false)] {
            let scene = SceneAssembler.build(source, wireframe: wireframe)
            let renderer = SCNRenderer(device: device, options: nil); renderer.scene = scene
            renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 960,height: 720), antialiasingMode: .multisampling4X)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: destination.appendingPathComponent(name + ".png"))
        }
    }
    @Test func missingResourcesAreListedWithoutFollowingAbsoluteReferences() throws {
        let model = try ScenePreviewDocument.decode(ScenePreviewTests().model(), extension: "rsm", encoding: .utf8)
        let scene = PreparedScene.prepare(model, files: [:], localRoot: nil, encoding: .utf8)
        #expect(scene.missing == ["wall.bmp"])
        #expect(scene.models.isEmpty && scene.textures.isEmpty)
    }
}
