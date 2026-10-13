// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
protocol DirectoryTableOwner: AnyObject {
    func directoryTableSelectionDidChange(_ controller: DirectoryTableController)
    func directoryTableDidFocus(_ controller: DirectoryTableController)
    func directoryTable(_ controller: DirectoryTableController, handleKey event: NSEvent) -> Bool
    func directoryTableActivate(_ controller: DirectoryTableController)
    func directoryTableMenu(_ controller: DirectoryTableController) -> NSMenu?
    func directoryTableDidLoad(_ controller: DirectoryTableController)
    func directoryTableVanished(_ controller: DirectoryTableController)
    var window: NSWindow? { get }
}

enum DirectoryTableStyle {
    case column, list
}

/// One directory shown as a table: the Columns view uses one per column and
/// the List view uses one with sortable headers.
@MainActor
final class DirectoryTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, FileTableViewDelegate {
    let model: DirectoryModel
    let style: DirectoryTableStyle
    let table = FileTableView()
    let view = ThemedView(fill: \.background)
    weak var owner: DirectoryTableOwner?

    private let scrollView = NSScrollView()
    private let header = ThemedView(fill: \.background)
    private let headerTitle = NSTextField.themedLabel(color: \.text, scale: 0.92, weight: .semibold)
    private let headerRule = ThemedView(fill: \.border)
    private let emptyLabel = NSTextField.themedLabel(color: \.dimText, scale: 0.92)
    private var pendingSelection: [URL]?
    private var rename: InlineRename?
    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    private static let nameColumn = NSUserInterfaceItemIdentifier("name")
    private static let sizeColumn = NSUserInterfaceItemIdentifier("size")
    private static let kindColumn = NSUserInterfaceItemIdentifier("kind")
    private static let modifiedColumn = NSUserInterfaceItemIdentifier("modified")

