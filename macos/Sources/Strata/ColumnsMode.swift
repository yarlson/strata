// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Lays out fixed-width columns left to right, then the preview in the
/// remaining width.
final class ColumnsDocumentView: NSView {
    var columnViews: [NSView] = [] {
        didSet { needsLayout = true }
    }
    var previewView: NSView? {
        didSet { needsLayout = true }
    }
    var columnWidth: CGFloat = 250
    var minimumPreviewWidth: CGFloat = 380

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let height = superview?.bounds.height ?? bounds.height
        var x: CGFloat = 0
        for view in columnViews {
            view.frame = NSRect(x: x, y: 0, width: columnWidth, height: height)
            x += columnWidth + 1
        }
        let visibleWidth = superview?.bounds.width ?? 0
        if let previewView, !previewView.isHidden {
            let width = max(visibleWidth - x, minimumPreviewWidth)
            previewView.frame = NSRect(x: x, y: 0, width: width, height: height)
            x += width
        }
        let size = NSSize(width: max(x, visibleWidth), height: height)
        if frame.size != size { setFrameSize(size) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        for view in columnViews {
            NSRect(x: view.frame.maxX, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

/// Miller columns: each opened folder adds a column, and a selected file
/// shows its preview after the last column.
@MainActor
final class ColumnsMode: NSObject, BrowserMode, DirectoryTableOwner {
    let view: NSView
    weak var host: BrowserModeHost?

    private let scrollView = NSScrollView()
    private let document = ColumnsDocumentView()
    private let preview = PreviewController()
    private var columns: [DirectoryTableController] = []
    private var focusedIndex = 0
    private var pendingChild: DispatchWorkItem?
    private var previewVisible = true

    override init() {
        let container = PaneView(fill: .controlBackgroundColor)
        view = container
        super.init()
        scrollView.documentView = document
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleAreaChanged), name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        document.previewView = preview.view
        document.addSubview(preview.view)
        preview.view.isHidden = true
        updateColumnWidth()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged), name: Appearance.didChange, object: nil
        )
    }

    @objc private func visibleAreaChanged() {
        document.needsLayout = true
    }

    @objc private func appearanceChanged() {
        updateColumnWidth()
        document.needsDisplay = true
    }

    private func updateColumnWidth() {
        document.columnWidth = (Appearance.shared.textSize * 19).rounded()
        document.needsLayout = true
    }

    // MARK: BrowserMode

    var activeDirectory: URL {
        focusedColumn?.url ?? columns.first?.url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var selectedEntries: [FileEntry] {
        focusedColumn?.selectedEntries ?? []
    }

    var filterText: String {
        get { focusedColumn?.model.filterText ?? "" }
        set { focusedColumn?.model.filterText = newValue }
    }

    var isFilterIncomplete: Bool { focusedColumn?.model.isFilterIncomplete ?? false }

    var isRenaming: Bool { columns.contains { $0.isRenaming } }

    private var focusedColumn: DirectoryTableController? {
        columns.indices.contains(focusedIndex) ? columns[focusedIndex] : nil
    }

    func show(_ location: URL, selecting: [URL]) {
        let location = location.canonical
        if let index = columns.firstIndex(where: { $0.url == location }) {
            trim(after: index)
            setFocused(index)
            if !selecting.isEmpty { columns[index].select(selecting) }
            columns[index].focus(selectingFirstIfEmpty: false)
            updatePreview()
            return
        }
        columns.forEach { $0.view.removeFromSuperview() }
        columns = []
        let column = append(location)
        setFocused(0)
        column.select(selecting)
        preview.clear()
        preview.view.isHidden = true
        document.needsLayout = true
        scrollView.contentView.scroll(to: .zero)
    }

    func focus() {
        focusedColumn?.focus(selectingFirstIfEmpty: false)
    }

    func select(_ urls: [URL]) {
        focusedColumn?.select(urls)
    }

    func beginRename(_ url: URL) {
        let directory = url.deletingLastPathComponent().canonical
        let column = columns.first { $0.url == directory } ?? focusedColumn
        column?.beginRename(url, window: view.window)
    }

    func selectAll() {
        focusedColumn?.table.selectAll(nil)
    }

    func reload() {
        columns.forEach { $0.model.load() }
    }

    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        updatePreview()
    }

    // MARK: Columns

    @discardableResult
    private func append(_ url: URL) -> DirectoryTableController {
        let column = DirectoryTableController(url: url, style: .column)
        column.owner = self
        columns.append(column)
        document.addSubview(column.view)
        document.columnViews = columns.map(\.view)
        return column
    }

    private func trim(after index: Int) {
        guard columns.count > index + 1 else { return }
        for column in columns[(index + 1)...] {
            column.view.removeFromSuperview()
        }
        columns.removeSubrange((index + 1)...)
        document.columnViews = columns.map(\.view)
    }

    private func setFocused(_ index: Int) {
        focusedIndex = index
    }

    /// Opens the selected folder's column after a short pause so key repeat
    /// does not load every folder it passes.
    private func scheduleChild(for entry: FileEntry, after column: DirectoryTableController) {
        pendingChild?.cancel()
        let work = DispatchWorkItem { [weak self, weak column] in
            MainActor.assumeIsolated {
                guard let self, let column, let index = self.columns.firstIndex(where: { $0 === column }),
                    column.selectedEntries == [entry]
                else { return }
                self.trim(after: index)
                self.append(entry.url)
                self.scrollToEnd()
            }
        }
        pendingChild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func openChild(of index: Int) {
        guard columns.indices.contains(index),
            let entry = columns[index].cursorEntry, entry.isFolder
        else { return }
        pendingChild?.cancel()
        if columns.count <= index + 1 || columns[index + 1].url != entry.url {
            trim(after: index)
            append(entry.url)
        }
        setFocused(index + 1)
        columns[index + 1].focus()
        scrollToEnd()
        host?.modeDidChangeDirectory(entry.url, recordHistory: true)
    }

    private func focusColumn(_ index: Int) {
        guard columns.indices.contains(index) else { return }
        setFocused(index)
        columns[index].focus()
        scrollToVisible(index)
        host?.modeDidChangeDirectory(columns[index].url, recordHistory: true)
    }

    private func scrollToEnd() {
        document.layoutSubtreeIfNeeded()
        let maxX = max(document.frame.width - scrollView.contentView.bounds.width, 0)
        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: maxX, y: 0))
    }

