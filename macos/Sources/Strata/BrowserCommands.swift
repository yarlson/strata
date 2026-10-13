// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Commands reachable from the menu bar, context menus, and keyboard.
extension BrowserWindowController: NSMenuItemValidation {
    private var selectionURLs: [URL] { selectedEntries.map(\.url) }

    // MARK: Opening

    @objc func openSelection(_ sender: Any?) {
        modeOpen(selectedEntries)
    }

    @objc func openInNewTab(_ sender: Any?) {
        let folders = selectedEntries.filter(\.isFolder).map(\.url)
        let targets = folders.isEmpty ? [activeDirectory] : folders
        for folder in targets {
            (NSApp.delegate as? AppDelegate)?.openTab(at: folder, beside: self)
        }
    }

    @objc func openInNewWindow(_ sender: Any?) {
        let folder = selectedEntries.first(where: \.isFolder)?.url ?? activeDirectory
        (NSApp.delegate as? AppDelegate)?.openWindow(at: folder)
    }

    @objc func quickLook(_ sender: Any?) {
        toggleQuickLook()
    }

    @objc func openTerminal(_ sender: Any?) {
        let folder =
            selectedEntries.count == 1 && selectedEntries[0].isFolder ? selectedEntries[0].url : activeDirectory
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func revealInFinder(_ sender: Any?) {
        let urls = selectionURLs
        if urls.isEmpty {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeDirectory.path)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: Editing

    @objc func renameSelection(_ sender: Any?) {
        guard selectedEntries.count == 1, let entry = selectedEntries.first else { return }
        mode.beginRename(entry.url)
    }

    @objc func duplicateSelection(_ sender: Any?) {
        let urls = selectionURLs
        guard !urls.isEmpty else { return }
        FileOperationCenter.shared.transfer(urls, to: activeDirectory, mode: .duplicate, window: window) {
            [weak self] created in
            self?.mode.select(created)
        }
    }

    @objc func compressSelection(_ sender: Any?) {
        FileOperationCenter.shared.compress(selectionURLs, window: window) { [weak self] archive in
            self?.mode.select([archive])
        }
    }

    @objc func newFolder(_ sender: Any?) {
        createItem(folder: true)
    }

    @objc func newFile(_ sender: Any?) {
        createItem(folder: false)
    }

    private func createItem(folder: Bool) {
        closeFilter(refocus: false)
        guard let url = FileOperationCenter.shared.create(folder: folder, in: activeDirectory, window: window) else {
            return
        }
        mode.beginRename(url)
    }

    @objc func newFolderWithSelection(_ sender: Any?) {
        let urls = selectionURLs
        guard !urls.isEmpty else {
            newFolder(sender)
            return
        }
        closeFilter(refocus: false)
        guard
            let folder = FileOperationCenter.shared.createFolder(containing: urls, in: activeDirectory, window: window)
        else { return }
        mode.beginRename(folder)
    }

    @objc func copy(_ sender: Any?) {
        FileClipboard.shared.copy(selectionURLs)
    }

    @objc func cut(_ sender: Any?) {
        FileClipboard.shared.cut(selectionURLs)
    }

    @objc func paste(_ sender: Any?) {
        pasteInto(activeDirectory)
    }

    private func pasteInto(_ directory: URL) {
        FileClipboard.shared.paste(into: directory, window: window) { [weak self] pasted in
            guard let self, directory == self.activeDirectory else { return }
            self.mode.select(pasted)
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        mode.selectAll()
    }

    @objc func moveToTrash(_ sender: Any?) {
        let urls = selectionURLs
        guard !urls.isEmpty else { return }
        FileOperationCenter.shared.trash(urls, window: window, undoManager: window?.undoManager)
    }

    @objc func deletePermanently(_ sender: Any?) {
        FileOperationCenter.shared.confirmDelete(selectionURLs, window: window)
    }

    @objc func copyPath(_ sender: Any?) {
        let urls = selectionURLs.isEmpty ? [activeDirectory] : selectionURLs
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    @objc func togglePin(_ sender: Any?) {
        let folders = selectedEntries.filter(\.isFolder).map(\.url)
        for folder in folders.isEmpty ? [activeDirectory] : folders {
            Preferences.shared.togglePin(folder)
        }
    }

    @objc func showProperties(_ sender: Any?) {
        let urls = selectionURLs.isEmpty ? [activeDirectory] : selectionURLs
        for url in urls.prefix(8) {
            PropertiesWindowController.show(for: url)
        }
    }

    // MARK: View

    @objc func refresh(_ sender: Any?) {
        mode.reload()
        VolumeMonitor.shared.refresh()
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        Preferences.shared.showHidden.toggle()
    }

    @objc func viewAsColumns(_ sender: Any?) { setViewMode(.columns) }
    @objc func viewAsIcons(_ sender: Any?) { setViewMode(.icons) }
    @objc func viewAsList(_ sender: Any?) { setViewMode(.list) }

    @objc func togglePreview(_ sender: Any?) {
        Preferences.shared.showPreview.toggle()
    }

    @objc func toggleFooter(_ sender: Any?) {
        Preferences.shared.showFooter.toggle()
    }

    @objc func textLarger(_ sender: Any?) {
        Preferences.shared.textSize += 1
    }

    @objc func textSmaller(_ sender: Any?) {
        Preferences.shared.textSize -= 1
    }

    @objc func textReset(_ sender: Any?) {
        Preferences.shared.textSize = Preferences.defaultTextSize
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard let key = (sender.representedObject as? String).flatMap(SortKey.init) else { return }
        var order = Preferences.shared.sortOrder
        order.key = key
        Preferences.shared.sortOrder = order
    }

    @objc func sortAscending(_ sender: NSMenuItem) {
        var order = Preferences.shared.sortOrder
        order.ascending = sender.tag == 1
        Preferences.shared.sortOrder = order
    }

    @objc func toggleStrataSidebar(_ sender: Any?) {
        splitViewItemForSidebar?.animator().isCollapsed.toggle()
    }

    @objc func focusSidebar(_ sender: Any?) {
        splitViewItemForSidebar?.isCollapsed = false
        sidebar.focus()
    }

    private var splitViewItemForSidebar: NSSplitViewItem? {
        (window?.contentViewController as? NSSplitViewController)?.splitViewItems.first
    }

    // MARK: Go

    @objc func goBackAction(_ sender: Any?) { goBack() }
    @objc func goForwardAction(_ sender: Any?) { goForward() }
    @objc func goUpAction(_ sender: Any?) { goUp() }

    @objc func goToPlace(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        navigate(to: url)
    }

    @objc func focusLocation(_ sender: Any?) {
        locationBar.beginEditing()
    }

    @objc func showFilter(_ sender: Any?) {
        openFilter()
    }

    @objc func showSearch(_ sender: Any?) {
        presentSearch(foldersOnly: false)
    }

    @objc func showJumpToFolder(_ sender: Any?) {
        presentSearch(foldersOnly: true)
    }

    private func presentSearch(foldersOnly: Bool) {
        guard let window, window.attachedSheet == nil, !mode.isRenaming else { return }
        let panel = SearchPanel(foldersOnly: foldersOnly) { [weak self] choice in
            guard let self else { return }
            switch choice {
            case let .reveal(url):
                self.navigate(to: url)
            case let .open(url):
                NSWorkspace.shared.open(url)
            case let .newTab(url):
                let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                (NSApp.delegate as? AppDelegate)?.openTab(
                    at: folder, beside: self, selecting: url.hasDirectoryPath ? [] : [url])
            }
        }
        searchPanel = panel
        panel.present(over: window)
    }

    // MARK: Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = !selectedEntries.isEmpty
        let preferences = Preferences.shared
        switch item.action {
        case #selector(openSelection(_:)), #selector(quickLook(_:)), #selector(duplicateSelection(_:)),
            #selector(compressSelection(_:)), #selector(copy(_:)), #selector(cut(_:)),
            #selector(moveToTrash(_:)), #selector(deletePermanently(_:)):
            return hasSelection
        case #selector(renameSelection(_:)):
            return selectedEntries.count == 1
        case #selector(paste(_:)):
            return !FileClipboard.shared.urls.isEmpty
        case #selector(goBackAction(_:)):
            return history.canGoBack
        case #selector(goForwardAction(_:)):
            return history.canGoForward
        case #selector(goUpAction(_:)):
            return activeDirectory.path != "/"
        case #selector(toggleHiddenFiles(_:)):
            item.state = preferences.showHidden ? .on : .off
        case #selector(togglePreview(_:)):
            item.state = preferences.showPreview ? .on : .off
        case #selector(toggleFooter(_:)):
            item.state = preferences.showFooter ? .on : .off
        case #selector(viewAsColumns(_:)):
            item.state = viewMode == .columns ? .on : .off
        case #selector(viewAsIcons(_:)):
            item.state = viewMode == .icons ? .on : .off
        case #selector(viewAsList(_:)):
            item.state = viewMode == .list ? .on : .off
        case #selector(sortBy(_:)):
            item.state = preferences.sortOrder.key.rawValue == item.representedObject as? String ? .on : .off
        case #selector(sortAscending(_:)):
            item.state = preferences.sortOrder.ascending == (item.tag == 1) ? .on : .off
        case #selector(togglePin(_:)):
            let folder = selectedEntries.first(where: \.isFolder)?.url ?? activeDirectory
            item.title = preferences.isPinned(folder) ? tr("Unpin") : tr("Pin")
        default:
            break
        }
        return true
    }

    // MARK: Context menu

    func contextMenu(for entries: [FileEntry], in directory: URL) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true
        func add(_ title: String, _ action: Selector, _ binding: KeyBinding? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: binding?.menuKeyEquivalent ?? "")
            item.keyEquivalentModifierMask = binding?.modifiers ?? []
            item.target = self
            menu.addItem(item)
        }
        guard !entries.isEmpty else {
            add(tr("New Folder"), #selector(newFolder(_:)), Bindings.newFolder)
            add(tr("New File"), #selector(newFile(_:)), Bindings.newFile)
            add(tr("Paste"), #selector(paste(_:)), Bindings.paste)
            menu.addItem(.separator())
            add(tr("Open in Terminal"), #selector(openTerminal(_:)), Bindings.terminal)
            add(tr("Refresh"), #selector(refresh(_:)), Bindings.refresh)
            add(tr("Show hidden files"), #selector(toggleHiddenFiles(_:)), Bindings.hiddenFiles)
            menu.addItem(sortMenuItem())
            menu.addItem(.separator())
            add(tr("Pin"), #selector(togglePin(_:)), Bindings.pin)
            add(tr("Properties"), #selector(showProperties(_:)), Bindings.properties)
            return menu
        }
        add(tr("Open"), #selector(openSelection(_:)), Bindings.open)
        if entries.count == 1, !entries[0].isFolder {
            menu.addItem(openWithMenuItem(for: entries[0].url))
        }
        if entries.contains(where: \.isFolder) {
            add(tr("Open in New Tab"), #selector(openInNewTab(_:)), Bindings.openInNewTab)
        }
        add(tr("Quick preview"), #selector(quickLook(_:)), Bindings.quickLook)
        menu.addItem(.separator())
        if entries.count == 1 { add(tr("Rename"), #selector(renameSelection(_:)), Bindings.rename) }
        add(tr("Duplicate"), #selector(duplicateSelection(_:)), Bindings.duplicate)
        add(tr("Compress"), #selector(compressSelection(_:)))
        add(tr("New Folder with Selection"), #selector(newFolderWithSelection(_:)), Bindings.newFolderWithSelection)
        menu.addItem(.separator())
        add(tr("Cut"), #selector(cut(_:)), Bindings.cut)
        add(tr("Copy"), #selector(copy(_:)), Bindings.copy)
        add(tr("Copy path"), #selector(copyPath(_:)), Bindings.copyPath)
        if entries.count == 1, entries[0].isFolder, !FileClipboard.shared.urls.isEmpty {
            let folder = entries[0].url
            menu.addItem(ClosureMenuItem(title: tr("Paste Into Folder")) { [weak self] in self?.pasteInto(folder) })
        }
        menu.addItem(.separator())
        if entries.allSatisfy(\.isFolder) {
            add(tr("Pin"), #selector(togglePin(_:)), Bindings.pin)
            if entries.count == 1 { add(tr("Open in Terminal"), #selector(openTerminal(_:)), Bindings.terminal) }
        }
        add(tr("Show in Finder"), #selector(revealInFinder(_:)))
        menu.addItem(.separator())
        add(tr("Move to Trash"), #selector(moveToTrash(_:)), Bindings.trash)
        add(tr("Delete Permanently"), #selector(deletePermanently(_:)), Bindings.deletePermanently)
        menu.addItem(.separator())
        add(tr("Properties"), #selector(showProperties(_:)), Bindings.properties)
        return menu
    }

    func sortMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: tr("Sort by"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let keys: [(SortKey, String)] = [
            (.name, tr("Name")), (.size, tr("Size")), (.kind, tr("Type")), (.modified, tr("Modified")),
        ]
        for (key, title) in keys {
            let entry = NSMenuItem(title: title, action: #selector(sortBy(_:)), keyEquivalent: "")
            entry.representedObject = key.rawValue
            entry.target = self
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        for (tag, title) in [(1, tr("Ascending")), (0, tr("Descending"))] {
            let entry = NSMenuItem(title: title, action: #selector(sortAscending(_:)), keyEquivalent: "")
            entry.tag = tag
            entry.target = self
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    /// Applications that can open `url`, the default first, then Other….
    func openWithMenuItem(for url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: tr("Open With"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let workspace = NSWorkspace.shared
        let defaultApp = workspace.urlForApplication(toOpen: url)
        var apps = workspace.urlsForApplications(toOpen: url)
        if let defaultApp {
            apps.removeAll { $0 == defaultApp }
            apps.insert(defaultApp, at: 0)
        }
        var seen = Set<String>()
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path)
            guard seen.insert(name).inserted else { continue }
            let title = app == defaultApp ? tr("%{app} (default)", ["app": name]) : name
            let entry = ClosureMenuItem(title: title) {
                workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            submenu.addItem(entry)
            if app == defaultApp, apps.count > 1 { submenu.addItem(.separator()) }
        }
        submenu.addItem(.separator())
        submenu.addItem(
            ClosureMenuItem(title: tr("Other…")) { [weak self] in
                let panel = NSOpenPanel()
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.allowedContentTypes = [.application]
                panel.canChooseDirectories = false
                guard let window = self?.window else { return }
                panel.beginSheetModal(for: window) { response in
                    guard response == .OK, let app = panel.url else { return }
                    workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            })
        item.submenu = submenu
        return item
    }
}
