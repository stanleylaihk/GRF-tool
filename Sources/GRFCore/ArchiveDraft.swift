import Foundation

public struct DraftResource: Identifiable, Sendable {
    public let id: Int
    public var file: GRFBuildFile
    public var deleted = false
    public var replaced = false
    public let originalPath: String?
    public var status: String {
        if deleted { return "Deleted" }
        if originalPath == nil { return "Added" }
        var labels: [String] = []
        if replaced { labels.append("Replaced") }
        if originalPath != file.path { labels.append("Renamed") }
        return labels.joined(separator: " · ")
    }
}

/// Stable resource identities allow a rename, replacement and deletion to share
/// one pending item. Reverting an item restores its complete original resource.
public struct ArchiveDraft: Sendable {
    private let base: [Int: DraftResource]
    private var overrides: [Int: DraftResource] = [:]
    private var history: [[Int: DraftResource]] = []
    private var names: [String: Set<Int>]
    private var nextID: Int
    public init(files: [GRFBuildFile]) {
        base = Dictionary(uniqueKeysWithValues: files.enumerated().map { ($0.offset, DraftResource(id: $0.offset, file: $0.element, originalPath: $0.element.path)) })
        names = Dictionary(files.enumerated().map { ($0.element.path.precomposedStringWithCanonicalMapping.lowercased(), Set([$0.offset])) }, uniquingKeysWith: { $0.union($1) })
        nextID = files.count
    }
    public var resources: [DraftResource] {
        let original = base.map { overrides[$0.key] ?? $0.value }
        let added = overrides.values.filter { $0.originalPath == nil && !$0.deleted }
        return (original + added).sorted { $0.id < $1.id }
    }
    public var changes: [DraftResource] { overrides.values.filter { !$0.status.isEmpty && !($0.deleted && $0.originalPath == nil) }.sorted { $0.file.path < $1.file.path } }
    public var files: [GRFBuildFile] { resources.filter { !$0.deleted }.map(\.file) }
    public var canUndo: Bool { !history.isEmpty }
    public func resource(_ id: Int) -> DraftResource? { overrides[id] ?? base[id] }
    private func key(_ path: String) -> String { path.precomposedStringWithCanonicalMapping.lowercased() }
    private func requireAvailable(_ path: String, except id: Int? = nil) throws {
        guard (names[key(path)] ?? []).subtracting(id.map { [$0] } ?? []).isEmpty else { throw GRFError.invalid("A resource already exists at \(path). Use Replace instead.") }
    }
    public mutating func add(_ files: [GRFBuildFile]) throws {
        var trial = self
        var before: [Int: DraftResource] = [:]
        for file in files {
            try trial.requireAvailable(file.path)
            let item = DraftResource(id: trial.nextID, file: file, originalPath: nil)
            var tombstone = item; tombstone.deleted = true; before[item.id] = tombstone
            trial.overrides[item.id] = item; trial.names[trial.key(file.path), default: []].insert(item.id); trial.nextID += 1
        }
        if !before.isEmpty { trial.history.append(before) }
        self = trial
    }
    public mutating func rename(_ id: Int, to path: String) throws {
        guard var item = resource(id), !item.deleted else { return }
        try requireAvailable(path, except: id)
        let file = try item.file.renamed(to: path)
        guard file.path != item.file.path else { return }
        history.append([id: item]); names[key(item.file.path)]?.remove(id); item.file = file; overrides[id] = item; names[key(file.path), default: []].insert(id)
    }
    public mutating func replace(_ id: Int, with file: GRFBuildFile) throws {
        guard var item = resource(id), !item.deleted else { return }
        let file = try file.renamed(to: item.file.path)
        history.append([id: item]); item.file = file; item.replaced = true; overrides[id] = item
    }
    public mutating func delete(_ ids: Set<Int>) {
        var before: [Int: DraftResource] = [:]
        for id in ids {
            guard var item = resource(id), !item.deleted else { continue }
            before[id] = item; names[key(item.file.path)]?.remove(id); item.deleted = true; overrides[id] = item
        }
        if !before.isEmpty { history.append(before) }
    }
    public mutating func undoLast() {
        guard let before = history.popLast() else { return }
        for id in before.keys { if let current = resource(id), !current.deleted { names[key(current.file.path)]?.remove(id) } }
        for (id, item) in before { overrides[id] = item; if !item.deleted { names[key(item.file.path), default: []].insert(id) } }
    }
    public mutating func revert(_ id: Int) throws {
        if let original = base[id] {
            try requireAvailable(original.file.path, except: id)
            if let current = resource(id), !current.deleted { names[key(current.file.path)]?.remove(id) }
            overrides[id] = original; names[key(original.file.path), default: []].insert(id)
        }
        else if var item = overrides[id] { names[key(item.file.path)]?.remove(id); item.deleted = true; overrides[id] = item }
        history = history.map { $0.filter { $0.key != id } }.filter { !$0.isEmpty }
    }
    public mutating func revertAll() { overrides = [:]; history = []; names = Dictionary(base.map { (key($0.value.file.path), Set([$0.key])) }, uniquingKeysWith: { $0.union($1) }) }
}
