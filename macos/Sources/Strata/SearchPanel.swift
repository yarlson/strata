// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Keeps one recent global index so repeated searches start with results.
@MainActor
final class SearchService {
    static let shared = SearchService()
    /// App-internal data that would fill the index before the user's own files.
    static let builtInExclusions = ["~/Library"]
    private var index: SearchIndex?
    private var created = Date.distantPast
    private var settings: (Bool, [String]) = (false, [])

    func currentIndex() -> SearchIndex {
        let preferences = Preferences.shared
        let wanted = (preferences.showHidden, preferences.searchExclusions)
        if let index, Date().timeIntervalSince(created) < 60, settings == wanted {
            return index
        }
        index?.cancel()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let next = SearchIndex(
            roots: [home] + VolumeMonitor.shared.searchRoots,
            exclusions: SearchExclusions(rules: wanted.1 + Self.builtInExclusions, home: home),
            includeHidden: wanted.0
        )
        next.start()
        index = next
        created = Date()
        settings = wanted
        return next
    }
}

enum SearchChoice {
    case reveal(URL), open(URL), newTab(URL)
}

/// The Cmd+K sheet: fuzzy search across home and mounted local drives.
@MainActor
final class SearchPanel: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let foldersOnly: Bool
    private let completion: (SearchChoice) -> Void
    private let field = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField.scaledLabel(color: .secondaryLabelColor, scale: 0.82)
    private let index: SearchIndex
    private var results: [IndexedItem] = []
    private var generation = 0
    private var poll: Timer?

    init(foldersOnly: Bool, completion: @escaping (SearchChoice) -> Void) {
        self.foldersOnly = foldersOnly
        self.completion = completion
        index = SearchService.shared.currentIndex()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        super.init(window: panel)
        build(panel)
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWhileIndexing() }
        }
        runQuery()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present(over window: NSWindow) {
        guard let sheet = self.window else { return }
        window.beginSheet(sheet)
        sheet.makeFirstResponder(field)
    }

    private func build(_ panel: NSPanel) {
        let content = PaneView()
        field.placeholderString = foldersOnly ? tr("Jump to a folder…") : tr("Search files and folders…")
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.font = Appearance.shared.font(scale: 1.1)
        let column = NSTableColumn(identifier: .init("result"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = Appearance.shared.rowHeight * 1.6
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(choose)
        table.focusRingType = .none
        table.style = .plain
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        for child in [field, scroll, status] {
            child.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(child)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])
        panel.contentView = content
        status.toolTip = nil
    }

    // MARK: Query

    func controlTextDidChange(_ obj: Notification) {
        runQuery()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            close(with: nil)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            choose()
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
        default:
            return false
        }
        return true
    }

    private func moveSelection(_ step: Int) {
        guard !results.isEmpty else { return }
        let row = (table.selectedRow + step).clamped(to: 0...(results.count - 1))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func runQuery() {
        generation += 1
        let generation = generation
        let snapshot = index.snapshot()
        let foldersOnly = foldersOnly
        guard let query = FuzzyQuery(field.stringValue) else {
            results = []
            table.reloadData()
            updateStatus(snapshot)
            return
        }
        Task.detached(priority: .userInitiated) {
            let found = SearchIndex.search(query, in: snapshot, foldersOnly: foldersOnly)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.results = found
                self.table.reloadData()
                if !found.isEmpty { self.table.selectRowIndexes([0], byExtendingSelection: false) }
                self.updateStatus(snapshot)
            }
        }
    }

    private func refreshWhileIndexing() {
        let snapshot = index.snapshot()
        if snapshot.isFinished {
            poll?.invalidate()
            poll = nil
        }
        if FuzzyQuery(field.stringValue) != nil { runQuery() } else { updateStatus(snapshot) }
    }

    private func updateStatus(_ snapshot: SearchIndex.Snapshot) {
        let indexed = trCount("items", snapshot.count)
        if !snapshot.isFinished {
            status.stringValue = "\(tr("Indexing files…"))  ·  \(indexed)"
        } else if snapshot.isTruncated {
            status.stringValue = "\(tr("Results may be incomplete"))  ·  \(indexed)"
        } else {
            status.stringValue = indexed
        }
        status.toolTip = nil
    }

    // MARK: Choice

    @objc private func choose() {
        let row = table.selectedRow >= 0 ? table.selectedRow : (results.isEmpty ? -1 : 0)
        guard results.indices.contains(row) else { return }
        let url = results[row].url
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.option) {
            close(with: .open(url))
        } else if flags.contains(.command) {
            close(with: .newTab(url))
        } else {
            close(with: .reveal(url))
        }
    }

    private func close(with choice: SearchChoice?) {
        poll?.invalidate()
        poll = nil
        if let sheet = window, let parent = sheet.sheetParent {
            parent.endSheet(sheet)
        }
        if let choice { completion(choice) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = results[row]
        return SearchResultCell(
            icon: NSWorkspace.shared.icon(forFile: item.url.path), name: item.name,
            location: LocationBar.displayPath(item.url.deletingLastPathComponent())
        )
    }
}

/// A result's icon, name, and folder; the text follows the row's selection.
private final class SearchResultCell: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private let location = NSTextField(labelWithString: "")

    init(icon image: NSImage, name: String, location: String) {
        super.init(frame: .zero)
        let appearance = Appearance.shared
        let icon = NSImageView(image: image)
        self.name.stringValue = name
        self.name.font = appearance.font(weight: .semibold)
        self.name.lineBreakMode = .byTruncatingMiddle
        self.location.stringValue = location
        self.location.font = appearance.font(scale: 0.82)
        self.location.lineBreakMode = .byTruncatingHead
        for child in [icon, self.name, self.location] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            self.name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            self.name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            self.name.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            self.location.leadingAnchor.constraint(equalTo: self.name.leadingAnchor),
            self.location.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            self.location.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        name.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        location.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}
