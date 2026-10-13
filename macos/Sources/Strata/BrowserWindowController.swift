// SPDX-License-Identifier: MIT

import AppKit
import Quartz
import StrataCore

/// One browser window or tab: sidebar, location bar, the active browser mode,
/// filter, progress, and footer.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    static let tabbingIdentifier = "io.github.lgse.Strata.browser"

    private(set) var history: NavigationHistory
    private(set) var mode: BrowserMode
    private(set) var viewMode: ViewMode

    let sidebar = SidebarController()
    let locationBar = LocationBar()
    let filterBar = FilterBar()
    private let footer = FooterView()
    private let progressDock = ProgressDock()
    private let modeContainer = ThemedView(fill: \.background)
    private let splitController = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem!
    private var viewModeControl: NSSegmentedControl?
    private var observers: [NSObjectProtocol] = []
    var onClose: ((BrowserWindowController) -> Void)?
    var searchPanel: SearchPanel?

    init(location: URL, selecting: [URL] = []) {
        let preferences = Preferences.shared
        viewMode = preferences.viewMode
        mode = Self.makeMode(viewMode)
        history = NavigationHistory(start: location.canonical)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.minSize = NSSize(width: 720, height: 420)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .preferred
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(window)
        buildToolbar(window)
        mode.host = self
        installMode()
        observe()
        show(location.canonical, selecting: selecting)
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    static func makeMode(_ mode: ViewMode) -> BrowserMode {
        switch mode {
        case .columns: ColumnsMode()
        case .icons: IconsMode()
        case .list: ListMode()
        }
    }

    var activeDirectory: URL { mode.activeDirectory }
    var selectedEntries: [FileEntry] { mode.selectedEntries }

    // MARK: Building

    private func buildContent(_ window: NSWindow) {
        sidebar.delegate = self
        locationBar.delegate = self
        filterBar.delegate = self
        filterBar.isHidden = true

        let pane = NSViewController()
        let paneView = ThemedView(fill: \.background)
        let stack = NSStackView(views: [filterBar, modeContainer, progressDock, footer])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [filterBar, modeContainer, progressDock, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        modeContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        paneView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: paneView.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: paneView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: paneView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: paneView.trailingAnchor),
        ])
        pane.view = paneView
        footer.isHidden = !Preferences.shared.showFooter

        sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 190
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        let paneItem = NSSplitViewItem(viewController: pane)
        paneItem.minimumThickness = 420
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(paneItem)
        splitController.splitView.dividerStyle = .thin
        splitController.splitView.autosaveName = "StrataSidebar"
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1240, height: 760))
        splitController.splitView.setPosition(230, ofDividerAt: 0)
    }

    private func installMode() {
        modeContainer.subviews.forEach { $0.removeFromSuperview() }
        let view = mode.view
        view.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
        ])
        mode.setPreviewVisible(Preferences.shared.showPreview)
        viewModeControl?.selectedSegment = ViewMode.allCases.firstIndex(of: viewMode) ?? 0
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] note in
                let key = note.userInfo?["key"] as? String
                MainActor.assumeIsolated { self?.preferenceDidChange(key) }
            })
        observers.append(
            center.addObserver(forName: Appearance.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyAppearance() }
            })
        observers.append(
            center.addObserver(forName: FileClipboard.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFooter() }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.updateFooter() }
            })
    }

    private func preferenceDidChange(_ key: String?) {
        switch key {
        case Preferences.Key.showFooter:
            footer.isHidden = !Preferences.shared.showFooter
        case Preferences.Key.showPreview:
            mode.setPreviewVisible(Preferences.shared.showPreview)
        case Preferences.Key.showHidden:
            updateFooter()
        default:
            break
        }
    }

    private func applyAppearance() {
        window?.appearance = Appearance.shared.palette.appearance
        window?.backgroundColor = Appearance.shared.palette.background
    }

    // MARK: Navigation

    /// Opens `url` as the current location. A file opens its folder with the
    /// file selected; a network URL is handed to macOS to mount.
    func navigate(to url: URL, selecting: [URL] = [], recordHistory: Bool = true) {
        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let url = url.canonical
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            Alerts.showError(
                tr("That location does not exist."), window: window)
            return
        }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
        if !isDirectory.boolValue || isPackage {
            navigate(to: url.deletingLastPathComponent(), selecting: [url], recordHistory: recordHistory)
            return
        }
        if recordHistory { history.visit(url) } else { history.replaceCurrent(with: url) }
        show(url, selecting: selecting)
    }

    private func show(_ url: URL, selecting: [URL]) {
        closeFilter(refocus: false)
        mode.show(url, selecting: selecting)
        mode.focus()
        updateChrome()
    }

    func goBack() {
        let from = history.current
        guard let target = history.goBack() else { return }
        show(target, selecting: Self.child(of: target, toward: from))
    }

    func goForward() {
        let from = history.current
        guard let target = history.goForward() else { return }
        show(target, selecting: Self.child(of: target, toward: from))
    }

    func goUp() {
        let current = activeDirectory
        let parent = current.deletingLastPathComponent().canonical
        guard parent != current else { return }
        history.visit(parent)
        show(parent, selecting: [current])
    }

    /// The direct child of `ancestor` on the way to `descendant`, as a selection.
    private static func child(of ancestor: URL, toward descendant: URL) -> [URL] {
        guard ancestor.isAncestor(of: descendant) else { return [] }
        let component = descendant.standardizedFileURL.pathComponents[ancestor.standardizedFileURL.pathComponents.count]
        return [ancestor.appendingPathComponent(component)]
    }

    func setViewMode(_ newMode: ViewMode) {
        guard newMode != viewMode else { return }
        let location = activeDirectory
        let selection = selectedEntries.map(\.url)
        viewMode = newMode
        Preferences.shared.viewMode = newMode
        mode = Self.makeMode(newMode)
        mode.host = self
        installMode()
        show(location, selecting: selection)
    }

    func updateChrome() {
        let directory = activeDirectory
        locationBar.show(directory)
        sidebar.showLocation(directory)
        window?.title = DirectoryTableController.displayName(directory)
        window?.representedURL = directory
        window?.toolbar?.validateVisibleItems()
        updateFooter()
        (NSApp.delegate as? AppDelegate)?.saveSession()
    }

    func updateFooter() {
        let selected = selectedEntries.count
        var parts: [String] = []
        if let clipboard = FileClipboard.shared.status { parts.append(clipboard) }
        if selected > 1 { parts.append(trCount("selected_items", selected)) }
        footer.setStatus(parts.joined(separator: "  ·  "))
        if !filterBar.isHidden {
            filterBar.setStatus(mode.isFilterIncomplete ? tr("Results may be incomplete") : "")
        }
    }

    // MARK: Filter

    func openFilter() {
        if filterBar.isHidden {
            filterBar.isHidden = false
            filterBar.clear()
        }
        filterBar.focus()
    }

    func closeFilter(refocus: Bool = true) {
        guard !filterBar.isHidden else { return }
        filterBar.clear()
        filterBar.isHidden = true
        mode.filterText = ""
        if refocus { mode.focus() }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        (NSApp.delegate as? AppDelegate)?.saveSession()
        updateFooter()
    }

    override func newWindowForTab(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openTab(at: activeDirectory, beside: self)
    }

    // MARK: Quick Look

    var quickLookItems: [URL] = []

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        quickLookItems = selectedEntries.map(\.url)
        guard !quickLookItems.isEmpty else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