    init(url: URL, style: DirectoryTableStyle) {
        model = DirectoryModel(url: url)
        self.style = style
        super.init()
        buildView()
        model.onChange = { [weak self] in self?.modelDidChange() }
        model.onVanish = { [weak self] in
            guard let self else { return }
            owner?.directoryTableVanished(self)
        }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: Appearance.didChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.appearanceDidChange() }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: Preferences.didChange, object: nil, queue: .main
            ) { [weak self] note in
                let key = note.userInfo?["key"] as? String
                MainActor.assumeIsolated {
                    if key == Preferences.Key.sortKey || key == Preferences.Key.sortAscending {
                        self?.syncSortIndicator()
                    }
                }
            })
        model.load()
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var url: URL { model.url }

    var selectedEntries: [FileEntry] {
        table.selectedRowIndexes.compactMap { model.entries.indices.contains($0) ? model.entries[$0] : nil }
    }

    var cursorEntry: FileEntry? {
        let row = table.cursorRow
        return model.entries.indices.contains(row) ? model.entries[row] : nil
    }

    /// Selects `urls` now, or once they appear after loading.
    func select(_ urls: [URL], scroll: Bool = true) {
        let urls = urls.map(\.canonical)
        let rows = IndexSet(urls.compactMap(model.index(of:)))
        if model.state == .loading || rows.count < urls.count {
            pendingSelection = urls
        }
        guard !rows.isEmpty || urls.isEmpty else { return }
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if scroll, let first = rows.first { table.scrollRowToVisible(first) }
    }

    func focus(selectingFirstIfEmpty: Bool = true) {
        table.window?.makeFirstResponder(table)
        if selectingFirstIfEmpty, table.selectedRowIndexes.isEmpty, table.numberOfRows > 0 {
            table.moveCursor(to: 0)
        }
    }

    /// Marks this table as the destination for paste and new items.
    func setActive(_ active: Bool) {
        isActive = active
        headerRule.fillColor = active ? \.accent : \.border
    }

    func beginRename(_ url: URL, window: NSWindow?) {
        guard let row = model.index(of: url) else {
            pendingRename = url
            return
        }
        table.scrollRowToVisible(row)
        table.selectRowIndexes([row], byExtendingSelection: false)
        guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileCellView else { return }
        let entry = model.entries[row]
        rename = InlineRename(
            field: cell.nameField, entry: entry,
            commit: { [weak self] name in
                guard let self else { return }
                if let renamed = FileOperationCenter.shared.rename(entry.url, to: name, window: window) {
                    self.select([renamed])
                }
            },
            finish: { [weak self] restoreFocus in
                guard let self else { return }
                self.rename = nil
                if restoreFocus { self.table.window?.makeFirstResponder(self.table) }
                if self.reloadAfterRename { self.modelDidChange() }
            })
    }

    private var pendingRename: URL?
    /// A reload arrived while a name was being edited; it waits so the edit survives.
    private var reloadAfterRename = false

    var isRenaming: Bool { rename != nil }

    // MARK: Layout

    private func buildView() {
        table.fileDelegate = self
        table.dataSource = self
        table.delegate = self
        table.rowHeight = Appearance.shared.rowHeight
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 4
        emptyLabel.lineBreakMode = .byWordWrapping
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)

        switch style {
        case .column:
            table.headerView = nil
            let column = NSTableColumn(identifier: Self.nameColumn)
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            buildColumnHeader()
        case .list:
            buildListColumns()
            NSLayoutConstraint.activate([scrollView.topAnchor.constraint(equalTo: view.topAnchor)])
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -24),
        ])
    }

    private func buildColumnHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerRule.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.lineBreakMode = .byTruncatingMiddle
        headerTitle.stringValue = Self.displayName(url)
        header.addSubview(headerTitle)
        header.addSubview(headerRule)
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 30),
            headerTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -12),
            headerTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerRule.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerRule.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerRule.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerRule.heightAnchor.constraint(equalToConstant: 1),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
        ])
    }

    private func buildListColumns() {
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat, SortKey)] = [
            (Self.nameColumn, tr("Name"), 320, .name),
            (Self.sizeColumn, tr("Size"), 90, .size),
            (Self.kindColumn, tr("Type"), 150, .kind),
            (Self.modifiedColumn, tr("Modified"), 170, .modified),
        ]
        for (identifier, title, width, key) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: true)
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.headerView = NSTableHeaderView()
        scrollView.hasHorizontalScroller = true
        syncSortIndicator()
    }

    private func syncSortIndicator() {
        guard style == .list else { return }
        let order = Preferences.shared.sortOrder
        table.sortDescriptors = [NSSortDescriptor(key: order.key.rawValue, ascending: order.ascending)]
    }

    private func appearanceDidChange() {
        table.rowHeight = Appearance.shared.rowHeight
        table.reloadData()
    }

    static func displayName(_ url: URL) -> String {
        url.path == "/" ? (FileManager.default.displayName(atPath: "/")) : url.lastPathComponent
    }

    // MARK: Model

    private func modelDidChange() {
        reloadAfterRename = isRenaming
        if isRenaming { return }
        let selected = pendingSelection ?? selectedEntries.map(\.url)
        let hadFocus = table.isFirstResponder
        table.reloadData()
        let rows = IndexSet(selected.compactMap(model.index(of:)))
        if !rows.isEmpty {
            table.selectRowIndexes(rows, byExtendingSelection: false)
            if pendingSelection != nil, let first = rows.first { table.scrollRowToVisible(first) }
            if rows.count == selected.count { pendingSelection = nil }
        }
        if model.state != .loading, pendingSelection != nil, rows.isEmpty {
            pendingSelection = nil
        }
        if hadFocus, table.selectedRowIndexes.isEmpty, table.numberOfRows > 0, !model.isFiltering {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
        updateEmptyLabel()
        owner?.directoryTableDidLoad(self)
        if let pendingRename, model.index(of: pendingRename) != nil {
            self.pendingRename = nil
            beginRename(pendingRename, window: owner?.window)
        }
    }

    private func updateEmptyLabel() {
        switch model.state {
        case .loading:
            emptyLabel.stringValue = ""
        case let .failed(message):
            emptyLabel.stringValue = message
        case .loaded:
            emptyLabel.stringValue =
                model.entries.isEmpty
                ? (model.isFiltering ? tr("No results") : tr("This folder is empty"))
                : ""
        }
        emptyLabel.isHidden = emptyLabel.stringValue.isEmpty
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.entries.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        FileRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = model.entries[row]
        let identifier = tableColumn?.identifier ?? Self.nameColumn
        if identifier == Self.nameColumn {
            let cell =
                tableView.makeView(withIdentifier: identifier, owner: nil) as? FileCellView
                ?? FileCellView()
            cell.identifier = identifier
            let detail: String? =
                if model.isNested(entry) {
                    Self.relativeParent(of: entry.url, below: url)
                } else if style == .column, !entry.isFolder, let size = entry.size {
                    Formatters.size(size)
                } else {
                    nil
                }
            cell.configure(entry, detail: detail, showsChevron: style == .column)
            return cell
        }
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = identifier
        cell.font = Appearance.shared.font(scale: 0.92)
        cell.textColor = Appearance.shared.palette.dimText
        cell.lineBreakMode = .byTruncatingTail
        cell.stringValue =
            switch identifier {
            case Self.sizeColumn: entry.size.map(Formatters.size) ?? "—"
            case Self.kindColumn: entry.kindDescription ?? ""
            default: entry.modified.map(Formatters.date) ?? ""
            }
        return cell
    }

    static func relativeParent(of url: URL, below root: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        return parent.dropFirst(base.count).joined(separator: "/")
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
            let key = descriptor.key.flatMap(SortKey.init)
        else { return }
        let order = StrataCore.SortOrder(key: key, ascending: descriptor.ascending)
        if order != Preferences.shared.sortOrder {
            Preferences.shared.sortOrder = order
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if !table.selectedRowIndexes.isEmpty, model.state != .loading { pendingSelection = nil }
        owner?.directoryTableSelectionDidChange(self)
    }

    // MARK: Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard !isRenaming else { return nil }
        return model.entries[row].url as NSURL
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        var destination = url
        if model.entries.indices.contains(row), dropOperation == .on, model.entries[row].isFolder {
            destination = model.entries[row].url
        } else {
            tableView.setDropRow(-1, dropOperation: .on)
        }
        return DropTarget.operation(for: info, destination: destination)
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let destination =
            model.entries.indices.contains(row) && model.entries[row].isFolder ? model.entries[row].url : url
        return DropTarget.accept(info, destination: destination, window: tableView.window)
    }

    // MARK: FileTableViewDelegate

    func fileTable(_ table: FileTableView, handleKey event: NSEvent) -> Bool {
        owner?.directoryTable(self, handleKey: event) ?? false
    }

    func fileTableMenu(_ table: FileTableView) -> NSMenu? {
        owner?.directoryTableMenu(self)
    }

    func fileTableDidBecomeFirstResponder(_ table: FileTableView) {
        owner?.directoryTableDidFocus(self)
    }

    func fileTableActivate(_ table: FileTableView) {
        owner?.directoryTableActivate(self)
    }
}

/// Finder drop semantics: Option copies, Command moves, otherwise items move
/// within a volume and copy across volumes.
@MainActor
enum DropTarget {
    static func operation(for info: NSDraggingInfo, destination: URL) -> NSDragOperation {
        let sources = urls(info)
        guard !sources.isEmpty,
            !sources.contains(where: { $0 == destination || $0.isAncestor(of: destination) })
        else { return [] }
        let mask = info.draggingSourceOperationMask
        if mask == .copy { return .copy }
        if mask == .generic { return .move }
        if sources.allSatisfy({ $0.deletingLastPathComponent().canonical == destination.canonical }) {
            return []
        }
        return sources.allSatisfy { FileMutations.sameVolume($0, destination) } ? .move : .copy
    }

    static func accept(_ info: NSDraggingInfo, destination: URL, window: NSWindow?) -> Bool {
        let operation = operation(for: info, destination: destination)
        guard !operation.isEmpty else { return false }
        FileOperationCenter.shared.transfer(
            urls(info), to: destination, mode: operation == .copy ? .copy : .move, window: window
        )
        return true
    }

    static func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}

enum Formatters {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Strings.locale))
    }
}
