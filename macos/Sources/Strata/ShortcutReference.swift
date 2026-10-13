// SPDX-License-Identifier: MIT

import AppKit

/// The F1 reference: every shortcut, rendered from the binding catalog.
@MainActor
final class ShortcutReference: NSWindowController {
    static let shared = ShortcutReference()

    private static func keys(_ bindings: KeyBinding...) -> String {
        bindings.map(\.label).joined(separator: "  ")
    }

    private static var sections: [(String, [(String, String)])] {
        [
            (
                tr("Navigate"),
                [
                    (keys(Bindings.up, Bindings.down, Bindings.vimUp, Bindings.vimDown), tr("Move the cursor")),
                    (keys(Bindings.extendUp, Bindings.extendDown), tr("Extend the selection")),
                    (
                        keys(Bindings.left, Bindings.right, Bindings.vimLeft, Bindings.vimRight),
                        tr("Parent pane / enter folder")
                    ),
                    (keys(Bindings.firstItem, Bindings.lastItem), tr("First or last item")),
                    (keys(Bindings.pageUp, Bindings.pageDown), tr("Page up or down")),
                    (keys(Bindings.enter, Bindings.open), tr("Open")),
                    (keys(Bindings.space, Bindings.quickLook), tr("Quick preview")),
                    (
                        keys(Bindings.backspace, Bindings.enclosingFolder, Bindings.parentAlt),
                        tr("Go to the parent folder")
                    ),
                    (keys(Bindings.back, Bindings.historyBackAlt), tr("Back")),
                    (keys(Bindings.forward, Bindings.historyForwardAlt), tr("Forward")),
                    (keys(Bindings.home, Bindings.homeAlt), tr("Home")),
                    (keys(Bindings.focusNext, Bindings.focusPrevious), tr("Next or previous column")),
                    (keys(Bindings.location), tr("Go to a path or URI")),
                    (keys(Bindings.search), tr("Search")),
                    (keys(Bindings.jumpToFolder), tr("Jump to a folder…")),
                    (keys(Bindings.filter, Bindings.filterSlash), tr("Filter")),
                    (keys(Bindings.sidebarFocus), tr("Focus the sidebar")),
                ]
            ),
            (
                tr("File"),
                [
                    (keys(Bindings.newFolder), tr("New Folder")),
                    (keys(Bindings.newFolderWithSelection), tr("New Folder with Selection")),
                    (keys(Bindings.newFile), tr("New File")),
                    (keys(Bindings.rename, Bindings.renameCommand), tr("Rename")),
                    (keys(Bindings.duplicate), tr("Duplicate")),
                    (keys(Bindings.copy, Bindings.cut, Bindings.paste), tr("Copy / cut")),
                    (keys(Bindings.copyPath, Bindings.copyPathPlain), tr("Copy path")),
                    (keys(Bindings.pin, Bindings.pinPlain), tr("Pin")),
                    (keys(Bindings.trash, Bindings.trashForwardDelete), tr("Move to Trash")),
                    (
                        keys(Bindings.deletePermanently, Bindings.deletePermanentlyForwardDelete),
                        tr("Delete Permanently")
                    ),
                    (keys(Bindings.properties, Bindings.propertiesEnter), tr("Properties")),
                    (keys(Bindings.terminal), tr("Open in Terminal")),
                    (keys(Bindings.undo, Bindings.redo), tr("Undo") + " / " + tr("Redo")),
                ]
            ),
            (
                tr("View"),
                [
                    (
                        keys(Bindings.viewColumns, Bindings.viewIcons, Bindings.viewList),
                        tr("Columns") + " / " + tr("Icons") + " / " + tr("List")
                    ),
                    (keys(Bindings.hiddenFiles), tr("Show hidden files")),
                    (keys(Bindings.preview), tr("Show preview")),
                    (keys(Bindings.sidebar), tr("Show sidebar")),
                    (keys(Bindings.refresh), tr("Refresh")),
                    (keys(Bindings.textLarger, Bindings.textSmaller, Bindings.textReset), tr("Text size")),
                    (keys(Bindings.settings), tr("Settings")),
                    (keys(Bindings.reference), tr("Keyboard shortcuts")),
                ]
            ),
            (
                tr("Tabs"),
                [
                    (keys(Bindings.newTab, Bindings.openInNewTab), tr("New Tab")),
                    (keys(Bindings.newWindow, Bindings.openInNewWindow), tr("New Window")),
                    (keys(Bindings.closeTab), tr("Close tab")),
                    ("⌃⇥  ⌃⇧⇥", tr("Next or previous tab")),
                ]
            ),
        ]
    }

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true
        )
        panel.title = tr("Keyboard shortcuts")
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        rebuild()
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            rebuild()
            showWindow(nil)
        }
    }

    private func rebuild() {
        let appearance = Appearance.shared
        window?.appearance = appearance.palette.appearance
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        for (title, rows) in Self.sections {
            let header = NSTextField.themedLabel(
                title.uppercased(with: Strings.locale), color: \.accent, scale: 0.8, weight: .semibold)
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(8, after: header)
            let grid = NSGridView(
                views: rows.map { keys, action in
                    [
                        NSTextField.themedLabel(keys, color: \.text, scale: 0.9, weight: .semibold),
                        NSTextField.themedLabel(action, color: \.dimText, scale: 0.9),
                    ]
                })
            grid.column(at: 0).width = 200
            grid.rowSpacing = 5
            stack.addArrangedSubview(grid)
            stack.setCustomSpacing(18, after: grid)
        }
        let scroll = NSScrollView()
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        let content = ThemedView(fill: \.background)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window?.contentView = content
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