extension BrowserWindowController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        quickLookItems[index] as NSURL
    }

    /// Arrow keys in the panel move the browser selection, which the panel follows.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, let responder = window?.firstResponder, !(responder is NSWindow) else {
            return false
        }
        responder.keyDown(with: event)
        quickLookItems = selectedEntries.map(\.url)
        panel.reloadData()
        return true
    }
}

// MARK: - Mode host

extension BrowserWindowController: BrowserModeHost {
    func modeDidChangeDirectory(_ url: URL, recordHistory: Bool) {
        if recordHistory { history.visit(url) } else { history.replaceCurrent(with: url) }
        if !filterBar.isHidden { closeFilter(refocus: false) }
        updateChrome()
    }

    func modeSelectionDidChange() {
        updateFooter()
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true {
            quickLookItems = selectedEntries.map(\.url)
            QLPreviewPanel.shared()?.reloadData()
        }
    }

    func modeHandleCommandKey(_ event: NSEvent) -> Bool {
        switch true {
        case Bindings.rename.matches(event): renameSelection(nil)
        case Bindings.refresh.matches(event): refresh(nil)
        case Bindings.trashForwardDelete.matches(event): moveToTrash(nil)
        case Bindings.deletePermanentlyForwardDelete.matches(event): deletePermanently(nil)
        case Bindings.copyPathPlain.matches(event): copyPath(nil)
        case Bindings.pinPlain.matches(event): togglePin(nil)
        case Bindings.filterSlash.matches(event): openFilter()
        case Bindings.propertiesEnter.matches(event): showProperties(nil)
        case Bindings.historyBackAlt.matches(event): goBack()
        case Bindings.historyForwardAlt.matches(event): goForward()
        case Bindings.parentAlt.matches(event): goUp()
        case Bindings.homeAlt.matches(event): navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        case Bindings.openInNewTab.matches(event): openInNewTab(nil)
        case Bindings.openInNewWindow.matches(event): openInNewWindow(nil)
        default: return false
        }
        return true
    }

