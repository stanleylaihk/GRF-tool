import SwiftUI
import GRFDesktop
import AppKit
import UniformTypeIdentifiers
import GRFCore

enum GRFBuilderMode {
    case new, edit, delete, repack
    var title: String {
        switch self {
        case .new: return "New GRF"
        case .edit: return "Merge / Edit GRF"
        case .delete: return "Delete Resources"
        case .repack: return "Repack GRF"
        }
    }
}

private final class BuildCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

@MainActor
private final class GRFBuilderModel: ObservableObject {
    @Published var files: [GRFBuildFile] = []
    @Published var selection = Set<String>()
    @Published var encoding: FilenameEncoding
    @Published var importEncoding: FilenameEncoding
    @Published var policy = GRFMergePolicy.keepExisting
    @Published var busy = false
    @Published var ready = true
    @Published var dirty = false
    @Published var canUndoDelete = false
    @Published var fraction: Double?
    @Published var status = "Import a folder or GRF to start. Selected folder names are kept."
    @Published var error: String?
    private var deletionUndo: ([GRFBuildFile], Bool)?
    private var protectedSources = Set<URL>()
    private var cancellation = BuildCancellation()
    private var operation = UUID()

    init(source: GRFArchive?, encoding: FilenameEncoding, removing paths: Set<String>) {
        self.encoding = encoding; self.importEncoding = encoding
        guard let source else { return }
        protectedSources.insert(source.url.resolvingSymlinksInPath().standardizedFileURL)
        busy = true; ready = false; status = "Preparing working copy…"
        let flag = cancellation
        Task {
            do {
                files = try await Task.detached(priority: .userInitiated) {
                    try GRFBuildFile.fromArchive(source, cancelled: { flag.cancelled })
                }.value
                ready = true
                status = "\(files.count.formatted()) files in working copy. Original archive is unchanged."
                if !paths.isEmpty { selection = paths; removeSelected() }
            } catch is GRFBuildError { status = "Preparation cancelled. Close and reopen to try again." }
            catch { self.error = error.localizedDescription; status = "Could not prepare archive." }
            busy = false
        }
    }

    func cancel() { cancellation.cancel() }

    func removeSelected() {
        guard ready, !selection.isEmpty else { return }
        let updated = GRFBuildFile.removing(files, paths: selection)
        let count = files.count - updated.count
        guard count > 0 else { return }
        deletionUndo = (files, dirty); canUndoDelete = true
        files = updated; selection = []; dirty = true
        status = "Removed \(count.formatted()) resources from draft. Save a new GRF to apply."
    }

    func undoDelete() {
        guard let snapshot = deletionUndo else { return }
        files = snapshot.0; dirty = snapshot.1; selection = []
        deletionUndo = nil; canUndoDelete = false
        status = "Deletion undone. \(files.count.formatted()) files in draft."
    }

