// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
protocol IconCollectionDelegate: AnyObject {
    func iconCollection(_ view: IconCollectionView, handleKey event: NSEvent) -> Bool
    func iconCollectionMenu(_ view: IconCollectionView) -> NSMenu?
    func iconCollectionActivate(_ view: IconCollectionView)
}

final class IconCollectionView: NSCollectionView {
    weak var iconDelegate: IconCollectionDelegate?

    override func keyDown(with event: NSEvent) {
        if iconDelegate?.iconCollection(self, handleKey: event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let path = indexPathForItem(at: point) {
            if !selectionIndexPaths.contains(path) {
                selectionIndexPaths = [path]
                delegate?.collectionView?(self, didSelectItemsAt: [path])
            }
        } else {
            deselectAll(nil)
            delegate?.collectionView?(self, didDeselectItemsAt: [])
        }
        window?.makeFirstResponder(self)
        return iconDelegate?.iconCollectionMenu(self)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil {
            iconDelegate?.iconCollectionActivate(self)
        }
    }
}

final class IconItemView: NSView {
    var isSelected = false { didSet { needsDisplay = true } }
    var isFocused = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let palette = Appearance.shared.palette
        (isFocused ? palette.selection : palette.highlight).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
    }
}

final class IconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IconItem")
    private(set) var entryURL: URL?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let container = IconItemView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = true
        for child in [icon, label] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
        ])
        view = container
        imageView = icon
        textField = label
    }

    override var isSelected: Bool {
        didSet { (view as? IconItemView)?.isSelected = isSelected }
    }

    func setFocused(_ focused: Bool) {
        (view as? IconItemView)?.isFocused = focused
    }

    func configure(_ entry: FileEntry, size: CGFloat) {
        entryURL = entry.url
        let appearance = Appearance.shared
        label.stringValue = entry.name
        label.font = appearance.font(scale: 0.9)
        label.textColor = entry.isHidden ? appearance.palette.dimText : appearance.palette.text
        icon.image = IconProvider.shared.cachedThumbnail(for: entry, size: size) ?? IconProvider.shared.icon(for: entry)
        guard !entry.isFolder, !entry.isPackage else { return }
        IconProvider.shared.thumbnail(for: entry, size: size) { [weak self] image in
            guard let self, let image, self.entryURL == entry.url else { return }
            self.icon.image = image
        }
    }
}

