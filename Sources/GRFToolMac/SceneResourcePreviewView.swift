import SwiftUI
import SceneKit
import GRFCore
import GRFDesktop

struct SceneResourcePreviewView: View {
    let prepared: PreparedScene
    @State private var mode = "Wireframe"
    @State private var showInfo = false
    @State private var showMissing = false
    @State private var scene: SCNScene?
    var document: ScenePreviewDocument { prepared.document }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if ["RSM", "GR2"].contains(document.kind) {
                    Picker("Model display", selection: $mode) {
                        Text("Wireframe").tag("Wireframe")
                        Text("Textured").tag("Textured")
                    }.pickerStyle(.segmented)
                } else { Text(document.kind == "RSW" ? "3D Map" : "Layer Positions").font(.callout.weight(.medium)); Spacer() }
                Button { showInfo.toggle() } label: { Image(systemName: showInfo ? "cube" : "info.circle") }.help(showInfo ? "Show scene" : "Show decoded information / JSON")
            }.padding(10)
            if showInfo { PlainTextPreview(text: (try? document.json()) ?? "Unable to encode scene.") }
            else if document.kind == "GR2" && document.meshes.isEmpty {
                ContentUnavailableView("No model geometry", systemImage: "cube", description: Text(document.notes.joined(separator: "\n")))
            } else if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else { ProgressView("Preparing scene…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Drag to orbit · Scroll to zoom · \(document.kind) \(document.version)").font(.caption).foregroundStyle(.secondary)
                if document.kind == "GR2" { Text(document.notes.filter { !$0.hasPrefix("Pose source:") }.joined(separator: "\n")).font(.caption2).foregroundStyle(.secondary) }
                if document.kind == "RSW" { Text("Static terrain and models · Water, effects and game lighting excluded").font(.caption2).foregroundStyle(.secondary) }
                if document.kind == "IMF" { Text("Layer origins only; matching SPR/ACT is required for sprite artwork.").font(.caption2).foregroundStyle(.secondary) }
                if !prepared.missing.isEmpty {
                    DisclosureGroup("\(prepared.missing.count) missing or unsupported resources", isExpanded: $showMissing) {
                        ScrollView { VStack(alignment: .leading, spacing: 5) { ForEach(prepared.missing, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
                    }.font(.caption).foregroundStyle(.orange)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
         .task(id: mode) {
            let wire = ["RSM", "GR2"].contains(document.kind) && mode == "Wireframe"
            let result = await Task.detached(priority: .userInitiated) { SceneAssembler.build(prepared, wireframe: wire) }.value
            if !Task.isCancelled { scene = result }
        }
    }
}