    func importSources(archives: Bool) {
        guard !busy, ready else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.value(archives ? "Merge GRF / GPF" : "Import Folders")
        panel.message = L10n.value(archives ? "Duplicate paths use the policy selected in the working copy." : "Choosing data imports data/… into the archive.")
        panel.canChooseDirectories = !archives; panel.canChooseFiles = archives; panel.allowsMultipleSelection = true
        if archives { panel.allowedContentTypes = ["grf", "gpf"].compactMap { UTType(filenameExtension: $0) } }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls, existing = files, selectedPolicy = policy, names = importEncoding
        cancellation = BuildCancellation(); let flag = cancellation
        busy = true; fraction = nil; status = "Reading selected sources…"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var combined = existing; var duplicates = 0; var imported = 0
                    for url in urls {
                        let added: [GRFBuildFile]
                        if archives {
                            let archive = try GRFArchive(url: url, encoding: names, cancelled: { flag.cancelled })
                            added = try GRFBuildFile.fromArchive(archive, cancelled: { flag.cancelled })
                        } else { added = try GRFBuildFile.importing(url, cancelled: { flag.cancelled }) }
                        let keys = Set(combined.map { $0.path.precomposedStringWithCanonicalMapping.lowercased() })
                        duplicates += added.filter { keys.contains($0.path.precomposedStringWithCanonicalMapping.lowercased()) }.count
                        imported += added.count
                        combined = try GRFBuildFile.merging(combined, with: added, policy: selectedPolicy)
                    }
                    if flag.cancelled { throw GRFBuildError.cancelled }
                    return (combined, imported, duplicates)
                }.value
                files = result.0; dirty = true; selection = []
                if archives { protectedSources.formUnion(urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }) }
                deletionUndo = nil; canUndoDelete = false
                status = "Read \(result.1.formatted()) resources; \(result.2.formatted()) duplicate paths (\(selectedPolicy.label)). Draft: \(files.count.formatted()) files."
            } catch is GRFBuildError { status = "Import cancelled. Draft unchanged." }
            catch { self.error = error.localizedDescription; status = "Import failed. Draft unchanged." }
            busy = false
        }
    }

    func save(protecting original: URL?, suggestedName: String, level: Int, completion: @escaping (URL, FilenameEncoding) -> Void) {
        guard !busy, ready else { return }
        let panel = NSSavePanel()
        panel.title = L10n.value("Save GRF Copy As")
        panel.allowedContentTypes = [UTType(filenameExtension: "grf") ?? .data]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        if protectedSources.contains(target) || original.map({ $0.resolvingSymlinksInPath().standardizedFileURL == target }) == true {
            error = "Choose a new filename. Source archives are protected."
            return
        }
        let staged = files; let selectedEncoding = encoding
        let replacingExisting = FileManager.default.fileExists(atPath: destination.path)
        cancellation = BuildCancellation(); let flag = cancellation
        operation = UUID(); let request = operation
        busy = true; fraction = 0; status = "Building GRF copy…"
        let report: @Sendable (GRFBuildProgress) -> Void = { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.busy, self.operation == request else { return }
                self.fraction = update.fraction; self.status = update.detail
            }
        }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try GRFBuilder.write(staged, to: destination, encoding: selectedEncoding, overwrite: replacingExisting,
                                         compressionLevel: level, progress: report, cancelled: { flag.cancelled })
                }.value
                busy = false; fraction = nil; dirty = false
                status = "Saved \(destination.lastPathComponent)."
                completion(destination, selectedEncoding)
            } catch is GRFBuildError {
                busy = false; fraction = nil; status = "Build cancelled. Draft kept; output unchanged."
            } catch {
                busy = false; fraction = nil; self.error = error.localizedDescription
                status = "Could not save. Draft kept; output unchanged. Replace or remove any unreadable resource before retrying."
            }
        }
    }
}

struct GRFBuilderView: View {
    let protectedArchive: URL?
    let source: GRFArchive?
    let mode: GRFBuilderMode
    let saved: (URL, FilenameEncoding) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GRFBuilderModel
    @State private var confirmDiscard = false
    @AppStorage(GRFPreferences.compressionKey) private var compressionLevel = -1

