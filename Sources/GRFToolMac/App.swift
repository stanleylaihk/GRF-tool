import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import GRFCore
import GRFDesktop

@main
struct GRFToolMacApp: App {
    @NSApplicationDelegateAdaptor(GRFApplicationDelegate.self) private var appDelegate
    @StateObject private var model = ArchiveModel()
    var body: some Scene {
        Window("GRF Tool", id: "main") {
            MainArchiveWindow(model: model, appDelegate: appDelegate)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New GRF…", action: model.newArchive).keyboardShortcut("n")
                    .disabled(model.busy || model.showBuilder)
                Button("Open…", action: model.chooseArchive).keyboardShortcut("o")
                    .disabled(model.busy || model.showBuilder)
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { model.searchFocusRequest += 1 }.keyboardShortcut("f")
                    .disabled(model.showBuilder)
            }
        }
        Window("Credits & Sources", id: "credits") { CreditsView().frame(minWidth: 640, minHeight: 520) }
        Settings { GRFSettingsView() }
    }
}

private struct MainArchiveWindow: View {
    @ObservedObject var model: ArchiveModel
    let appDelegate: GRFApplicationDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ArchiveView(model: model)
            .frame(minWidth: 1100, minHeight: 680)
            .background(MainWindowCapture(delegate: appDelegate).allowsHitTesting(false))
            .onAppear {
                appDelegate.recovery.createWindow = { openWindow(id: "main") }
                appDelegate.mayTerminate = { !model.busy && model.confirmLeavingDraft() }
            }
            .onOpenURL { model.open($0) }
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class ArchiveModel: ObservableObject {
    @Published var archive: GRFArchive?
    @Published var showBuilder = false
    @Published var builderMode = GRFBuilderMode.new
    @Published var selection = Set<Int>()
    @Published var folder = ""
    @Published var search = ""
    @Published var searchFocusRequest = 0
    @Published var encoding = FilenameEncoding.korean
    @Published var textEncoding = TextPreviewEncoding.automatic
    @Published var textPreviewFailure: String?
    @Published var formattedJSON: String?
    @Published var busy = false
    @Published var loadingFraction: Double?
    @Published var loadingLocation = ""
    @Published var extracting = false
    @Published var completed = 0
    @Published var total = 0
    @Published var status = "Open a GRF or GPF archive to get started."
    @Published var error: String?
    @Published var extractionNotice: String?
    @Published var showPreview = true
    @Published var preview: PreviewContent = .empty
    @Published var frameIndex = 0
    @Published var playing = false
    @Published var spritePlaying = false
    @Published var transparent = true
    @Published var zoom = 2.0
    @Published var actionIndex = 0
    @Published var paletteLabel = "Embedded palette"
    @Published var externalPreviewName: String?
    @Published var actionDocument: ActionDocument?
    @Published var frameDuration = 0.125
    @Published var paletteSelection: Int?
    @Published var showPaletteBrowser = false
    @Published var filenameMode = ExtractionFilenameMode.unicode
    @Published var sortOrder = [KeyPathComparator(\GRFEntry.name), KeyPathComparator(\GRFEntry.path)]
    @Published var folders: [ArchiveFolder] = []
    @Published var visibleEntries: [GRFEntry] = []
    @Published var fileListRevision = UUID()
    @Published var paletteEntries: [GRFEntry] = []
    var textPreviewBytes: Data?
    var sceneCancellation = CancellationFlag()
    var entryLookup: [Int: GRFEntry] = [:]
    var audio: AVAudioPlayer?
    var previewID = UUID()
    var cancellation = CancellationFlag()
    var spriteBytes: Data?
    var spriteDocument: SpriteDocument?
    var overridePalette: Data?
    var actionCompanionName = ""
    var viewedPalette: Data?
    var paletteRequestID = UUID()
    var actionRenderID = UUID()
    var loadID = UUID()
    var visibleArchiveID: ObjectIdentifier?
    var visibleFolder = ""
    var visibleSearch = ""
    var visibleSortOrder: [KeyPathComparator<GRFEntry>] = []

    var protectedSourceURLs = Set<URL>()
    @Published var draft: ArchiveDraft?
    @Published var draftEntries: [GRFEntry] = []
    @Published var localFiles: [Int: GRFBuildFile] = [:]
    @Published var localDirectory: URL?
    @Published var browsingLocal = false
    @Published var showChanges = false
    @Published var searchScope = "Filename"
    @Published var searchRunning = false
    @Published var searchProgress = 0.0
    @Published var searchHits: [ContentSearchHit] = []
    @Published var searchFailures: [String] = []
    @Published var submittedQuery = ""
    @Published var hitOccurrence = 0
    var searchCancellation = CancellationFlag()
    var searchID = UUID()
    var workspaceRevision = UUID()
    var sceneResources: [String: GRFBuildFile] {
        Dictionary(entries.compactMap { entry -> (String, GRFBuildFile)? in
            guard browsingLocal || draft?.resource(entry.id)?.deleted != true else { return nil }
            return resourceFile(entry.id).map { (entry.path.lowercased(), $0) }
        }, uniquingKeysWith: { a, _ in a })
    }
    var sourceLabel: String { browsingLocal ? (localDirectory?.lastPathComponent ?? "Local Files") : (archive?.url.lastPathComponent ?? "New GRF") }
    var hasSource: Bool { browsingLocal ? localDirectory != nil : draft != nil }
    var pendingCount: Int { draft?.changes.count ?? 0 }

    var loading: Bool { loadingFraction != nil }

    var previewName: String { externalPreviewName ?? currentEntry.map { ($0.path as NSString).lastPathComponent } ?? "Preview" }
    var previewFrames: [SpriteFrame] { if case .sprite(let frames) = preview { return frames }; return [] }
    var isActionPreview: Bool { actionDocument != nil }

    var entries: [GRFEntry] {
        if browsingLocal { return localFiles.map { GRFEntry.listing(id: $0.key, path: $0.value.path, size: Int($0.value.size)) } }
        return draftEntries
    }
    func updateVisibleEntries() {
        let nameQuery = searchScope == "Filename" ? search : ""
        let hitIDs = Set(searchHits.map(\.resourceID))
        visibleEntries = entries.filter { entry in
            if searchScope != "Filename", !submittedQuery.isEmpty {
                return hitIDs.contains(entry.id) || (searchScope == "All" && ResourceSearch.matchesName(entry.path, query: submittedQuery))
            }
            return (folder.isEmpty || entry.path.hasPrefix(folder + "/")) && ResourceSearch.matchesName(entry.path, query: nameQuery)
        }.sorted(using: sortOrder)
        fileListRevision = UUID()
        rememberVisibleQuery()
    }
    func sortFiles(_ column: String, ascending: Bool) {
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case "size": sortOrder = [KeyPathComparator(\GRFEntry.size, order: order), KeyPathComparator(\GRFEntry.name)]
        case "packed": sortOrder = [KeyPathComparator(\GRFEntry.compressedSize, order: order), KeyPathComparator(\GRFEntry.name)]
        default: sortOrder = [KeyPathComparator(\GRFEntry.name, order: order), KeyPathComparator(\GRFEntry.path)]
        }
    }
    func rememberVisibleQuery() {
        visibleArchiveID = archive.map(ObjectIdentifier.init)
        visibleFolder = folder; visibleSearch = search; visibleSortOrder = sortOrder
    }
    var selectedEntries: [GRFEntry] { entries.filter { selection.contains($0.id) } }
    func searchChanged() {
        updateVisibleEntries()
        let visibleIDs: Set<Int> = Set(visibleEntries.map { $0.id })
        selection.formIntersection(visibleIDs)
    }
    var currentEntry: GRFEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return entryLookup[id]
    }

    func newArchive() {
        guard !busy, !showBuilder else { return }
        if !confirmLeavingDraft() { return }
        archive = nil; protectedSourceURLs = []; draft = ArchiveDraft(files: []); browsingLocal = false
        folder = ""; selection = []; search = ""; clearPreview(); refreshWorkspace()
    }

    func editArchive(_ mode: GRFBuilderMode) {
        guard !busy, !showBuilder, archive != nil else { return }
        builderMode = mode; showBuilder = true
    }

    func chooseArchive() {
        let panel = NSOpenPanel()
        panel.title = "Open Archive or Resource"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !busy, !showBuilder else { return }
        if !["grf", "gpf"].contains(url.pathExtension.lowercased()) { openPreview(url); return }
        guard confirmLeavingDraft() else { return }
        stopContentSearch()
        busy = true
        loadingFraction = 0
        loadingLocation = url.path
        status = "Opening \(url.lastPathComponent)…"
        loadID = UUID()
        let request = loadID
        cancellation = CancellationFlag()
        let flag = cancellation
        let selectedEncoding = encoding
        let ordering = sortOrder
        let reportLoad: @Sendable (Double, String) -> Void = { [weak self] fraction, detail in
            guard let model = self else { return }
            Task { @MainActor in model.updateLoad(request, fraction: fraction, detail: detail) }
        }
        Task {
            do {
                let (result, paths, palettes, initialFiles) = try await Task.detached(priority: .userInitiated) {
                    let result = try GRFArchive(url: url, encoding: selectedEncoding, progress: { progress in
                        reportLoad(progress.fraction * 0.9, progress.detail)
                    }, cancelled: { flag.isCancelled })
                    reportLoad(0.93, "Building folder tree")
                    let paths = ArchiveFolder.tree(filePaths: result.entries.map(\.path))
                    if flag.isCancelled { throw GRFError.loadingCancelled }
                    let palettes = result.entries.filter { $0.path.lowercased().hasSuffix(".pal") }
                    reportLoad(0.97, "Preparing file list")
                    let files = result.entries.sorted(using: ordering)
                    if flag.isCancelled { throw GRFError.loadingCancelled }
                    return (result, paths, palettes, files)
                }.value
                archive = result
                protectedSourceURLs = [result.url.resolvingSymlinksInPath().standardizedFileURL]
                draft = try ArchiveDraft(files: GRFBuildFile.fromArchive(result, validatingPaths: false))
                browsingLocal = false
                folders = paths
                paletteEntries = palettes
                selection = []
                folder = ""
                search = ""
                refreshWorkspace()
                visibleEntries = entries.sorted(using: ordering)
                fileListRevision = UUID()
                rememberVisibleQuery()
                clearPreview()
                status = "Loaded \(result.entries.count.formatted()) files."
            } catch {
                if flag.isCancelled { status = "Archive loading cancelled." }
                else { self.error = error.localizedDescription; status = "Could not open archive." }
            }
            loadingFraction = nil
            busy = false
        }
    }

    func updateLoad(_ request: UUID, fraction: Double, detail: String) {
        guard request == loadID, let current = loadingFraction, fraction >= current else { return }
        loadingFraction = fraction
        status = "\((loadingLocation as NSString).lastPathComponent) · \(detail)"
    }

    func reloadEncoding() {
        if let url = archive?.url { open(url) }
    }

    func clearPreview() {
        sceneCancellation.cancel(); sceneCancellation = CancellationFlag()
        textPreviewBytes = nil
        textPreviewFailure = nil
        formattedJSON = nil
        previewID = UUID()
        paletteRequestID = UUID()
        actionRenderID = UUID()
        audio?.stop()
        audio = nil
        playing = false
        spritePlaying = false
        frameIndex = 0
        actionIndex = 0
        actionDocument = nil
        spriteDocument = nil
        spriteBytes = nil
        overridePalette = nil
        paletteSelection = nil
        paletteLabel = "Embedded palette"
        externalPreviewName = nil
        frameDuration = 0.125
        viewedPalette = nil
        preview = .empty
    }

    func loadPreview() {
        clearPreview()
        guard showPreview, let entry = currentEntry, let file = resourceFile(entry.id) else { return }
        // Previews are bounded; extraction remains available for larger files.
        guard entry.size <= 64 * 1024 * 1024 else {
            preview = .message("This file is too large to preview. Extract it to open in another app.")
            return
        }
        let id = previewID
        preview = .loading
        Task {
            do {
                let bytes = try await Task.detached(priority: .userInitiated) { try file.data() }.value
                guard previewID == id else { return }
                let ext = (entry.path as NSString).pathExtension.lowercased()
                if ext == "spr" {
                    let document = try await Task.detached { try SpriteDecoder.document(from: bytes) }.value
                    guard previewID == id else { return }
                    spriteBytes = bytes
                    spriteDocument = document
                    preview = document.frames.isEmpty ? .message("This sprite has no frames.") : .sprite(document.frames)
                } else if ext == "fna" {
                    let names = encoding
                    let info = try await Task.detached { try Self.resourceInfo(bytes, extension: ext, encoding: names) }.value
                    guard previewID == id else { return }
                    preview = .resourceInfo(info)
                } else if ["rsw", "rsm", "imf", "gr2"].contains(ext) {
                    let names = encoding, files = sceneResources, sceneFlag = sceneCancellation
                    let localRoot = browsingLocal ? Self.resourceRoot(localDirectory) : nil
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        if ext == "gr2" { return try GrannyScene.prepare(bytes, path: entry.path, files: files, localRoot: localRoot, cancelled: { sceneFlag.isCancelled }) }
                        let document = try ScenePreviewDocument.decode(bytes, extension: ext, encoding: names)
                        return PreparedScene.prepare(document, files: files, localRoot: localRoot, encoding: names, cancelled: { sceneFlag.isCancelled })
                    }.value
                    guard previewID == id else { return }
                    preview = .scene(prepared)
                } else if ["gat", "gnd"].contains(ext) {
                    let names = encoding
                    let result = try await Task.detached { let map = try MapDocument.decode(bytes, encoding: names); return (map, map.raster()) }.value
                    guard previewID == id else { return }
                    preview = .map(result.0, result.1, file.source)
                } else if ext == "pal" {
                    let colors = try await Task.detached { try PaletteDecoder.colors(from: bytes) }.value
                    guard previewID == id else { return }
                    viewedPalette = bytes
                    preview = .palette(colors)
                } else if ext == "act" {
                    let document = try await Task.detached { try ActionDecoder.decode(bytes) }.value
                    guard previewID == id else { return }
                    actionDocument = document
                    actionIndex = document.firstDrawableActionIndex ?? 0
                    let stem = (entry.path as NSString).deletingPathExtension
                    actionCompanionName = stem + ".spr"
                    if let companion = entries.first(where: { $0.path.caseInsensitiveCompare(actionCompanionName) == .orderedSame }) {
                        guard let companionFile = resourceFile(companion.id) else { return }
                        let data = try await Task.detached { try companionFile.data() }.value
                        let sprite = try await Task.detached { try SpriteDecoder.document(from: data) }.value
                        guard previewID == id else { return }
                        spriteBytes = data
                        spriteDocument = sprite
                        renderAction()
                    } else {
                        preview = .message("ACT contains animation instructions and needs its matching SPR image file. Choose \((actionCompanionName as NSString).lastPathComponent) to preview the animation.")
                    }
                } else if ["lua", "lub"].contains(ext) {
                    let selectedEncoding = encoding
                    let script = try await Task.detached { try LuaPreviewer.preview(bytes, encoding: selectedEncoding) }.value
                    guard previewID == id else { return }
                    preview = .script(script)
                } else if let image = NSImage(data: bytes) {
                    preview = .image(image)
                } else if ["wav", "mp3", "aiff", "ogg"].contains(ext) {
                    audio = try AVAudioPlayer(data: bytes)
                    audio?.prepareToPlay()
                    preview = .audio(audio?.duration ?? 0)
                } else if ResourceSearch.textExtensions.contains(ext) || Self.looksLikeText(bytes) {
                    textPreviewBytes = bytes
                    refreshTextPreview()
                } else {
                    preview = .inspection(ResourceInspection.inspect(bytes, name: entry.path), nil)
                }
            } catch {
                guard previewID == id else { return }
                if let data = try? file.data() {
                    preview = .inspection(ResourceInspection.inspect(data, name: entry.path), error.localizedDescription)
                } else { preview = .message(error.localizedDescription) }
            }
        }
    }

    func choosePreviewFile() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Preview Resource"
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPreview(url)
    }

    func openPreview(_ url: URL) { browseLocalFile(url) }

    nonisolated static func previewData(from url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw GRFError.invalid("This preview file exceeds the 64 MiB limit.") }
        return try Data(contentsOf: url)
    }

    func chooseCompanion() {
        let panel = NSOpenPanel()
        panel.title = "Choose Matching SPR"
        panel.message = "Choose \((actionCompanionName as NSString).lastPathComponent), or the matching sprite from another location."
        panel.allowedContentTypes = [UTType(filenameExtension: "spr")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = previewID
        Task {
            do {
                let data = try await Task.detached { try Self.previewData(from: url) }.value
                let document = try await Task.detached { try SpriteDecoder.document(from: data) }.value
                guard previewID == id else { return }
                spriteBytes = data
                spriteDocument = document
                actionCompanionName = url.lastPathComponent
                paletteLabel = "Embedded palette"
                overridePalette = nil
                renderAction()
            } catch { if previewID == id { self.error = error.localizedDescription } }
        }
    }

    func chooseSpriteForPalette() {
        guard let palette = viewedPalette else { return }
        let name = previewName
        let panel = NSOpenPanel()
        panel.title = "Choose Sprite for This Palette"
        panel.allowedContentTypes = [UTType(filenameExtension: "spr")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = previewID
        Task {
            do {
                let bytes = try await Task.detached { try Self.previewData(from: url) }.value
                let document = try await Task.detached { try SpriteDecoder.document(from: bytes, palette: palette) }.value
                guard previewID == id else { return }
                spriteBytes = bytes
                spriteDocument = document
                externalPreviewName = url.lastPathComponent
                paletteLabel = name
                overridePalette = palette
                preview = document.frames.isEmpty ? .message("This sprite has no frames.") : .sprite(document.frames)
                frameIndex = 0
            } catch { if previewID == id { self.error = error.localizedDescription } }
        }
    }

    func renderAction() {
        guard let actionDocument, let spriteDocument else { return }
        guard actionDocument.actions.indices.contains(actionIndex) else {
            preview = .message("This ACT has no animation actions.")
            return
        }
        spritePlaying = false
        frameIndex = 0
        let action = actionDocument.actions[actionIndex]
        guard Self.hasVisibleLayers(action) else {
            preview = .message("This action contains no visible sprite layers. Choose another action above.")
            return
        }
        frameDuration = action.frameDuration
        let id = previewID
        let selectedAction = actionIndex
        actionRenderID = UUID()
        let renderID = actionRenderID
        preview = .loading
        Task {
            do {
                let frames = try await Task.detached {
                    try ActionRenderer.render(action: action, sprites: spriteDocument.frames, indexedCount: spriteDocument.indexedFrameCount)
                }.value
                guard previewID == id, actionIndex == selectedAction, actionRenderID == renderID else { return }
                preview = frames.isEmpty ? .message("This action has no frames.") : .sprite(frames)
            } catch {
                guard previewID == id, actionIndex == selectedAction, actionRenderID == renderID else { return }
                preview = .message(error.localizedDescription)
            }
        }
    }

    nonisolated static func hasVisibleLayers(_ action: SpriteAction) -> Bool {
        action.frames.contains { frame in
            frame.layers.contains { layer in
                layer.spriteIndex >= 0 && layer.scaleX != 0 && layer.scaleY != 0 && layer.color.last != 0
            }
        }
    }

    func choosePalette() {
        let panel = NSOpenPanel()
        panel.title = "Apply Palette to Sprite"
        panel.allowedContentTypes = [UTType(filenameExtension: "pal")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = previewID
        Task {
            do {
                let data = try await Task.detached { try Self.previewData(from: url) }.value
                guard previewID == id else { return }
                applyPalette(data, label: url.lastPathComponent)
            } catch { if previewID == id { self.error = error.localizedDescription } }
        }
    }

    func useArchivePalette(_ entry: GRFEntry) {
        guard let file = resourceFile(entry.id) else { return }
        let id = previewID
        Task {
            do {
                let data = try await Task.detached { try file.data() }.value
                guard previewID == id else { return }
                applyPalette(data, label: (entry.path as NSString).lastPathComponent)
            } catch { if previewID == id { self.error = error.localizedDescription } }
        }
    }

    func applyPalette(_ palette: Data?, label: String = "Embedded palette") {
        guard let bytes = spriteBytes else { return }
        spritePlaying = false
        let id = previewID
        paletteRequestID = UUID()
        let request = paletteRequestID
        Task {
            do {
                let document = try await Task.detached { try SpriteDecoder.document(from: bytes, palette: palette) }.value
                guard previewID == id, paletteRequestID == request else { return }
                spriteDocument = document
                overridePalette = palette
                paletteLabel = label
                if isActionPreview { renderAction() }
                else { preview = document.frames.isEmpty ? .message("This sprite has no frames.") : .sprite(document.frames) }
            } catch { if previewID == id, paletteRequestID == request { self.error = error.localizedDescription } }
        }
    }

    func saveSprite(all: Bool) {
        let frames = previewFrames
        guard !busy, !frames.isEmpty else { return }
        spritePlaying = false
        let name = (previewName as NSString).deletingPathExtension
        let destination: URL
        if all {
            let panel = NSOpenPanel()
            panel.title = "Save All Frames as BMP"
            panel.message = "Frames are numbered 00000.bmp, 00001.bmp, and so on. Existing files are not overwritten."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        } else {
            let panel = NSSavePanel()
            panel.title = "Save Current Frame as BMP"
            panel.allowedContentTypes = [.bmp]
            panel.nameFieldStringValue = "\(name)_\(String(format: "%05d", frameIndex)).bmp"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }
        let selected = min(frameIndex, frames.count - 1)
        let alpha = transparent
        busy = true
        status = "Saving bitmap frames…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if all {
                        let targets = frames.indices.map { destination.appendingPathComponent(String(format: "%05d.bmp", $0)) }
                        guard !targets.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                            throw GRFError.invalid("An output bitmap already exists. Choose an empty folder.")
                        }
                        for (index, frame) in frames.enumerated() {
                            try SpriteExporter.bmp(frame: frame, transparent: alpha).write(to: targets[index], options: .withoutOverwriting)
                        }
                    } else {
                        try SpriteExporter.bmp(frame: frames[selected], transparent: alpha).write(to: destination, options: .atomic)
                    }
                }.value
                status = all ? "Saved \(frames.count) bitmap frames." : "Saved \(destination.lastPathComponent)."
            } catch { self.error = error.localizedDescription; status = "Could not save bitmap frames." }
            busy = false
        }
    }

    nonisolated static func resourceInfo(_ bytes: Data, extension ext: String, encoding: FilenameEncoding) throws -> String {
        if ext == "fna" {
            let document = try FilenameListPreview.decode(bytes, encoding: encoding)
            return document.readableSummary + "\n\nJSON\n" + (try document.json())
        }
        let document = try GrannyPreviewDocument.decode(bytes)
        let sectionStatus: String
        do {
            let sections = try GrannySectionDecoder.decode(bytes)
            let count = sections.filter { !$0.isEmpty }.count
            let total = sections.reduce(0) { $0 + $1.count }
            sectionStatus = "Native section decompression succeeded: \(count) nonempty sections, \(total) decoded bytes. No Windows DLL was loaded."
        } catch {
            sectionStatus = "Native section decompression unavailable for this file: \(error.localizedDescription)"
        }
        return document.readableSummary + "\n\n" + sectionStatus + "\n\nJSON\n" + (try document.json())
    }

    func refreshTextPreview() {
        guard let bytes = textPreviewBytes else { return }
        do {
            let result = try TextPreviewDecoder.preview(bytes, encoding: textEncoding, maximumBytes: searchScope != "Filename" && !submittedQuery.isEmpty ? 16 * 1024 * 1024 : TextPreviewDecoder.limit)
            textPreviewFailure = nil
            formattedJSON = nil
            if currentEntry?.path.lowercased().hasSuffix(".json") == true,
               let object = try? JSONSerialization.jsonObject(with: Data(result.text.utf8), options: [.fragmentsAllowed]),
               let bytes = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
                formattedJSON = String(decoding: bytes, as: UTF8.self)
            }
            preview = .text(result)
        } catch {
            textPreviewFailure = error.localizedDescription
            preview = .text(TextPreview(text: "", encodingLabel: textEncoding.label))
        }
    }

    func refreshAudioState() {
        if playing && audio?.isPlaying != true { playing = false }
    }

    func toggleAudio() {
        guard let audio else { return }
        if playing { audio.pause(); playing = false }
        else { audio.currentTime = audio.currentTime >= audio.duration ? 0 : audio.currentTime; playing = audio.play() }
    }

    func saveSelectedAs() {
        guard !busy, let entry = currentEntry, let file = resourceFile(entry.id) else { return }
        let panel = NSSavePanel()
        panel.title = "Extract File As"
        panel.nameFieldStringValue = (entry.path as NSString).lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        status = "Extracting \(entry.path)…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let bytes = try file.data(limit: 512 * 1024 * 1024)
                    try bytes.write(to: destination, options: .atomic)
                }.value
                status = "Extracted \(destination.lastPathComponent)."
            } catch {
                self.error = error.localizedDescription
                status = "Could not extract file."
            }
            busy = false
        }
    }

    func extract(all: Bool) { extractWorkspace(all: all) }

    func cancel() { cancellation.cancel() }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell = 12.0
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .controlBackgroundColor)))
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    let rect = CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color(Color.gray.opacity(0.17)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PalettePreview: View {
    let colors: [PaletteColor]
    let chooseSprite: () -> Void
    @State private var selected = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("256-color palette").font(.headline)
            Text("Index 0 is transparent when applied to indexed SPR frames.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 16), spacing: 2) {
                    ForEach(colors.indices, id: \.self) { index in
                        let color = colors[index]
                        Rectangle().fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { if selected == index { Rectangle().stroke(.white, lineWidth: 2).padding(1) } }
                            .contentShape(Rectangle())
                            .onTapGesture { selected = index }
                            .help("Index \(index): RGB \(color.red), \(color.green), \(color.blue); alpha \(color.alpha)")
                            .accessibilityLabel("Palette color \(index)")
                    }
                }
            }
            if colors.indices.contains(selected) {
                let color = colors[selected]
                Text("Index \(selected) · RGB \(color.red), \(color.green), \(color.blue) · A \(color.alpha)")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Button("Try Palette on SPR…", action: chooseSprite).buttonStyle(.bordered)
        }.padding(14)
    }
}