    private func scrollToVisible(_ index: Int) {
        document.layoutSubtreeIfNeeded()
        document.scrollToVisible(columns[index].view.frame)
    }

    private func updatePreview() {
        guard let column = focusedColumn ?? columns.last else { return }
        let index = columns.firstIndex { $0 === column } ?? 0
        let deepest = columns.count - 1 > index ? columns[columns.count - 1] : column
        let entries = deepest.selectedEntries
        if !previewVisible {
            preview.view.isHidden = true
        } else if entries.count == 1, let entry = entries.first, !entry.isFolder {
            preview.view.isHidden = false
            preview.show(entry)
        } else if entries.count > 1 {
            preview.view.isHidden = false
            preview.showSelection(count: entries.count, totalSize: entries.compactMap(\.size).reduce(0, +))
        } else {
            preview.clear()
            preview.view.isHidden = true
        }
        document.needsLayout = true
        if !preview.view.isHidden { scrollToEnd() }
    }

    // MARK: DirectoryTableOwner

    var window: NSWindow? { view.window }

    func directoryTableSelectionDidChange(_ controller: DirectoryTableController) {
        guard let index = columns.firstIndex(where: { $0 === controller }) else { return }
        let entries = controller.selectedEntries
        let userDriven = controller.table.isFirstResponder
        if entries.count == 1, let entry = entries.first, entry.isFolder {
            if columns.count > index + 1, columns[index + 1].url == entry.url {
                trim(after: index + 1)
            } else {
                trim(after: index)
                if userDriven { scheduleChild(for: entry, after: controller) }
            }
        } else {
            pendingChild?.cancel()
            trim(after: index)
        }
        updatePreview()
        host?.modeSelectionDidChange()
    }

    func directoryTableDidFocus(_ controller: DirectoryTableController) {
        guard let index = columns.firstIndex(where: { $0 === controller }), index != focusedIndex else { return }
        setFocused(index)
        host?.modeDidChangeDirectory(controller.url, recordHistory: true)
        updatePreview()
    }

    func directoryTable(_ controller: DirectoryTableController, handleKey event: NSEvent) -> Bool {
        guard let index = columns.firstIndex(where: { $0 === controller }) else { return false }
        let entry = controller.cursorEntry
        switch true {
        case Bindings.right.matches(event), Bindings.vimRight.matches(event):
            if entry?.isFolder == true {
                openChild(of: index)
            } else if columns.count > index + 1 {
                focusColumn(index + 1)
            }
        case Bindings.enter.matches(event):
            if let entry, entry.isFolder, controller.selectedEntries.count <= 1 {
                openChild(of: index)
            } else {
                host?.modeOpen(controller.selectedEntries)
            }
        case Bindings.left.matches(event), Bindings.vimLeft.matches(event), Bindings.backspace.matches(event):
            if index > 0 { focusColumn(index - 1) } else { host?.modeNavigateUp() }
        case Bindings.focusNext.matches(event):
            focusColumn(min(index + 1, columns.count - 1))
        case Bindings.focusPrevious.matches(event):
            focusColumn(max(index - 1, 0))
        case Bindings.space.matches(event):
            if let entry, entry.isFolder, controller.selectedEntries.count == 1 {
                openChild(of: index)
            } else {
                host?.modeQuickLook()
            }
        default:
            if handleTableMovement(event, table: controller.table) { return true }
            return host?.modeHandleCommandKey(event) ?? false
        }
        return true
    }

    func directoryTableActivate(_ controller: DirectoryTableController) {
        guard let index = columns.firstIndex(where: { $0 === controller }) else { return }
        if let entry = controller.cursorEntry, entry.isFolder {
            openChild(of: index)
        } else {
            host?.modeOpen(controller.selectedEntries)
        }
    }

    func directoryTableMenu(_ controller: DirectoryTableController) -> NSMenu? {
        host?.modeContextMenu(for: controller.selectedEntries, in: controller.url)
    }

    func directoryTableDidLoad(_ controller: DirectoryTableController) {
        if controller === focusedColumn { host?.modeSelectionDidChange() }
    }

    func directoryTableVanished(_ controller: DirectoryTableController) {
        guard let index = columns.firstIndex(where: { $0 === controller }) else { return }
        if index == 0 {
            host?.modeDirectoryVanished(controller.url)
        } else {
            trim(after: index - 1)
            focusColumn(index - 1)
        }
    }
}
