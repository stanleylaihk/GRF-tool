import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GRFCore
import GRFDesktop

private final class MapExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

struct MapPreviewView: View {
    let document: MapDocument
    let raster: MapRaster
    let sourceURL: URL
    let name: String
    @State private var tab = "Preview"
    @State private var zoom = 2.0
    @State private var selectedX = 0
    @State private var selectedY = 0
    @State private var xInput = "0"
    @State private var yInput = "0"
    @State private var selectionError: String?
    @State private var exporting = false
    @State private var fraction = 0.0
    @State private var exportMessage = ""
    @State private var error: String?
    @State private var flag = MapExportCancellation()

    private var image: NSImage? {
        guard let provider = CGDataProvider(data: raster.rgba as CFData),
              let cg = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: raster.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                               decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: raster.width, height: raster.height))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Map View", selection: $tab) {
                ForEach(["Preview", "Info", "JSON"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).padding(10)
            switch tab {
            case "Preview": mapView
            case "Info": infoView
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Text("Summary + selected cell (\(selectedX), \(selectedY)). Export includes all cells and surfaces.")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                    PlainTextPreview(text: (try? document.previewJSON(x: selectedX, y: selectedY)) ?? "Unable to encode selection.")
                }
            }
            Divider()
            HStack {
                if exporting {
                    ProgressView(value: fraction).frame(width: 70)
                    Text("Exporting…").font(.caption)
                    Spacer()
                    Button("Cancel") { flag.cancel() }
                } else {
                    Text(exportMessage.isEmpty ? "\(document.kind.rawValue) \(document.summary.version) · \(document.width) × \(document.height)" : exportMessage)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Export JSON…", action: exportJSON)
                }
            }.padding(10)
        }
        .alert("Map Preview", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { flag.cancel() }
    }

    private var mapView: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Fit") { fit(geometry.size) }
                        Button { zoom = max(0.05, zoom / 2) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom Out")
                        Button { zoom = min(16, zoom * 2) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom In")
                        Spacer(minLength: 0)
                        Text(String(format: "%.0f%%", zoom * 100)).monospacedDigit().font(.caption)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.none)
                                .frame(width: Double(document.width) * zoom, height: Double(document.height) * zoom)
                                .overlay(alignment: .topLeading) {
                                    if zoom >= 8 {
                                        Canvas { context, size in
                                            var path = Path()
                                            for x in 0...document.width {
                                                let p = Double(x) * zoom; path.move(to: CGPoint(x: p, y: 0)); path.addLine(to: CGPoint(x: p, y: size.height))
                                            }
                                            for y in 0...document.height {
                                                let p = Double(y) * zoom; path.move(to: CGPoint(x: 0, y: p)); path.addLine(to: CGPoint(x: size.width, y: p))
                                            }
                                            context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                                        }.allowsHitTesting(false)
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    Rectangle().stroke(.white, lineWidth: 2).shadow(color: .black, radius: 1)
                                        .frame(width: max(2, zoom), height: max(2, zoom))
                                        .offset(x: Double(selectedX) * zoom, y: Double(selectedY) * zoom)
                                        .allowsHitTesting(false)
                                }
                                .contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { event in
                                    select(x: Int(event.location.x / zoom), y: Int(event.location.y / zoom))
                                })
                                .accessibilityLabel("\(document.kind.rawValue) map, \(document.width) by \(document.height) cells. Use the X and Y fields to select a cell.")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.black.opacity(0.06))
                }.onAppear { fit(geometry.size) }
            }
            HStack(spacing: 6) {
                Text("X").font(.caption)
                TextField("X coordinate", text: $xInput).frame(width: 48).onSubmit(goToCell)
                    .accessibilityLabel("Cell X")
                Text("Y").font(.caption)
                TextField("Y coordinate", text: $yInput).frame(width: 48).onSubmit(goToCell)
                    .accessibilityLabel("Cell Y")
                Button("Go", action: goToCell)
                Spacer(minLength: 0)
            }.textFieldStyle(.roundedBorder)
            if let selectionError { Text(selectionError).font(.caption).foregroundStyle(.red) }
            if let cell = document.cell(x: selectedX, y: selectedY) {
                Text("Cell (\(selectedX), \(selectedY))" + (cell.terrainLabel.map { " · \($0)" } ?? ""))
                    .font(.caption.bold()).textSelection(.enabled)
                Text("File heights: " + cell.heights.map { String(format: "%.2f", $0) }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(document.kind == .gat ? "Green: walkable · Gray: blocked · Blue: type 3 water · Orange: ranged only · Purple: other type" : "Dark → light: low → high elevation · Charcoal: no top surface")
                .font(.caption2).foregroundStyle(.secondary)
            Text("File coordinates · y=0 at top").font(.caption2).foregroundStyle(.secondary)
        }.padding(10)
    }

    private var infoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Format", value: "\(document.kind.rawValue) \(document.summary.version)")
                LabeledContent("Dimensions", value: "\(document.width) × \(document.height)")
                LabeledContent("Cells", value: document.summary.cellCount.formatted())
                LabeledContent("File height range", value: String(format: "%.2f … %.2f", document.summary.minimumFileHeight, document.summary.maximumFileHeight))
                if let scale = document.summary.geometryScale { LabeledContent("Geometry scale", value: String(format: "%g", scale)) }
                if document.kind == .gnd {
                    LabeledContent("Surfaces", value: document.summary.surfaceCount.formatted())
                    LabeledContent("Lightmaps", value: (document.summary.lightmaps?.count ?? 0).formatted())
                    LabeledContent("Additional data", value: ByteCountFormatter.string(fromByteCount: Int64(document.summary.additionalByteCount), countStyle: .file))
                    Text("Textures (\(document.textures.count))").font(.headline)
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(document.textures.indices, id: \.self) { index in
                            Text("\(index): \(document.textures[index])").font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                } else {
                    ForEach(document.summary.terrainCounts.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }, id: \.self) { type in
                        LabeledContent("\(type): \(MapDocument.terrainLabel(Int(type) ?? 0))", value: (document.summary.terrainCounts[type] ?? 0).formatted())
                    }
                }
                Divider()
                ForEach(document.summary.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }.padding(12).textSelection(.enabled)
        }
    }

    private func fit(_ size: CGSize) {
        zoom = max(0.05, min(16, min(max(1, size.width - 16) / Double(document.width), max(1, size.height - 40) / Double(document.height))))
    }
    private func select(x: Int, y: Int) {
        guard document.cell(x: x, y: y) != nil else { return }
        selectedX = x; selectedY = y; xInput = String(x); yInput = String(y); selectionError = nil
    }
    private func goToCell() {
        guard let x = Int(xInput), let y = Int(yInput), document.cell(x: x, y: y) != nil else {
            selectionError = "Choose X: 0–\(document.width - 1), Y: 0–\(document.height - 1)."; return
        }
        select(x: x, y: y)
    }

    private func exportJSON() {
        let panel = NSSavePanel(); panel.title = "Export Map JSON"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.resolvingSymlinksInPath().standardizedFileURL != sourceURL.resolvingSymlinksInPath().standardizedFileURL else {
            error = "Choose another filename to preserve the source file."; return
        }
        let overwrite = FileManager.default.fileExists(atPath: url.path)
        flag = MapExportCancellation(); let cancellation = flag
        exporting = true; fraction = 0; exportMessage = ""
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try document.writeJSON(to: url, overwrite: overwrite, cancelled: { cancellation.cancelled }, progress: { value in
                        Task { @MainActor in fraction = value }
                    })
                }.value
                exporting = false; exportMessage = "Saved \(url.lastPathComponent)."
            } catch {
                exporting = false
                if cancellation.cancelled { exportMessage = "Export cancelled." }
                else { self.error = error.localizedDescription }
            }
        }
    }
}