private struct ArchivePalettePicker: View {
    let entries: [GRFEntry]
    let select: (GRFEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var matches: [GRFEntry] {
        Array(entries.lazy.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }.prefix(300))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Palette from Archive").font(.title3.bold())
            TextField("Search PAL filenames", text: $search).textFieldStyle(.roundedBorder)
            List(matches) { entry in
                Button { select(entry) } label: {
                    FileNameLabel(text: entry.path, icon: "paintpalette").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help(entry.path)
            }
            HStack {
                Text("Showing up to 300 matches of \(entries.count.formatted()) palettes.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(20).frame(width: 650, height: 480)
    }
}

enum PreviewContent {
    case empty, loading, message(String), image(NSImage), text(TextPreview), script(ScriptPreview), audio(TimeInterval), sprite([SpriteFrame]), palette([PaletteColor])
    case map(MapDocument, MapRaster, URL)
    case scene(PreparedScene)
    case resourceInfo(String)
    case inspection(ResourceInspection, String?)
}

private struct FileNameLabel: View {
    let text: String
    let icon: String
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: icon).frame(width: 22, height: 20, alignment: .center).accessibilityHidden(true)
            Text(text).lineLimit(1)
        }
    }
}

private struct ToolbarCaption: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 18)).frame(height: 32)
            Text(title).font(.system(size: 10)).frame(height: 14).fixedSize()
        }.frame(minWidth: 44).padding(.horizontal, 2)
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
    }
}

private struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel
    @State private var formatJSON = true
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showEncoding = false
    @State private var showArchiveActions = false
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
    private var navigation: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $model.folder) {
                Section("Sources") {
                    if model.draft != nil {
                        Label((model.archive?.url.lastPathComponent ?? "New GRF") + (model.pendingCount > 0 ? " · \(model.pendingCount) changes" : ""), systemImage: model.browsingLocal ? "archivebox" : "archivebox.fill")
                            .tag("source:archive")
                    }
                    if let directory = model.localDirectory {
                        Label(directory.lastPathComponent, systemImage: model.browsingLocal ? "folder.fill" : "folder").tag("source:local").help(directory.path)
                    }
                }
                FileNameLabel(text: "All Files", icon: "tray.full").tag("")
                Section("Folders") {
                    OutlineGroup(model.folders, children: \.children) { folder in
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "folder").frame(width: 22, height: 20, alignment: .center).accessibilityHidden(true)
                            Text(folder.name).font(.callout).lineLimit(1).layoutPriority(1)
                            if let english = FolderGlossary.english(for: folder.name) {
                                Text(english).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.tag(folder.path)
                            .help(folder.path + (FolderGlossary.english(for: folder.name).map { "\n" + $0 } ?? ""))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .modifier(SidebarGlassEffect())
            .disabled(model.loading)
            .navigationSplitViewColumnWidth(min: 180, ideal: 280, max: 420)
            .overlay {
                if !model.hasSource { ContentUnavailableView("Choose a Source", systemImage: "archivebox", description: Text("Open a GRF or any local resource.")) }
            }
        } detail: {
            VStack(spacing: 0) {
                HSplitView {
                    GeometryReader { bounds in
                        fileList.frame(width: bounds.size.width, height: bounds.size.height)
                    }.frame(minWidth: 320, idealWidth: 470)
                    if model.showPreview {
                        GeometryReader { bounds in
                            previewPane.frame(width: bounds.size.width, height: bounds.size.height)
                        }.frame(minWidth: 250, idealWidth: 340)
                    }
                }
                if model.draft != nil && !model.browsingLocal { pendingChanges }
                Divider()
                statusBar
            }
        }
    }

    private var selectionAwareNavigation: some View {
        VStack(spacing: 0) {
            archiveToolbar.fixedSize(horizontal: false, vertical: true)
            navigation.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.hasSource ? model.sourceLabel : "GRF Tool")
        .toolbar(removing: .sidebarToggle)
        .toolbar(.hidden, for: .windowToolbar)
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: model.selection) { _, _ in model.hitOccurrence = 0; model.loadPreview() }
        .onChange(of: model.showPreview) { _, _ in
            if model.externalPreviewName == nil { model.loadPreview() }
            else { model.spritePlaying = false }
        }
        .onChange(of: model.encoding) { _, _ in model.reloadEncoding() }
        .onChange(of: model.textEncoding) { _, _ in model.refreshTextPreview() }
        .onChange(of: model.sortOrder) { _, _ in model.updateVisibleEntries() }
        .onChange(of: model.actionIndex) { _, _ in model.renderAction() }
    }

    var body: some View {
        selectionAwareNavigation
        .onChange(of: model.localDirectory) { _, _ in columnVisibility = .all }
        .onChange(of: model.browsingLocal) { _, _ in columnVisibility = .all }
        .onChange(of: model.archive?.url) { _, _ in columnVisibility = .all }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in model.refreshAudioState() }
        .onChange(of: model.folder) { _, value in
            if value == "source:archive" { model.folder = ""; model.switchSource(local: false) }
            else if value == "source:local" { model.folder = ""; model.switchSource(local: true) }
            else { model.updateVisibleEntries(); model.selection.formIntersection(Set(model.visibleEntries.map(\.id))) }
        }
        .onChange(of: model.search) { _, _ in
            if model.searchScope == "Filename" { model.searchChanged() }
            else { model.stopContentSearch(); model.submittedQuery = ""; model.searchHits = []; model.updateVisibleEntries() }
        }
        .onChange(of: model.searchScope) { _, _ in model.stopContentSearch(); model.submittedQuery = ""; model.searchHits = []; model.updateVisibleEntries() }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.busy, let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .alert(model.extractionNotice == nil ? "Could Not Complete Operation" : "Extraction Report", isPresented: Binding(get: { model.error != nil || model.extractionNotice != nil }, set: { if !$0 { model.error = nil; model.extractionNotice = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.extractionNotice ?? model.error ?? "") }
        .sheet(isPresented: $model.showBuilder) {
            GRFBuilderView(protectedArchive: model.archive?.url,
                           source: model.builderMode == .new ? nil : model.archive,
                           sourceEncoding: model.encoding, mode: model.builderMode,
                           removing: model.builderMode == .delete ? Set(model.selectedEntries.map(\.path)) : []) { url, encoding in
                model.showBuilder = false
                model.encoding = encoding
                model.open(url)
            }
        }
        .sheet(isPresented: $model.showPaletteBrowser) {
            ArchivePalettePicker(entries: model.paletteEntries) { entry in
                model.showPaletteBrowser = false
                model.useArchivePalette(entry)
            }
        }
    }

    private var archiveToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly } label: { Image(systemName: "sidebar.left") }.help("Toggle sidebar")
                Button(action: model.chooseArchive) { Label("Open", systemImage: "folder") }.disabled(model.busy)
                Button(action: model.choosePreviewFile) { Label("Local File", systemImage: "doc.viewfinder") }.disabled(model.busy)
                Menu {
                    Button("New GRF…", action: model.newArchive)
                    Button("Add Files / Folders…") { model.addResources() }
                    Button("Replace Selected…", action: model.replaceSelected).disabled(model.selection.count != 1)
                    Button("Rename Selected…", action: model.renameSelected).disabled(model.selection.count != 1)
                    Button("Delete Selected", action: model.deleteSelected).disabled(model.selection.isEmpty)
                    Divider()
                    Button("Merge GRF…", action: model.mergeResources)
                    Button("Import Folder…") { model.addResources(folderOnly: true) }
                    Button("Repack As…", action: model.saveWorkspace)
                } label: { Label("Manage", systemImage: "square.stack.3d.up") }.disabled(model.busy || model.browsingLocal)
                Button { model.extract(all: false) } label: { Label("Extract", systemImage: "square.and.arrow.down") }.disabled(model.busy || model.selection.isEmpty)
                Menu {
                    Button("Extract All…") { model.extract(all: true) }
                    Button("Extract File As…", action: model.saveSelectedAs).disabled(model.selection.count != 1)
                } label: { Image(systemName: "chevron.down") }.disabled(model.busy || !model.hasSource)
                Button(action: model.saveWorkspace) { Label("Save GRF As…", systemImage: "square.and.arrow.up") }.disabled(model.busy || model.browsingLocal || model.draft == nil)
                Spacer()
                Button { model.showPreview.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle preview")
                Menu {
                    Button("Text / Filename Encoding…") { showEncoding = true }
                    Button("Credits & Sources…") { openWindow(id: "credits") }
                    SettingsLink { Text("Settings…") }
                } label: { Image(systemName: "ellipsis.circle") }
                .popover(isPresented: $showEncoding) {
                    Form {
                        Picker("Text Encoding", selection: $model.textEncoding) { ForEach(TextPreviewEncoding.allCases, id: \.self) { Text($0.label).tag($0) } }
                        Picker("Archive Filename Encoding", selection: $model.encoding) { ForEach(FilenameEncoding.allCases, id: \.self) { Text($0.label).tag($0) } }
                    }.padding(18).frame(width: 440)
                }
            }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            HStack(spacing: 12) {
                Picker("Search in", selection: $model.searchScope) {
                    Text("Filename").tag("Filename"); Text("Content").tag("Content"); Text("All").tag("All")
                }.pickerStyle(.segmented).frame(width: 250)
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(model.searchScope == "Filename" ? "Search paths or filenames · *.spr" : "Search text in this source · Press Return", text: $model.search)
                    .textFieldStyle(.plain).focused($searchFocused).onSubmit { model.runContentSearch() }.accessibilityLabel("Search resources")
                if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
                if model.searchScope != "Filename" {
                    if model.searchRunning {
                        ProgressView(value: model.searchProgress).frame(width: 85)
                        Button("Cancel", action: model.stopContentSearch)
                    } else { Button("Search", action: model.runContentSearch).disabled(model.busy || model.search.isEmpty) }
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.background(.bar)
    }

    private var pendingChanges: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button { model.showChanges.toggle() } label: {
                    Label("Pending Changes · \(model.pendingCount)", systemImage: model.showChanges ? "chevron.down" : "chevron.right")
                }.buttonStyle(.plain).font(.callout.weight(.medium))
                Spacer()
                Button("Undo Last", action: model.undoLastChange).disabled(model.busy || model.draft?.canUndo != true)
                Button("Undo All", action: model.revertAllChanges).disabled(model.busy || model.pendingCount == 0)
                Button("Save GRF As…", action: model.saveWorkspace).disabled(model.busy)
            }.padding(10)
            if model.showChanges && model.pendingCount > 0 {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.draft?.changes ?? []) { change in
                            HStack {
                                Text(change.status).font(.caption.weight(.semibold)).frame(width: 110, alignment: .leading).foregroundStyle(change.deleted ? .red : .orange)
                                VStack(alignment: .leading) {
                                    Text(change.file.path).lineLimit(1).truncationMode(.middle)
                                    if let old = change.originalPath, old != change.file.path { Text("From: " + old).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button("Reveal") { model.folder = ""; model.search = ""; model.selection = [change.id] }
                                Button("Undo") { model.revertChange(change.id) }
                            }.padding(.horizontal, 12).padding(.vertical, 7)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 170).disabled(model.busy)
            }
        }.background(.background)
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.folder.isEmpty ? "All Files" : model.folder).font(.headline).lineLimit(1)
                Spacer()
                Text("\(model.visibleEntries.count.formatted()) files").foregroundStyle(.secondary)
            }.padding(14)
            Divider()
            if model.searchScope != "Filename" && !model.submittedQuery.isEmpty {
                if !model.searchFailures.isEmpty {
                    Text("\(model.searchFailures.count) files skipped · \(model.searchFailures.first ?? "")").font(.caption).foregroundStyle(.secondary).padding(8).textSelection(.enabled)
                }
                List(selection: $model.selection) {
                    ForEach(model.visibleEntries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(entry.path, systemImage: fileIcon(entry.path)).font(.callout.weight(.medium))
                            if let hit = model.searchHits.first(where: { $0.resourceID == entry.id }) {
                                Text("\(hit.count) matches · Line \(hit.line)").font(.caption).foregroundStyle(.secondary)
                                Text(hit.snippet).font(.caption.monospaced()).lineLimit(3)
                            } else { Text("Filename match").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4).tag(entry.id)
                    }
                }
            } else {
            ArchiveFileTable(entries: model.visibleEntries, revision: model.fileListRevision, selection: $model.selection,
                             sortChanged: model.sortFiles, icon: fileIcon, busy: model.busy,
                             extractAs: model.saveSelectedAs, extractSelected: { model.extract(all: false) },
                             copyPaths: {
                                 NSPasteboard.general.clearContents()
                                 NSPasteboard.general.setString(model.selectedEntries.map(\.path).joined(separator: "\n"), forType: .string)
                             }, resourceStatus: model.statusForEntry, canEdit: !model.browsingLocal,
                             replace: model.replaceSelected, rename: model.renameSelected, delete: model.deleteSelected)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(model.loading)
            .overlay {
                if !model.hasSource {
                    ContentUnavailableView {
                        Label("Explore Your Game Resources", systemImage: "archivebox")
                    } description: {
                        Text("Drop a GRF or GPF archive here, or choose Open.\nBrowse, preview and extract without changing the archive.")
                    } actions: {
                        Button("Open Archive…", action: model.chooseArchive).buttonStyle(.borderedProminent).disabled(model.busy)
                    }
                } else if model.visibleEntries.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                }
            }
            }
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.currentEntry == nil ? "Preview" : model.previewName).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let id = model.currentEntry?.id, !model.statusForEntry(id).isEmpty { Text(model.statusForEntry(id)).font(.caption).foregroundStyle(.orange) }
            }.padding(14)
            Divider()
            if model.searchScope != "Filename" && !model.submittedQuery.isEmpty {
                HStack {
                    Text("Find: " + model.submittedQuery).font(.caption).lineLimit(1)
                    Spacer()
                    Button { model.hitOccurrence -= 1 } label: { Image(systemName: "chevron.up") }.help("Previous match").accessibilityLabel("Previous match")
                    Button { model.hitOccurrence += 1 } label: { Image(systemName: "chevron.down") }.help("Next match").accessibilityLabel("Next match")
                }.padding(8)
            }
            if let document = model.actionDocument {
                Picker("Action", selection: $model.actionIndex) {
                    ForEach(document.actions.indices, id: \.self) { action in
                        Text(actionLabel(action, count: document.actions.count)).tag(action)
                    }
                }.padding(.horizontal).padding(.top, 10)
                Text("\(document.actions.count) actions · \(document.sounds.count) sound events")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            Group {
                switch model.preview {
                case .empty:
                    ContentUnavailableView("Select a File", systemImage: "doc.viewfinder", description: Text("Preview images, text, Lua/LUB scripts, audio, SPR sprites, PAL colors, ACT animations, GAT/GND maps, RSW scenes, RSM/GR2 models, IMF layers and FNA information."))
                case .loading:
                    VStack { Spacer(); ProgressView("Loading preview…"); Spacer() }.frame(maxWidth: .infinity)
                case .message(let text):
                    VStack {
                        ContentUnavailableView("Preview Unavailable", systemImage: "doc.questionmark", description: Text(text))
                        if model.isActionPreview {
                            Button("Choose Matching SPR…", action: model.chooseCompanion).padding(.bottom)
                        }
                    }
                case .image(let image):
                    ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 700, maxHeight: 700).padding() }
                case .text(let document):
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("Text Encoding", selection: $model.textEncoding) {
                                ForEach(TextPreviewEncoding.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.pickerStyle(.menu).controlSize(.small)
                            if model.formattedJSON != nil && model.submittedQuery.isEmpty { Toggle("Format JSON", isOn: $formatJSON).toggleStyle(.checkbox).font(.caption) }
                            Text(model.textPreviewFailure == nil ? "Decoded as: \(document.encodingLabel)" : "Choose another encoding")
                                .font(.caption).foregroundStyle(.secondary)
                            if let warning = document.warning {
                                Text(warning).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                            }
                        }.padding(10)
                        Divider()
                        if let failure = model.textPreviewFailure {
                            Text(failure).foregroundStyle(.secondary).padding()
                            Spacer()
                        } else {
                            PlainTextPreview(text: formatJSON && model.submittedQuery.isEmpty ? (model.formattedJSON ?? document.text) : document.text, query: model.searchScope == "Filename" ? "" : model.submittedQuery, occurrence: model.hitOccurrence)
                        }
                    }
                case .inspection(let document, let reason):
                    RawResourcePreview(document: document, reason: reason)
                case .resourceInfo(let info):
                    PlainTextPreview(text: info)
                case .script(let script):
                    VStack(alignment: .leading, spacing: 0) {
                        Text(script.format).font(.caption).foregroundStyle(.secondary).padding(10)
                        Divider()
                        PlainTextPreview(text: script.text, query: model.searchScope == "Filename" ? "" : model.submittedQuery, occurrence: model.hitOccurrence)
                    }
                case .audio(let duration):
                    VStack(spacing: 18) {
                        Spacer()
                        Image(systemName: "waveform").font(.system(size: 56)).foregroundStyle(.tint)
                        Text("\(Int(duration / 60)):\(String(format: "%02d", Int(duration) % 60))").monospacedDigit()
                        Button(action: model.toggleAudio) { Label(model.playing ? "Pause" : "Play", systemImage: model.playing ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                case .sprite(let frames):
                    spritePreview(frames)
                case .scene(let document):
                    SceneResourcePreviewView(prepared: document).id(model.previewID)
                case .map(let document, let raster, let source):
                    MapPreviewView(document: document, raster: raster, sourceURL: source, name: model.previewName).id(document.id)
                case .palette(let colors):
                    PalettePreview(colors: colors, chooseSprite: model.chooseSpriteForPalette)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.externalPreviewName != nil || model.currentEntry != nil {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.previewName).font(.callout.weight(.medium)).textSelection(.enabled)
                    if model.externalPreviewName == nil, let entry = model.currentEntry {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(12)
            }
        }.background(.background)
    }

    private func spritePreview(_ frames: [SpriteFrame]) -> some View {
        let index = min(max(0, model.frameIndex), frames.count - 1)
        let frame = frames[index]
        return VStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = spriteImage(frame, transparent: model.transparent) {
                    Image(nsImage: image).resizable().interpolation(.none)
                        .frame(width: Double(frame.width) * model.zoom, height: Double(frame.height) * model.zoom)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Checkerboard().opacity(model.transparent ? 1 : 0) }
            HStack {
                Toggle("Transparent", isOn: $model.transparent).toggleStyle(.checkbox)
                Spacer()
                Text("\(frame.width) × \(frame.height)").foregroundStyle(.secondary)
            }.font(.caption).padding(.horizontal, 12)
            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $model.zoom, in: 0.25...8, step: 0.25)
                Text("\(Int(model.zoom * 100))% ").monospacedDigit().frame(width: 42)
            }.padding(.horizontal, 12)
            HStack {
                Button { model.frameIndex -= 1 } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                Text("\(index + 1) / \(frames.count)").monospacedDigit().frame(minWidth: 90)
                Button { model.frameIndex += 1 } label: { Image(systemName: "chevron.right") }.disabled(index + 1 == frames.count)
                Button { model.spritePlaying.toggle() } label: { Image(systemName: model.spritePlaying ? "pause.fill" : "play.fill") }
                    .help(model.isActionPreview ? "Play at the ACT frame rate" : "Cycle sprite frames at 8 frames per second")
            }.padding(.vertical, 6)
            HStack {
                Menu {
                    Button("Load PAL File…", action: model.choosePalette)
                    Button("Choose PAL from Archive…") { model.showPaletteBrowser = true }.disabled(model.paletteEntries.isEmpty)
                    Button("Reset Palette") { model.applyPalette(nil) }
                    if model.isActionPreview { Button("Change Matching SPR…", action: model.chooseCompanion) }
                } label: { Label("Palette", systemImage: "paintpalette") }
                Spacer()
                Button("Save One") { model.saveSprite(all: false) }.disabled(model.busy)
                    .help("Save the displayed frame as BMP")
                Button("Save All") { model.saveSprite(all: true) }.disabled(model.busy)
                    .help(model.isActionPreview ? "Save all frames in the selected action as BMP" : "Save every SPR frame as BMP")
            }.padding(.horizontal, 12)
            Text(model.paletteLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(model.paletteLabel)
                .padding(.horizontal).padding(.bottom, 8)
        }
        .task(id: model.spritePlaying) {
            guard model.spritePlaying else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(0.01, model.frameDuration))) } catch { return }
                guard model.spritePlaying else { return }
                model.frameIndex = (model.frameIndex + 1) % frames.count
            }
        }
    }

    private func actionLabel(_ index: Int, count: Int) -> String {
        let directions = ["South", "Southwest", "West", "Northwest", "North", "Northeast", "East", "Southeast"]
        return count >= 8 && count % 8 == 0 ? "Action \(index / 8) · \(directions[index % 8]) [\(index)]" : "Action \(index)"
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.busy && !model.loading { ProgressView().controlSize(.small) }
            Text(model.status).font(.caption).lineLimit(1).help(model.loadingLocation)
            Spacer()
            if let fraction = model.loadingFraction {
                ProgressView(value: fraction, total: 1).frame(width: 160).accessibilityLabel("Archive loading progress")
                Button("Cancel", action: model.cancel).controlSize(.small)
            } else if model.extracting {
                ProgressView(value: Double(model.completed), total: Double(max(1, model.total))).frame(width: 130)
                Text("\(model.completed) / \(model.total)").font(.caption).monospacedDigit()
                Button("Cancel", action: model.cancel).controlSize(.small)
            } else if !model.selection.isEmpty {
                Text("\(model.selection.count) selected").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func fileIcon(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "bmp", "png", "jpg", "jpeg", "tga", "spr": return "photo"
        case "pal": return "paintpalette"
        case "act": return "figure.walk"
        case "gat", "gnd", "rsw": return "map"
        case "rsm", "gr2": return "cube"
        case "imf": return "square.3.layers.3d"
        case "wav", "mp3", "ogg": return "waveform"
        case "txt", "xml", "lua", "lub", "json": return "doc.text"
        default: return "doc"
        }
    }

    private func spriteImage(_ frame: SpriteFrame, transparent: Bool) -> NSImage? {
        var data = frame.rgba
        if !transparent { for offset in stride(from: 3, to: data.count, by: 4) { data[offset] = 255 } }
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: frame.width, height: frame.height))
    }
}