    func modeOpen(_ entries: [FileEntry]) {
        guard !entries.isEmpty else { return }
        if entries.count == 1, let entry = entries.first, entry.isFolder {
            navigate(to: entry.url)
            return
        }
        let files = entries.filter { !$0.isFolder }.map(\.url)
        for url in files {
            NSWorkspace.shared.open(url)
        }
        for folder in entries.filter(\.isFolder) {
            (NSApp.delegate as? AppDelegate)?.openTab(at: folder.url, beside: self)
        }
    }

    func modeNavigateUp() { goUp() }

    func modeContextMenu(for entries: [FileEntry], in directory: URL) -> NSMenu {
        contextMenu(for: entries, in: directory)
    }

    func modeDirectoryVanished(_ url: URL) {
        var parent = url.deletingLastPathComponent()
        while parent.path != "/", !FileManager.default.fileExists(atPath: parent.path) {
            parent.deleteLastPathComponent()
        }
        navigate(to: parent, recordHistory: false)
    }

    func modeQuickLook() { toggleQuickLook() }
}

// MARK: - Sidebar, location bar, filter

extension BrowserWindowController: SidebarDelegate, LocationBarDelegate, FilterBarDelegate {
    func sidebar(_ sidebar: SidebarController, navigateTo url: URL, newTab: Bool) {
        if newTab {
            (NSApp.delegate as? AppDelegate)?.openTab(at: url, beside: self)
        } else {
            navigate(to: url)
        }
    }

    func sidebarDidFinish(_ sidebar: SidebarController) { mode.focus() }

    func sidebarShowProperties(of url: URL) {
        PropertiesWindowController.show(for: url)
    }

    func locationBar(_ bar: LocationBar, navigateTo url: URL) {
        navigate(to: url)
    }

    func locationBarDidEndEditing(_ bar: LocationBar) {
        mode.focus()
    }

    func filterBar(_ bar: FilterBar, didChange text: String) {
        mode.filterText = text
        updateFooter()
    }

    func filterBarDidCancel(_ bar: FilterBar) {
        closeFilter()
    }

    func filterBarMoveDown(_ bar: FilterBar) {
        mode.focus()
    }
}

// MARK: - Toolbar

extension NSToolbarItem.Identifier {
    static let strataNavigation = Self("strata.navigation")
    static let strataLocation = Self("strata.location")
    static let strataViewMode = Self("strata.viewMode")
    static let strataSearch = Self("strata.search")
    static let strataPreview = Self("strata.preview")
}

extension BrowserWindowController: NSToolbarDelegate {
    fileprivate func buildToolbar(_ window: NSWindow) {
        let toolbar = NSToolbar(identifier: "StrataBrowser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator, .strataNavigation, .strataLocation, .flexibleSpace,
            .strataViewMode, .strataPreview, .strataSearch,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .strataNavigation:
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: [IconProvider.symbol("chevron.left")!, IconProvider.symbol("chevron.right")!],
                selectionMode: .momentary, labels: [tr("Back"), tr("Forward")],
                target: self, action: #selector(navigationClicked(_:))
            )
            group.controlRepresentation = .expanded
            group.isNavigational = true
            group.subitems[0].toolTip = tr("Back")
            group.subitems[1].toolTip = tr("Forward")
            return group
        case .strataLocation:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = locationBar
            item.label = tr("Location")
            item.visibilityPriority = .high
            return item
        case .strataViewMode:
            let control = NSSegmentedControl(
                images: [
                    IconProvider.symbol("rectangle.split.3x1")!, IconProvider.symbol("square.grid.2x2")!,
                    IconProvider.symbol("list.bullet")!,
                ],
                trackingMode: .selectOne, target: self, action: #selector(viewModeClicked(_:))
            )
            for (index, label) in [tr("Columns"), tr("Icons"), tr("List")].enumerated() {
                control.setToolTip(label, forSegment: index)
                control.setLabel("", forSegment: index)
            }
            control.selectedSegment = ViewMode.allCases.firstIndex(of: viewMode) ?? 0
            viewModeControl = control
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = control
            item.label = tr("View")
            return item
        case .strataSearch:
            return button(identifier, symbol: "magnifyingglass", label: tr("Search"), action: #selector(showSearch(_:)))
        case .strataPreview:
            return button(
                identifier, symbol: "sidebar.right", label: tr("Preview"), action: #selector(togglePreview(_:)))
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, symbol: String, label: String, action: Selector)
        -> NSToolbarItem
    {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = IconProvider.symbol(symbol)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    @objc private func navigationClicked(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { goBack() } else { goForward() }
    }

    @objc private func viewModeClicked(_ sender: NSSegmentedControl) {
        setViewMode(ViewMode.allCases[sender.selectedSegment])
    }
}