@MainActor
final class IconsMode: NSObject, BrowserMode, NSCollectionViewDataSource, NSCollectionViewDelegate,
    IconCollectionDelegate
{
    let view: NSView
    weak var host: BrowserModeHost?

    private let collection = IconCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField.themedLabel(color: \.dimText, scale: 0.92)
    private let split: PreviewSplit
    private var model: DirectoryModel?
    private var memory = SelectionMemory()
    private var pendingSelection: [URL] = []
    private var rename: InlineRename?

    override init() {
        let container = ThemedView(fill: \.background)
        split = PreviewSplit(content: container)
        view = split
        super.init()
        split.preview.onClose = { Preferences.shared.showPreview = false }
        collection.collectionViewLayout = makeLayout()
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.clear]
        collection.dataSource = self
        collection.delegate = self
        collection.iconDelegate = self
        collection.register(IconItem.self, forItemWithIdentifier: IconItem.identifier)
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        scrollView.documentView = collection
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        for child in [scrollView, emptyLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -24),
        ])
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 4
        emptyLabel.lineBreakMode = .byWordWrapping
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: Appearance.didChange, object: nil
        )
    }

    @objc private func themeChanged() {
        collection.collectionViewLayout = makeLayout()
        collection.reloadData()
    }

    private var iconSize: CGFloat { (Appearance.shared.textSize * 5).rounded() }

    private func makeLayout() -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        let width = iconSize + 44
        layout.itemSize = NSSize(width: width, height: iconSize + Appearance.shared.textSize * 3 + 20)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        return layout
    }

    // MARK: BrowserMode

    var activeDirectory: URL { model?.url ?? FileManager.default.homeDirectoryForCurrentUser }

    var selectedEntries: [FileEntry] {
        guard let model else { return [] }
        return collection.selectionIndexPaths.sorted().compactMap {
            model.entries.indices.contains($0.item) ? model.entries[$0.item] : nil
        }
    }

    var filterText: String {
        get { model?.filterText ?? "" }
        set { model?.filterText = newValue }
    }

    var isFilterIncomplete: Bool { model?.isFilterIncomplete ?? false }
    var isRenaming: Bool { rename != nil }

    func show(_ location: URL, selecting: [URL]) {
        let location = location.canonical
        if let model {
            memory.remember(selectedEntries.map(\.url), in: model.url)
        }
        let next = DirectoryModel(url: location)
        model = next
        pendingSelection = selecting.isEmpty ? memory.selection(in: location) : selecting
        next.onChange = { [weak self] in self?.modelDidChange() }
        next.onVanish = { [weak self] in self?.host?.modeDirectoryVanished(location) }
        collection.reloadData()
        split.preview.clear()
        next.load()
    }

    func focus() {
        collection.window?.makeFirstResponder(collection)
        if collection.selectionIndexPaths.isEmpty, (model?.entries.count ?? 0) > 0 {
            select(at: 0)
        }
    }

    func select(_ urls: [URL]) {
        guard let model else { return }
        let urls = urls.map(\.canonical)
        let paths = Set(urls.compactMap(model.index(of:)).map { IndexPath(item: $0, section: 0) })
        if paths.count < urls.count { pendingSelection = urls }
        collection.selectionIndexPaths = paths
        if let first = paths.min() { collection.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge) }
        selectionDidChange()
    }

    func beginRename(_ url: URL) {
        guard let index = model?.index(of: url), let entry = model?.entries[index] else {
            pendingSelection = [url]
            pendingRename = url
            return
        }
        let path = IndexPath(item: index, section: 0)
        collection.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        collection.selectionIndexPaths = [path]
        guard let item = collection.item(at: path), let field = item.textField else { return }
        let window = view.window
        rename = InlineRename(
            field: field, entry: entry,
            commit: { [weak self] name in
                if let renamed = FileOperationCenter.shared.rename(entry.url, to: name, window: window) {
                    self?.select([renamed])
                }
            },
            finish: { [weak self] restoreFocus in
                guard let self else { return }
                self.rename = nil
                if restoreFocus { self.collection.window?.makeFirstResponder(self.collection) }
                if self.reloadAfterRename { self.modelDidChange() }
            })
    }

    private var pendingRename: URL?
    /// A reload arrived while a name was being edited; it waits so the edit survives.
    private var reloadAfterRename = false

    func selectAll() {
        collection.selectAll(nil)
        selectionDidChange()
    }

    func reload() { model?.load() }
    func setPreviewVisible(_ visible: Bool) { split.setPreviewVisible(visible) }

    private func select(at index: Int) {
        let path = IndexPath(item: index, section: 0)
        collection.selectionIndexPaths = [path]
        collection.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        selectionDidChange()
    }

    // MARK: Model

    private func modelDidChange() {
        reloadAfterRename = isRenaming
        guard let model, !isRenaming else { return }
        let keep = pendingSelection.isEmpty ? selectedEntries.map(\.url) : pendingSelection
        collection.reloadData()
        let paths = Set(keep.compactMap(model.index(of:)).map { IndexPath(item: $0, section: 0) })
        collection.selectionIndexPaths = paths
        if !pendingSelection.isEmpty, !paths.isEmpty {
            if let first = paths.min() { collection.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge) }
            if paths.count == pendingSelection.count { pendingSelection = [] }
        }
        if model.state != .loading, paths.isEmpty { pendingSelection = [] }
        switch model.state {
        case .loading: emptyLabel.stringValue = ""
        case let .failed(message): emptyLabel.stringValue = message
        case .loaded:
            emptyLabel.stringValue =
                model.entries.isEmpty
                ? (model.isFiltering ? tr("No results") : tr("This folder is empty")) : ""
        }
        emptyLabel.isHidden = emptyLabel.stringValue.isEmpty
        selectionDidChange()
        if let pendingRename, model.index(of: pendingRename) != nil {
            self.pendingRename = nil
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.beginRename(pendingRename) }
            }
        }
    }

    private func selectionDidChange() {
        let entries = selectedEntries
        if entries.count == 1, let entry = entries.first {
            split.preview.show(entry)
        } else if entries.count > 1 {
            split.preview.showSelection(count: entries.count, totalSize: entries.compactMap(\.size).reduce(0, +))
        } else {
            split.preview.clear()
        }
        let focused = collection.window?.firstResponder === collection
        for item in collection.visibleItems() {
            (item as? IconItem)?.setFocused(focused)
        }
        host?.modeSelectionDidChange()
    }

    // MARK: Collection view

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model?.entries.count ?? 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath)
        -> NSCollectionViewItem
    {
        let item = collectionView.makeItem(withIdentifier: IconItem.identifier, for: indexPath)
        if let item = item as? IconItem, let entry = model?.entries[indexPath.item] {
            item.configure(entry, size: iconSize)
            item.setFocused(collectionView.window?.firstResponder === collectionView)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selectionDidChange()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath)
        -> NSPasteboardWriting?
    {
        guard rename == nil else { return nil }
        return model?.entries[indexPath.item].url as NSURL?
    }

    func collectionView(
        _ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        DropTarget.operation(
            for: draggingInfo,
            destination: dropDestination(proposedIndexPath.pointee as IndexPath, dropOperation.pointee))
    }

    func collectionView(
        _ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        DropTarget.accept(draggingInfo, destination: dropDestination(indexPath, dropOperation), window: view.window)
    }

    private func dropDestination(_ indexPath: IndexPath, _ operation: NSCollectionView.DropOperation) -> URL {
        if operation == .on, let entries = model?.entries, entries.indices.contains(indexPath.item),
            entries[indexPath.item].isFolder
        {
            return entries[indexPath.item].url
        }
        return activeDirectory
    }

    // MARK: IconCollectionDelegate

    func iconCollection(_ view: IconCollectionView, handleKey event: NSEvent) -> Bool {
        let entries = selectedEntries
        switch true {
        case Bindings.enter.matches(event):
            host?.modeOpen(entries)
        case Bindings.backspace.matches(event):
            host?.modeNavigateUp()
        case Bindings.space.matches(event):
            if entries.count == 1, entries[0].isFolder { host?.modeOpen(entries) } else { host?.modeQuickLook() }
        case Bindings.escape.matches(event):
            collection.deselectAll(nil)
            selectionDidChange()
        case Bindings.vimLeft.matches(event), Bindings.vimRight.matches(event),
            Bindings.vimUp.matches(event), Bindings.vimDown.matches(event):
            moveSelection(event)
        case Bindings.firstItem.matches(event):
            if (model?.entries.count ?? 0) > 0 { select(at: 0) }
        case Bindings.lastItem.matches(event):
            if let count = model?.entries.count, count > 0 { select(at: count - 1) }
        default:
            return host?.modeHandleCommandKey(event) ?? false
        }
        return true
    }

    private func moveSelection(_ event: NSEvent) {
        let count = model?.entries.count ?? 0
        guard count > 0 else { return }
        let columns = max(
            1,
            Int(
                (collection.bounds.width - 24)
                    / ((collection.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.width ?? 100)))
        let current = collection.selectionIndexPaths.max()?.item ?? -1
        let step =
            switch true {
            case Bindings.vimLeft.matches(event): -1
            case Bindings.vimRight.matches(event): 1
            case Bindings.vimUp.matches(event): -columns
            default: columns
            }
        select(at: (current + step).clamped(to: 0...(count - 1)))
    }

    func iconCollectionMenu(_ view: IconCollectionView) -> NSMenu? {
        host?.modeContextMenu(for: selectedEntries, in: activeDirectory)
    }

    func iconCollectionActivate(_ view: IconCollectionView) {
        host?.modeOpen(selectedEntries)
    }
}
