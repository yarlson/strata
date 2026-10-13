// SPDX-License-Identifier: MIT

import AppKit

@MainActor
protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarController, navigateTo url: URL, newTab: Bool)
    func sidebarDidFinish(_ sidebar: SidebarController)
    func sidebarShowProperties(of url: URL)
}

final class SidebarNode {
    enum Kind {
        case group, place, pinned, volume
    }

    let kind: Kind
    let title: String
    let url: URL?
    let symbol: String
    let volume: Volume?
    var children: [SidebarNode] = []

    init(kind: Kind, title: String, url: URL? = nil, symbol: String = "folder", volume: Volume? = nil) {
        self.kind = kind
        self.title = title
        self.url = url
        self.symbol = symbol
        self.volume = volume
    }
}

final class SidebarOutlineView: NSOutlineView {
    var onKey: ((NSEvent) -> Bool)?
    var onMenu: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?(row(at: convert(event.locationInWindow, from: nil)))
    }
}

@MainActor
final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var delegate: SidebarDelegate?

    private let outline = SidebarOutlineView()
    private var groups: [SidebarNode] = []
    private var observers: [NSObjectProtocol] = []
    private var currentLocation: URL?

    override func loadView() {
        let container = ThemedView(fill: \.background)
        container.borderEdges = .maxX
        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
        ])
        let column = NSTableColumn(identifier: .init("sidebar"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.focusRingType = .none
        outline.indentationPerLevel = 0
        outline.rowSizeStyle = .custom
        outline.selectionHighlightStyle = .regular
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.registerForDraggedTypes([.fileURL])
        outline.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        outline.onMenu = { [weak self] row in self?.menu(forRow: row) }
        view = container
        rebuild()
        let center = NotificationCenter.default
        for name in [VolumeMonitor.didChange, Preferences.didChange, Appearance.didChange] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.rebuild() }
                })
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func focus() {
        view.window?.makeFirstResponder(outline)
        if outline.selectedRow < 0 { outline.selectRowIndexes([1], byExtendingSelection: false) }
    }

    /// Highlights the row for `url` when the sidebar lists it.
    func showLocation(_ url: URL) {
        currentLocation = url.canonical
        let row = (0..<outline.numberOfRows).first { index in
            (outline.item(atRow: index) as? SidebarNode)?.url?.canonical == currentLocation
        }
        if let row {
            outline.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            outline.deselectAll(nil)
        }
    }

    private func rebuild() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileManager = FileManager.default
        func place(_ directory: FileManager.SearchPathDirectory, _ title: String, _ symbol: String) -> SidebarNode? {
            fileManager.urls(for: directory, in: .userDomainMask).first.map {
                SidebarNode(kind: .place, title: title, url: $0, symbol: symbol)
            }
        }
        let places = SidebarNode(kind: .group, title: tr("Places"))
        places.children = [
            SidebarNode(kind: .place, title: tr("Home"), url: home, symbol: "house"),
            place(.desktopDirectory, tr("Desktop"), "menubar.dock.rectangle"),
            place(.documentDirectory, tr("Documents"), "doc.text"),
            place(.downloadsDirectory, tr("Downloads"), "arrow.down.circle"),
            place(.picturesDirectory, tr("Pictures"), "photo"),
            place(.musicDirectory, tr("Music"), "music.note"),
            place(.moviesDirectory, tr("Videos"), "film"),
            SidebarNode(
                kind: .place, title: tr("Applications"), url: URL(fileURLWithPath: "/Applications"),
                symbol: "square.grid.2x2"),
            SidebarNode(kind: .place, title: tr("Trash"), url: home.appendingPathComponent(".Trash"), symbol: "trash"),
        ].compactMap { $0 }
        let pinned = SidebarNode(kind: .group, title: tr("Pinned"))
        pinned.children = Preferences.shared.pinned.map {
            SidebarNode(kind: .pinned, title: $0.lastPathComponent, url: $0, symbol: "folder")
        }
        let devices = SidebarNode(kind: .group, title: tr("Devices"))
        devices.children = VolumeMonitor.shared.volumes.map {
            SidebarNode(
                kind: .volume, title: $0.name, url: $0.url, symbol: $0.isRoot ? "internaldrive" : "externaldrive",
                volume: $0)
        }
        groups = [places, pinned, devices].filter { !$0.children.isEmpty || $0 === pinned }
        outline.rowHeight = Appearance.shared.rowHeight
        outline.reloadData()
        groups.forEach { outline.expandItem($0) }
        if let currentLocation { showLocation(currentLocation) }
    }

    // MARK: Actions

    @objc private func rowClicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? SidebarNode, let url = node.url else { return }
        let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        delegate?.sidebar(self, navigateTo: url, newTab: newTab)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if Bindings.enter.matches(event) || Bindings.right.matches(event) || Bindings.space.matches(event) {
            if let node = outline.item(atRow: outline.selectedRow) as? SidebarNode, let url = node.url {
                delegate?.sidebar(self, navigateTo: url, newTab: false)
                delegate?.sidebarDidFinish(self)
            }
            return true
        }
        if Bindings.escape.matches(event) || Bindings.focusNext.matches(event) {
            delegate?.sidebarDidFinish(self)
            return true
        }
        if Bindings.vimDown.matches(event) || Bindings.vimUp.matches(event) {
            let step = Bindings.vimDown.matches(event) ? 1 : -1
            var row = outline.selectedRow + step
            while row >= 0, row < outline.numberOfRows, (outline.item(atRow: row) as? SidebarNode)?.kind == .group {
                row += step
            }
            if row >= 0, row < outline.numberOfRows { outline.selectRowIndexes([row], byExtendingSelection: false) }
            return true
        }
        return false
    }

    private func menu(forRow row: Int) -> NSMenu? {
        guard let node = outline.item(atRow: row) as? SidebarNode, let url = node.url else { return nil }
        let menu = NSMenu()
        menu.addItem(
            ClosureMenuItem(title: tr("Open in New Tab")) { [weak self] in
                guard let self else { return }
                self.delegate?.sidebar(self, navigateTo: url, newTab: true)
            })
        if node.kind == .pinned {
            menu.addItem(ClosureMenuItem(title: tr("Unpin")) { Preferences.shared.togglePin(url) })
        }
        if let volume = node.volume, volume.isEjectable {
            menu.addItem(
                ClosureMenuItem(title: tr("Eject")) { [weak self] in
                    VolumeMonitor.shared.eject(volume, from: self?.view.window)
                })
        }
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem(title: tr("Properties")) { [weak self] in
                self?.delegate?.sidebarShowProperties(of: url)
            })
        return menu
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarNode)?.children.count ?? groups.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarNode)?.children[index] ?? groups[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarNode)?.kind != .group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? SidebarNode)?.kind == .group ? Appearance.shared.rowHeight + 8 : Appearance.shared.rowHeight
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        SidebarRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let appearance = Appearance.shared
        if node.kind == .group {
            let label = NSTextField(labelWithString: node.title.uppercased(with: Strings.locale))
            label.font = appearance.font(scale: 0.75, weight: .semibold)
            label.textColor = appearance.palette.dimText
            let cell = NSTableCellView()
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            ])
            return cell
        }
        return SidebarCell(node: node) { [weak self] volume in
            VolumeMonitor.shared.eject(volume, from: self?.view.window)
        }
    }

    // MARK: Drag and drop

    func outlineView(
        _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let node = item as? SidebarNode else { return [] }
        if node.kind == .group, node.title == tr("Pinned") {
            let folders = DropTarget.urls(info).filter(\.hasDirectoryPath)
            return folders.isEmpty ? [] : .link
        }
        guard index == NSOutlineViewDropOnItemIndex, let url = node.url else { return [] }
        return DropTarget.operation(for: info, destination: url)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int)
        -> Bool
    {
        guard let node = item as? SidebarNode else { return false }
        if node.kind == .group {
            for url in DropTarget.urls(info) where url.hasDirectoryPath && !Preferences.shared.isPinned(url) {
                Preferences.shared.togglePin(url)
            }
            return true
        }
        guard let url = node.url else { return false }
        return DropTarget.accept(info, destination: url, window: view.window)
    }
}

final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let palette = Appearance.shared.palette
        palette.highlight.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override var isGroupRowStyle: Bool {
        get { false }
        set {}
    }
}

final class SidebarCell: NSTableCellView {
    private let ejectAction: (Volume) -> Void
    private let volume: Volume?

    init(node: SidebarNode, eject: @escaping (Volume) -> Void) {
        ejectAction = eject
        volume = node.volume
        super.init(frame: .zero)
        let appearance = Appearance.shared
        let icon = NSImageView(image: IconProvider.symbol(node.symbol, size: 13) ?? NSImage())
        icon.contentTintColor = appearance.palette.accent
        let label = NSTextField(labelWithString: node.title)
        label.font = appearance.font()
        label.textColor = appearance.palette.text
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for child in [icon, label] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let volume = node.volume, volume.isEjectable {
            let button = NSButton(
                image: IconProvider.symbol("eject", size: 11) ?? NSImage(), target: self,
                action: #selector(SidebarCell.ejectClicked))
            button.isBordered = false
            button.contentTintColor = appearance.palette.dimText
            button.toolTip = tr("Eject")
            button.setAccessibilityLabel(tr("Eject"))
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -6),
            ])
        } else {
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func ejectClicked() {
        if let volume { ejectAction(volume) }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
