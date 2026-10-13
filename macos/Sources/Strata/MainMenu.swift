// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// The menu bar. Browser commands go to the key window's controller through
/// the responder chain; app commands go to the app delegate.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Strata", appMenu()))
        main.addItem(submenu(tr("File"), fileMenu()))
        main.addItem(submenu(tr("Edit"), editMenu()))
        main.addItem(submenu(tr("View"), viewMenu()))
        main.addItem(submenu(tr("Go"), goMenu()))
        let window = windowMenu()
        main.addItem(submenu(tr("Window"), window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: tr("Help"))
        help.addItem(
            item(tr("Keyboard shortcuts"), #selector(AppDelegate.showShortcutReference(_:)), Bindings.reference))
        main.addItem(submenu(tr("Help"), help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        menu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ binding: KeyBinding? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: binding?.menuKeyEquivalent ?? "")
        item.keyEquivalentModifierMask = binding?.modifiers ?? []
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(tr("About Strata"), #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item(tr("Settings…"), #selector(AppDelegate.showSettings(_:)), Bindings.settings))
        menu.addItem(.separator())
        let services = NSMenu()
        menu.addItem(submenu(tr("Services"), services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item(tr("Hide Strata"), #selector(NSApplication.hide(_:)), KeyBinding(.character("h"), .command)))
        menu.addItem(
            item(
                tr("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)),
                KeyBinding(.character("h"), [.command, .option])))
        menu.addItem(item(tr("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item(tr("Quit Strata"), #selector(NSApplication.terminate(_:)), KeyBinding(.character("q"), .command)))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(tr("New Window"), #selector(AppDelegate.newBrowserWindow(_:)), Bindings.newWindow))
        menu.addItem(item(tr("New Tab"), #selector(AppDelegate.newBrowserTab(_:)), Bindings.newTab))
        menu.addItem(.separator())
        menu.addItem(item(tr("New Folder"), #selector(BrowserWindowController.newFolder(_:)), Bindings.newFolder))
        menu.addItem(
            item(
                tr("New Folder with Selection"), #selector(BrowserWindowController.newFolderWithSelection(_:)),
                Bindings.newFolderWithSelection))
        menu.addItem(item(tr("New File"), #selector(BrowserWindowController.newFile(_:)), Bindings.newFile))
        menu.addItem(.separator())
        menu.addItem(item(tr("Open"), #selector(BrowserWindowController.openSelection(_:)), Bindings.open))
        menu.addItem(
            item(tr("Open in New Tab"), #selector(BrowserWindowController.openInNewTab(_:)), Bindings.openInNewTab))
        menu.addItem(item(tr("Quick preview"), #selector(BrowserWindowController.quickLook(_:)), Bindings.quickLook))
        menu.addItem(.separator())
        menu.addItem(item(tr("Rename"), #selector(BrowserWindowController.renameSelection(_:)), Bindings.renameCommand))
        menu.addItem(
            item(tr("Duplicate"), #selector(BrowserWindowController.duplicateSelection(_:)), Bindings.duplicate))
        menu.addItem(item(tr("Compress"), #selector(BrowserWindowController.compressSelection(_:))))
        menu.addItem(.separator())
        menu.addItem(item(tr("Copy path"), #selector(BrowserWindowController.copyPath(_:)), Bindings.copyPath))
        menu.addItem(item(tr("Pin"), #selector(BrowserWindowController.togglePin(_:)), Bindings.pin))
        menu.addItem(
            item(tr("Open in Terminal"), #selector(BrowserWindowController.openTerminal(_:)), Bindings.terminal))
        menu.addItem(item(tr("Show in Finder"), #selector(BrowserWindowController.revealInFinder(_:))))
        menu.addItem(.separator())
        menu.addItem(item(tr("Move to Trash"), #selector(BrowserWindowController.moveToTrash(_:)), Bindings.trash))
        menu.addItem(
            item(
                tr("Delete Permanently"), #selector(BrowserWindowController.deletePermanently(_:)),
                Bindings.deletePermanently))
        menu.addItem(.separator())
        menu.addItem(item(tr("Properties"), #selector(BrowserWindowController.showProperties(_:)), Bindings.properties))
        menu.addItem(.separator())
        menu.addItem(item(tr("Close tab"), #selector(NSWindow.performClose(_:)), Bindings.closeTab))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(tr("Undo"), Selector(("undo:")), Bindings.undo))
        menu.addItem(item(tr("Redo"), Selector(("redo:")), Bindings.redo))
        menu.addItem(.separator())
        menu.addItem(item(tr("Cut"), #selector(NSText.cut(_:)), Bindings.cut))
        menu.addItem(item(tr("Copy"), #selector(NSText.copy(_:)), Bindings.copy))
        menu.addItem(item(tr("Paste"), #selector(NSText.paste(_:)), Bindings.paste))
        menu.addItem(item(tr("Select All"), #selector(NSText.selectAll(_:)), Bindings.selectAll))
        menu.addItem(.separator())
        menu.addItem(item(tr("Filter"), #selector(BrowserWindowController.showFilter(_:)), Bindings.filter))
        menu.addItem(item(tr("Search"), #selector(BrowserWindowController.showSearch(_:)), Bindings.search))
        menu.addItem(
            item(
                tr("Jump to a folder…"), #selector(BrowserWindowController.showJumpToFolder(_:)), Bindings.jumpToFolder)
        )
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(tr("Columns"), #selector(BrowserWindowController.viewAsColumns(_:)), Bindings.viewColumns))
        menu.addItem(item(tr("Icons"), #selector(BrowserWindowController.viewAsIcons(_:)), Bindings.viewIcons))
        menu.addItem(item(tr("List"), #selector(BrowserWindowController.viewAsList(_:)), Bindings.viewList))
        menu.addItem(.separator())
        menu.addItem(
            item(
                tr("Show hidden files"), #selector(BrowserWindowController.toggleHiddenFiles(_:)), Bindings.hiddenFiles)
        )
        menu.addItem(item(tr("Show preview"), #selector(BrowserWindowController.togglePreview(_:)), Bindings.preview))
        menu.addItem(
            item(tr("Show sidebar"), #selector(BrowserWindowController.toggleStrataSidebar(_:)), Bindings.sidebar))
        menu.addItem(item(tr("Show shortcut footer"), #selector(BrowserWindowController.toggleFooter(_:))))
        menu.addItem(.separator())
        let sort = NSMenuItem(title: tr("Sort by"), action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for (key, title) in [
            (SortKey.name, tr("Name")), (.size, tr("Size")), (.kind, tr("Type")), (.modified, tr("Modified")),
        ] {
            let entry = item(title, #selector(BrowserWindowController.sortBy(_:)))
            entry.representedObject = key.rawValue
            sortMenu.addItem(entry)
        }
        sortMenu.addItem(.separator())
        for (tag, title) in [(1, tr("Ascending")), (0, tr("Descending"))] {
            let entry = item(title, #selector(BrowserWindowController.sortAscending(_:)))
            entry.tag = tag
            sortMenu.addItem(entry)
        }
        sort.submenu = sortMenu
        menu.addItem(sort)
        menu.addItem(.separator())
        menu.addItem(item(tr("Zoom in"), #selector(BrowserWindowController.textLarger(_:)), Bindings.textLarger))
        menu.addItem(item(tr("Zoom out"), #selector(BrowserWindowController.textSmaller(_:)), Bindings.textSmaller))
        menu.addItem(item(tr("Reset"), #selector(BrowserWindowController.textReset(_:)), Bindings.textReset))
        menu.addItem(.separator())
        menu.addItem(item(tr("Refresh"), #selector(BrowserWindowController.refresh(_:)), Bindings.refresh))
        menu.addItem(.separator())
        menu.addItem(
            item(
                tr("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)),
                KeyBinding(.character("f"), [.command, .control])))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(tr("Back"), #selector(BrowserWindowController.goBackAction(_:)), Bindings.back))
        menu.addItem(item(tr("Forward"), #selector(BrowserWindowController.goForwardAction(_:)), Bindings.forward))
        menu.addItem(
            item(
                tr("Go to the parent folder"), #selector(BrowserWindowController.goUpAction(_:)),
                Bindings.enclosingFolder))
        menu.addItem(.separator())
        let home = FileManager.default.homeDirectoryForCurrentUser
        let places: [(String, URL?, KeyBinding?)] = [
            (tr("Home"), home, Bindings.home),
            (
                tr("Desktop"), FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
                KeyBinding(.character("d"), [.command, .shift])
            ),
            (
                tr("Documents"), FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                KeyBinding(.character("o"), [.command, .shift])
            ),
            (
                tr("Downloads"), FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                KeyBinding(.character("l"), [.command, .option])
            ),
            (
                tr("Applications"), URL(fileURLWithPath: "/Applications"),
                KeyBinding(.character("a"), [.command, .shift])
            ),
        ]
        for (title, url, binding) in places {
            guard let url else { continue }
            let entry = item(title, #selector(BrowserWindowController.goToPlace(_:)), binding)
            entry.representedObject = url
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(
            item(tr("Go to a path or URI"), #selector(BrowserWindowController.focusLocation(_:)), Bindings.location))
        menu.addItem(
            item(tr("Focus the sidebar"), #selector(BrowserWindowController.focusSidebar(_:)), Bindings.sidebarFocus))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            item(tr("Minimize"), #selector(NSWindow.performMiniaturize(_:)), KeyBinding(.character("m"), .command)))
        menu.addItem(item(tr("Zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(tr("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