    init(protectedArchive: URL?, source: GRFArchive? = nil, sourceEncoding: FilenameEncoding = .korean,
         mode: GRFBuilderMode = .new, removing paths: Set<String> = [], saved: @escaping (URL, FilenameEncoding) -> Void) {
        self.protectedArchive = protectedArchive; self.source = source; self.mode = mode; self.saved = saved
        _model = StateObject(wrappedValue: GRFBuilderModel(source: source, encoding: sourceEncoding, removing: paths))
    }
    private var suggestedName: String {
        guard let source else { return "new.grf" }
        return source.url.deletingPathExtension().lastPathComponent + (mode == .repack ? "-repacked.grf" : "-edited.grf")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.value(mode.title)).font(.title2.bold())
                    Text(L10n.text("Edit a working copy, then save a new GRF 2.0. Source archives stay unchanged."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.text("\(model.files.count.formatted()) files")).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.text("Merge GRF…"), systemImage: "square.stack.3d.up") { model.importSources(archives: true) }
                Button(L10n.text("Import Folder…"), systemImage: "folder.badge.plus") { model.importSources(archives: false) }
                Spacer()
                Button(L10n.text("Delete Selected"), systemImage: "trash", action: model.removeSelected).disabled(model.selection.isEmpty)
                Button(L10n.text("Undo Delete"), action: model.undoDelete).disabled(!model.canUndoDelete)
            }.disabled(model.busy || !model.ready)
            HStack {
                Picker(L10n.text("Duplicate Paths"), selection: $model.policy) {
                    ForEach(GRFMergePolicy.allCases, id: \.self) { Text(L10n.value($0.label)).tag($0) }
                }
                Picker(L10n.text("Import GRF Names"), selection: $model.importEncoding) {
                    ForEach(FilenameEncoding.allCases, id: \.self) { Text(L10n.value($0.label)).tag($0) }
                }
            }.disabled(model.busy)
            HStack {
                Picker(L10n.text("Output Filenames"), selection: $model.encoding) {
                    ForEach(FilenameEncoding.allCases, id: \.self) { Text(L10n.value($0.label)).tag($0) }
                }
                Spacer()
                Text(L10n.text("Compression: \(GRFPreferences.label(compressionLevel))")).font(.caption).foregroundStyle(.secondary)
                SettingsLink { Image(systemName: "gearshape") }.help(L10n.text("Compression settings"))
            }.disabled(model.busy)
            List(selection: $model.selection) {
                ForEach(model.files) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc").frame(width: 22, height: 20).foregroundStyle(.secondary)
                        Text(L10n.value(file.path)).lineLimit(1).truncationMode(.middle).help(L10n.value(file.source.path))
                        Spacer()
                        Text(L10n.value(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))).font(.caption).foregroundStyle(.secondary)
                    }.tag(file.path)
                }
            }.disabled(model.busy || !model.ready)
            .overlay {
                if model.files.isEmpty && !model.busy {
                    ContentUnavailableView(L10n.text("No Resources"), systemImage: "archivebox", description: Text(L10n.text("Import folders or GRFs, or save an empty archive.")))
                }
            }
            HStack {
                if model.busy {
                    if let fraction = model.fraction { ProgressView(value: fraction).frame(width: 120) }
                    else { ProgressView().controlSize(.small) }
                }
                Text(L10n.value(model.status)).font(.caption).lineLimit(2).help(L10n.value(model.status))
                Spacer()
                if model.busy { Button(L10n.text("Cancel Operation"), action: model.cancel) }
            }.frame(minHeight: 30)
            HStack {
                Button(L10n.text("Close")) {
                    if model.dirty { confirmDiscard = true } else { dismiss() }
                }.disabled(model.busy).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.value(mode == .repack ? "Repack As…" : "Save GRF As…")) {
                    model.save(protecting: protectedArchive, suggestedName: suggestedName, level: compressionLevel) { url, encoding in
                        dismiss(); saved(url, encoding)
                    }
                }.buttonStyle(.borderedProminent).disabled(model.busy || !model.ready)
            }
        }.padding(20).frame(width: 900, height: 620)
        .interactiveDismissDisabled(model.dirty || model.busy)
        .alert(L10n.text("Could Not Complete Operation"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L10n.text("OK"), role: .cancel) { model.error = nil }
        } message: { Text(L10n.value(model.error ?? "")) }
        .confirmationDialog("Discard unsaved changes? Source archives and files will be kept.", isPresented: $confirmDiscard) {
            Button(L10n.text("Discard Draft"), role: .destructive) { dismiss() }
            Button(L10n.text("Keep Draft"), role: .cancel) {}
        }
    }
}
