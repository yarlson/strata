// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
final class ListMode: NSObject, BrowserMode, DirectoryTableOwner {
    let view: NSView
    weak var host: BrowserModeHost?

    private let container = ThemedView(fill: \.background)
    private let split: PreviewSplit
    private var controller: DirectoryTableController?
    private var memory = SelectionMemory()

    override init() {
        split = PreviewSplit(content: container)
        view = split
        super.init()
        split.preview.onClose = { Preferences.shared.showPreview = false }
    }

    var activeDirectory: URL {
        controller?.url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var selectedEntries: [FileEntry] { controller?.selectedEntries ?? [] }

    var filterText: String {
        get { controller?.model.filterText ?? "" }
        set { controller?.model.filterText = newValue }
    }

    var isFilterIncomplete: Bool { controller?.model.isFilterIncomplete ?? false }
    var isRenaming: Bool { controller?.isRenaming ?? false }

    func show(_ location: URL, selecting: [URL]) {
        let location = location.canonical
        if let controller {
            memory.remember(controller.selectedEntries.map(\.url), in: controller.url)
            controller.view.removeFromSuperview()
        }
        let next = DirectoryTableController(url: location, style: .list)
        next.owner = self
        controller = next
        next.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: container.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            next.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        next.select(selecting.isEmpty ? memory.selection(in: location) : selecting)
        split.preview.clear()
    }

    func focus() { controller?.focus() }
    func select(_ urls: [URL]) { controller?.select(urls) }
    func beginRename(_ url: URL) { controller?.beginRename(url, window: view.window) }
    func selectAll() { controller?.table.selectAll(nil) }
    func reload() { controller?.model.load() }
    func setPreviewVisible(_ visible: Bool) { split.setPreviewVisible(visible) }

    // MARK: DirectoryTableOwner

    var window: NSWindow? { view.window }

    func directoryTableSelectionDidChange(_ controller: DirectoryTableController) {
        let entries = controller.selectedEntries
        if entries.count == 1, let entry = entries.first {
            split.preview.show(entry)
        } else if entries.count > 1 {
            split.preview.showSelection(count: entries.count, totalSize: entries.compactMap(\.size).reduce(0, +))
        } else {
            split.preview.clear()
        }
        host?.modeSelectionDidChange()
    }

    func directoryTableDidFocus(_ controller: DirectoryTableController) {}

    func directoryTable(_ controller: DirectoryTableController, handleKey event: NSEvent) -> Bool {
        let entry = controller.cursorEntry
        switch true {
        case Bindings.enter.matches(event):
            host?.modeOpen(controller.selectedEntries)
        case Bindings.right.matches(event), Bindings.vimRight.matches(event):
            if let entry, entry.isFolder { host?.modeOpen([entry]) }
        case Bindings.left.matches(event), Bindings.vimLeft.matches(event), Bindings.backspace.matches(event):
            host?.modeNavigateUp()
        case Bindings.space.matches(event):
            if let entry, entry.isFolder, controller.selectedEntries.count == 1 {
                host?.modeOpen([entry])
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
        host?.modeOpen(controller.selectedEntries)
    }

    func directoryTableMenu(_ controller: DirectoryTableController) -> NSMenu? {
        host?.modeContextMenu(for: controller.selectedEntries, in: controller.url)
    }

    func directoryTableDidLoad(_ controller: DirectoryTableController) {
        host?.modeSelectionDidChange()
    }

    func directoryTableVanished(_ controller: DirectoryTableController) {
        host?.modeDirectoryVanished(controller.url)
    }
}
