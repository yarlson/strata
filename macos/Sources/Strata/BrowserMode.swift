// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// What every browser mode tells its window.
@MainActor
protocol BrowserModeHost: AnyObject {
    var window: NSWindow? { get }
    /// The directory that receives paste and new items changed.
    func modeDidChangeDirectory(_ url: URL, recordHistory: Bool)
    func modeSelectionDidChange()
    /// Commands shared by every mode; returns true when the key was used.
    func modeHandleCommandKey(_ event: NSEvent) -> Bool
    func modeOpen(_ entries: [FileEntry])
    func modeNavigateUp()
    func modeContextMenu(for entries: [FileEntry], in directory: URL) -> NSMenu
    func modeDirectoryVanished(_ url: URL)
    func modeQuickLook()
}

/// Columns, Icons, or List: one way of showing the current location.
@MainActor
protocol BrowserMode: AnyObject {
    var view: NSView { get }
    var host: BrowserModeHost? { get set }
    var activeDirectory: URL { get }
    var selectedEntries: [FileEntry] { get }
    var filterText: String { get set }
    var isFilterIncomplete: Bool { get }
    var isRenaming: Bool { get }
    func show(_ location: URL, selecting: [URL])
    func focus()
    func select(_ urls: [URL])
    func beginRename(_ url: URL)
    func selectAll()
    func reload()
    func setPreviewVisible(_ visible: Bool)
}

/// Remembers the selection of the last directories left in one browser so
/// returning to them restores it.
struct SelectionMemory {
    private var entries: [URL: [URL]] = [:]
    private var order: [URL] = []
    private let limit = 128

    mutating func remember(_ selection: [URL], in directory: URL) {
        entries[directory] = selection
        order.removeAll { $0 == directory }
        order.append(directory)
        if order.count > limit {
            entries[order.removeFirst()] = nil
        }
    }

    func selection(in directory: URL) -> [URL] {
        entries[directory] ?? []
    }
}

/// Shared keyboard movement for table-based modes. Returns true when handled.
@MainActor
func handleTableMovement(_ event: NSEvent, table: FileTableView) -> Bool {
    let cursor = table.cursorRow
    switch true {
    case Bindings.up.matches(event), Bindings.vimUp.matches(event):
        table.moveCursor(to: cursor < 0 ? 0 : cursor - 1)
    case Bindings.down.matches(event), Bindings.vimDown.matches(event):
        table.moveCursor(to: cursor < 0 ? 0 : cursor + 1)
    case Bindings.extendUp.matches(event):
        table.moveCursor(to: max(cursor - 1, 0), extend: true)
    case Bindings.extendDown.matches(event):
        table.moveCursor(to: cursor + 1, extend: true)
    case Bindings.firstItem.matches(event):
        table.moveCursor(to: 0)
    case Bindings.lastItem.matches(event):
        table.moveCursor(to: table.numberOfRows - 1)
    case Bindings.pageUp.matches(event):
        table.moveCursor(to: max(cursor, 0) - table.pageRowCount)
    case Bindings.pageDown.matches(event):
        table.moveCursor(to: max(cursor, 0) + table.pageRowCount)
    case Bindings.escape.matches(event):
        table.deselectAll(nil)
    default:
        return false
    }
    return true
}

@MainActor
final class PreviewSplit: NSSplitView {
    let preview = PreviewController()

    init(content: NSView) {
        super.init(frame: .zero)
        isVertical = true
        dividerStyle = .thin
        addArrangedSubview(content)
        addArrangedSubview(preview.view)
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        preview.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        setHoldingPriority(.defaultLow, forSubviewAt: 0)
        setHoldingPriority(.defaultHigh, forSubviewAt: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var dividerColor: NSColor { Appearance.shared.palette.border }

    func setPreviewVisible(_ visible: Bool) {
        let wasHidden = preview.view.isHidden
        preview.view.isHidden = !visible
        if visible, wasHidden {
            layoutSubtreeIfNeeded()
            setPosition(max(bounds.width - 380, bounds.width * 0.55), ofDividerAt: 0)
        }
        adjustSubviews()
    }
}
