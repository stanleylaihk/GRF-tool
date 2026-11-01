import AppKit
import Foundation
import UniformTypeIdentifiers
import GRFCore
import GRFDesktop

@MainActor
extension ArchiveModel {
    func resourceFile(_ id: Int) -> GRFBuildFile? { browsingLocal ? localFiles[id] : draft?.resource(id)?.file }
    func refreshWorkspace() {
        if !browsingLocal {
            draftEntries = draft?.resources.map { item in
                GRFEntry.listing(id: item.id, path: item.file.path, size: Int(item.file.size), compressedSize: item.file.compressedSize)
            } ?? []
        }
        entryLookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        folders = ArchiveFolder.tree(filePaths: entries.map(\.path))
        paletteEntries = entries.filter { $0.path.lowercased().hasSuffix(".pal") }
        workspaceRevision = UUID()
        stopContentSearch(); submittedQuery = ""; searchHits = []
        updateVisibleEntries()
    }
    func confirmLeavingDraft() -> Bool {
        guard pendingCount > 0 else { return true }
        let alert = NSAlert(); alert.messageText = "Keep your unsaved changes?"
        alert.informativeText = "Save a GRF copy before opening another archive, or discard the pending changes. Your source file is unchanged."
        alert.addButton(withTitle: "Keep Working"); alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func switchSource(local: Bool) {
        guard !busy, browsingLocal != local else { return }
        browsingLocal = local; selection = []; folder = ""; search = ""; clearPreview(); refreshWorkspace(); status = "\(sourceLabel) · \(entries.count) resources"
    }
    func browseLocalFile(_ url: URL) {
        guard !busy else { return }
        busy = true
        let directory = url.deletingLastPathComponent()
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    var result: [Int: GRFBuildFile] = [:]
                    for item in urls {
                        if let file = try? GRFBuildFile.importingFile(item) { result[result.count] = file }
                    }
                    return result
                }.value
                localDirectory = directory; localFiles = files; browsingLocal = true
                folder = ""; search = ""; clearPreview(); refreshWorkspace()
                if let id = files.first(where: { $0.value.source.standardizedFileURL == url.standardizedFileURL })?.key { selection = [id] }
                else { throw GRFError.invalid("The selected resource could not be read.") }
                showPreview = true; status = "Local folder · \(files.count) files"
            } catch { self.error = error.localizedDescription }
            busy = false
            loadPreview()
        }
    }
    func statusForEntry(_ id: Int) -> String { browsingLocal ? "" : draft?.resource(id)?.status ?? "" }
    func addResources(folderOnly: Bool = false) {
        guard !busy, !browsingLocal, draft != nil else { return }
        let panel = NSOpenPanel(); panel.title = folderOnly ? "Import Folder" : "Add Resources"
        panel.canChooseFiles = !folderOnly; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls, prefix = folder
        busy = true
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try urls.flatMap { url -> [GRFBuildFile] in
                        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { return try GRFBuildFile.importing(url) }
                        return [try GRFBuildFile.importingFile(url, path: prefix.isEmpty ? url.lastPathComponent : prefix + "/" + url.lastPathComponent)]
                    }
                }.value
                try draft?.add(files); showChanges = true; refreshWorkspace(); status = "\(files.count) resources added to pending changes."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func mergeResources() {
        guard !busy, !browsingLocal, draft != nil else { return }
        let panel = NSOpenPanel(); panel.title = "Merge GRF"; panel.allowedContentTypes = ["grf", "gpf"].compactMap { UTType(filenameExtension: $0) }; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls, names = encoding
        busy = true
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try urls.flatMap { try GRFBuildFile.fromArchive(GRFArchive(url: $0, encoding: names)) }
                }.value
                let existing = Dictionary((draft?.resources.filter { !$0.deleted } ?? []).map { ($0.file.path.precomposedStringWithCanonicalMapping.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
                let duplicates = files.filter { existing[$0.path.precomposedStringWithCanonicalMapping.lowercased()] != nil }.count
                var replacing = false
                if duplicates > 0 {
                    let alert = NSAlert(); alert.messageText = "\(duplicates) duplicate paths"
                    alert.informativeText = "Choose how to merge these resources into the pending draft."
                    alert.addButton(withTitle: "Keep Existing"); alert.addButton(withTitle: "Replace Existing"); alert.addButton(withTitle: "Cancel")
                    let response = alert.runModal()
                    if response == .alertThirdButtonReturn { busy = false; return }
                    replacing = response == .alertSecondButtonReturn
                }
                var trial = draft!, added: [GRFBuildFile] = []
                for file in files {
                    if let id = existing[file.path.precomposedStringWithCanonicalMapping.lowercased()] {
                        if replacing { try trial.replace(id, with: file) }
                    } else { added.append(file) }
                }
                try trial.add(added); protectedSourceURLs.formUnion(urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }); draft = trial; showChanges = true; refreshWorkspace(); loadPreview()
                status = "Merged resources into pending changes."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func replaceSelected() {
        guard !busy, !browsingLocal, let id = currentEntry?.id else { return }
        let panel = NSOpenPanel(); panel.title = "Replace Resource"; panel.message = "The archive path stays the same. Preview updates immediately; save a new GRF to publish."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try draft?.replace(id, with: GRFBuildFile.importingFile(url)); changedWorkspace() }
        catch { self.error = error.localizedDescription }
    }
    func renameSelected() {
        guard !busy, !browsingLocal, let entry = currentEntry else { return }
        let alert = NSAlert(); alert.messageText = "Rename Resource"
        alert.informativeText = "Enter the full archive path. References inside other files are not rewritten."
        let field = NSTextField(string: entry.path); field.frame = NSRect(x: 0, y: 0, width: 420, height: 26)
        alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try draft?.rename(entry.id, to: field.stringValue); changedWorkspace() }
        catch { self.error = error.localizedDescription }
    }
    func deleteSelected() {
        guard !busy, !browsingLocal else { return }
        draft?.delete(selection); changedWorkspace()
    }
    func changedWorkspace() { showChanges = true; refreshWorkspace(); loadPreview(); status = "\(pendingCount) pending changes · Save a new GRF to apply." }
    func undoLastChange() { guard !busy else { return }; draft?.undoLast(); changedWorkspace() }
    func revertChange(_ id: Int) { guard !busy else { return }; do { try draft?.revert(id); changedWorkspace() } catch { self.error = error.localizedDescription } }
    func revertAllChanges() { guard !busy else { return }; draft?.revertAll(); changedWorkspace() }
    func saveWorkspace() {
        guard !busy, !browsingLocal, let draft else { return }
        let panel = NSSavePanel(); panel.title = "Save GRF Copy As"; panel.allowedContentTypes = [UTType(filenameExtension: "grf") ?? .data]
        panel.nameFieldStringValue = (archive?.url.deletingPathExtension().lastPathComponent ?? "new") + "-edited.grf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if protectedSourceURLs.contains(url.resolvingSymlinksInPath().standardizedFileURL) {
            error = "Choose a new filename to preserve the source GRF."; return
        }
        let files = draft.files, names = encoding
        let level = UserDefaults.standard.object(forKey: GRFPreferences.compressionKey) as? Int ?? -1
        let overwrite = FileManager.default.fileExists(atPath: url.path)
        cancellation = CancellationFlag(); let flag = cancellation
        busy = true; loadingFraction = 0; loadingLocation = url.path
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try GRFBuilder.write(files, to: url, encoding: names, overwrite: overwrite, compressionLevel: level, progress: { progress in
                        Task { @MainActor in self.loadingFraction = progress.fraction; self.status = progress.detail }
                    }, cancelled: { flag.isCancelled })
                }.value
                busy = false; loadingFraction = nil; self.draft?.revertAll(); open(url)
            } catch { busy = false; loadingFraction = nil; self.error = error.localizedDescription }
        }
    }
    func extractWorkspace(all: Bool) {
        guard !busy else { return }
        let ids = all ? entries.map(\.id) : Array(selection)
        let files = ids.compactMap { id -> GRFBuildFile? in
            if !browsingLocal, draft?.resource(id)?.deleted == true { return nil }
            return resourceFile(id)
        }
        guard !files.isEmpty else { return }
        let panel = NSOpenPanel(); panel.title = "Choose Extraction Folder"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        cancellation = CancellationFlag(); let flag = cancellation
        busy = true; extracting = true; completed = 0; total = files.count
        Task {
            do {
                let failures = try await Task.detached(priority: .userInitiated) {
                    var failures: [String] = []
                    for (i, file) in files.enumerated() {
                        if flag.isCancelled { throw GRFError.cancelled }
                        do { try DraftExtraction.write(file, to: destination, cancelled: { flag.isCancelled }) }
                        catch { if flag.isCancelled { throw error }; failures.append("\(file.path): \(error.localizedDescription)") }
                        Task { @MainActor in self.completed = i + 1 }
                    }
                    return failures
                }.value
                status = "Extracted \(files.count - failures.count) of \(files.count) resources."
                if !failures.isEmpty { extractionNotice = failures.prefix(30).joined(separator: "\n") }
            } catch { self.error = error.localizedDescription }
            busy = false; extracting = false
        }
    }
    func stopContentSearch() { searchCancellation.cancel(); searchID = UUID(); searchRunning = false }
    func runContentSearch() {
        guard searchScope != "Filename", !busy else { return }
        stopContentSearch()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        submittedQuery = query; searchHits = []; searchFailures = []; hitOccurrence = 0
        guard !query.isEmpty else { updateVisibleEntries(); return }
        let files = entries.compactMap { entry -> (GRFEntry, GRFBuildFile)? in
            guard ResourceSearch.textExtensions.contains((entry.path as NSString).pathExtension.lowercased()), let file = resourceFile(entry.id) else { return nil }
            if !browsingLocal, draft?.resource(entry.id)?.deleted == true { return nil }
            return (entry, file)
        }
        searchCancellation = CancellationFlag(); let flag = searchCancellation, request = UUID(); searchID = request
        searchRunning = true; searchProgress = 0
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var hits: [ContentSearchHit] = [], failures: [String] = []
                for (i, pair) in files.enumerated() {
                    if flag.isCancelled { break }
                    do {
                        let data = try pair.1.data(limit: 16 * 1024 * 1024)
                        if let hit = try ResourceSearch.hit(data, resourceID: pair.0.id, path: pair.0.path, query: query) { hits.append(hit) }
                    } catch { failures.append("\(pair.0.path): \(error.localizedDescription)") }
                    if i % 20 == 0 || i + 1 == files.count {
                        let current = hits, skipped = failures
                        Task { @MainActor in
                            guard self.searchID == request else { return }
                            self.searchProgress = Double(i+1) / Double(max(1, files.count)); self.searchHits = current; self.searchFailures = skipped; self.updateVisibleEntries()
                        }
                    }
                }
                return (hits, failures)
            }.value
            guard searchID == request else { return }
            searchHits = result.0; searchFailures = result.1; searchRunning = false; searchProgress = 1; updateVisibleEntries()
            status = "\(searchHits.count) content matches · \(searchFailures.count) skipped files"
        }
    }
    nonisolated static func resourceRoot(_ directory: URL?) -> URL? {
        guard var directory else { return nil }
        let original = directory
        for _ in 0..<8 {
            if directory.lastPathComponent.lowercased() == "data" { return directory.deletingLastPathComponent() }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }; directory = parent
        }
        return original
    }
    nonisolated static func looksLikeText(_ bytes: Data) -> Bool {
        let sample = bytes.prefix(4096)
        return !sample.isEmpty && !sample.contains(0) && sample.filter { $0 < 9 || (14...31).contains($0) }.count < max(1, sample.count / 100) && (try? TextPreviewDecoder.preview(Data(sample))) != nil
    }
}
