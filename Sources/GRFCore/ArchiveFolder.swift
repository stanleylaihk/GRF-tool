import Foundation

/// Folder identity is the complete archive path; labels only show the local name.
public struct ArchiveFolder: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let children: [ArchiveFolder]?

    public static func tree(filePaths: [String]) -> [ArchiveFolder] {
        let root = FolderBuilder(name: "", path: "")
        for path in filePaths {
            var parent = root
            for component in path.split(separator: "/").dropLast() {
                let name = String(component)
                if let child = parent.children[name] { parent = child }
                else {
                    let child = FolderBuilder(name: name, path: parent.path.isEmpty ? name : parent.path + "/" + name)
                    parent.children[name] = child
                    parent = child
                }
            }
        }
        return root.nodes()
    }
}

private final class FolderBuilder {
    let name: String
    let path: String
    var children: [String: FolderBuilder] = [:]
    init(name: String, path: String) { self.name = name; self.path = path }
    func nodes() -> [ArchiveFolder] {
        children.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map {
            let descendants = $0.nodes()
            return ArchiveFolder(name: $0.name, path: $0.path, children: descendants.isEmpty ? nil : descendants)
        }
    }
}
