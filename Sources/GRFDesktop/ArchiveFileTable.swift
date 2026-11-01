import AppKit
import SwiftUI
import GRFCore

/// An indexed, reusable-cell table so selecting a file never rebuilds the archive list.
public struct ArchiveFileTable: NSViewRepresentable {
    public let entries: [GRFEntry]
    public let revision: UUID
    @Binding public var selection: Set<Int>
    public let sortChanged: (String, Bool) -> Void
    public let icon: (String) -> String
    public let busy: Bool
    public let extractAs: () -> Void
    public let extractSelected: () -> Void
    public let copyPaths: () -> Void
    public let resourceStatus: (Int) -> String
    public let canEdit: Bool
    public let replace: () -> Void
    public let rename: () -> Void
    public let delete: () -> Void

    public init(entries: [GRFEntry], revision: UUID, selection: Binding<Set<Int>>,
                sortChanged: @escaping (String, Bool) -> Void, icon: @escaping (String) -> String,
                busy: Bool, extractAs: @escaping () -> Void, extractSelected: @escaping () -> Void, copyPaths: @escaping () -> Void,
                resourceStatus: @escaping (Int) -> String = { _ in "" }, canEdit: Bool = false,
                replace: @escaping () -> Void = {}, rename: @escaping () -> Void = {}, delete: @escaping () -> Void = {}) {
        self.entries = entries; self.revision = revision; self._selection = selection
        self.sortChanged = sortChanged; self.icon = icon
        self.busy = busy; self.extractAs = extractAs; self.extractSelected = extractSelected; self.copyPaths = copyPaths
        self.resourceStatus = resourceStatus; self.canEdit = canEdit; self.replace = replace; self.rename = rename; self.delete = delete
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = ArchiveTableScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let table = ArchiveNativeTable()
        table.autoresizingMask = [.width]
        let menu = NSMenu()
        for (title, action) in [("Extract File As…", #selector(Coordinator.extractAs)),
                                 ("Extract Selected…", #selector(Coordinator.extractSelected)),
                                 ("Copy Paths", #selector(Coordinator.copyPaths)),
                                 ("Replace…", #selector(Coordinator.replace)),
                                 ("Rename…", #selector(Coordinator.rename)),
                                 ("Delete", #selector(Coordinator.delete))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = context.coordinator
            menu.addItem(item)
        }
        table.menu = menu
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        for (key, title, width) in [("name", "Name", 300.0), ("size", "Size", 85.0), ("packed", "Packed", 85.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title; column.width = width
            column.minWidth = key == "name" ? 180 : 85
            column.resizingMask = key == "name" ? [.autoresizingMask, .userResizingMask] : []
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    public func updateNSView(_ view: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.table?.isEnabled != context.environment.isEnabled {
            coordinator.table?.isEnabled = context.environment.isEnabled
        }
        coordinator.update()
    }
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 470,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 400)
    }

    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
        var parent: ArchiveFileTable
        weak var table: NSTableView?
        private var revision: UUID?
        private var rows: [GRFEntry] = []
        private var indexByID: [Int: Int] = [:]
        private var synchronizing = false
        init(_ parent: ArchiveFileTable) { self.parent = parent }

        func update() {
            guard let table else { return }
            synchronizing = true
            defer { synchronizing = false }
            if revision != parent.revision {
                rows = parent.entries
                indexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
                revision = parent.revision
                table.reloadData()
                if let scroll = table.enclosingScrollView {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            let selected = IndexSet(parent.selection.compactMap { indexByID[$0] })
            if table.selectedRowIndexes != selected { table.selectRowIndexes(selected, byExtendingSelection: false) }
        }
        @objc func extractAs() { parent.extractAs() }
        @objc func extractSelected() { parent.extractSelected() }
        @objc func copyPaths() { parent.copyPaths() }
        @objc func replace() { parent.replace() }
        @objc func rename() { parent.rename() }
        @objc func delete() { parent.delete() }
        public func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(replace) || item.action == #selector(rename) { return parent.canEdit && !parent.busy && parent.selection.count == 1 }
            if item.action == #selector(delete) { return parent.canEdit && !parent.busy && !parent.selection.isEmpty }
            if item.action == #selector(copyPaths) { return !parent.selection.isEmpty }
            if item.action == #selector(extractAs) { return !parent.busy && parent.selection.count == 1 }
            return !parent.busy && !parent.selection.isEmpty
        }
        public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row), let column = tableColumn else { return nil }
            let entry = rows[row]
            if column.identifier.rawValue == "name" {
                let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? FileIconCell) ?? FileIconCell(identifier: column.identifier)
                let status = parent.resourceStatus(entry.id)
                cell.label.stringValue = entry.name + (status.isEmpty ? "" : "  · " + status)
                cell.label.textColor = status == "Deleted" ? .tertiaryLabelColor : .labelColor
                cell.symbol.image = NSImage(systemSymbolName: parent.icon(entry.path), accessibilityDescription: nil)
                cell.toolTip = entry.path
                return cell
            }
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView { cell = existing }
            else {
                cell = NSTableCellView()
                cell.identifier = column.identifier
                let label = NSTextField(labelWithString: "")
                label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                label.textColor = .secondaryLabelColor
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label); cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            let bytes = column.identifier.rawValue == "size" ? entry.size : entry.compressedSize
            cell.textField?.stringValue = column.identifier.rawValue == "packed" && bytes == 0 && entry.size > 0 ? "—" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return cell
        }
        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let table else { return }
            let selected = Set(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
            if selected != parent.selection { parent.selection = selected }
        }
        public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !synchronizing, let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            parent.sortChanged(key, descriptor.ascending)
        }
    }
}

private final class FileIconCell: NSTableCellView {
    let symbol = NSImageView()
    let label = NSTextField(labelWithString: "")
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        symbol.imageScaling = .scaleProportionallyDown; symbol.imageAlignment = .alignCenter
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        symbol.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol); addSubview(label)
        imageView = symbol; textField = label
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 22),
            symbol.heightAnchor.constraint(equalToConstant: 20),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { return nil }
}

private final class ArchiveNativeTable: NSTableView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let clicked = row(at: convert(event.locationInWindow, from: nil))
        if clicked >= 0 && !selectedRowIndexes.contains(clicked) {
            selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

/// Keep all three columns inside the file pane when the preview changes width.
private final class ArchiveTableScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, let name = table.tableColumns.first else { return }
        let width = contentView.bounds.width
        guard width >= 350 else { return }
        let nameWidth = max(180, width - 184)
        if abs(name.width - nameWidth) > 0.5 { name.width = nameWidth }
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if contentView.bounds.minX != 0 { contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.minY)); reflectScrolledClipView(contentView) }
    }
}
