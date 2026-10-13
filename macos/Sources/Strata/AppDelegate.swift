// SPDX-License-Identifier: MIT

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [BrowserWindowController] = []
    private var isTerminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = Appearance.shared
        NSApp.mainMenu = MainMenu.build()
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = VolumeMonitor.shared
        if controllers.isEmpty {
            openInitialWindows()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openWindow(at: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, controllers.isEmpty { openWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveSession()
        isTerminating = true
        return .terminateNow
    }

    // MARK: Windows

    private func openInitialWindows() {
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let path = arguments.first {
            openWindow(at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return
        }
        let session = Preferences.shared.session
        let tabs = session.tabs.filter(Self.isRestorable)
        guard Preferences.shared.restoreTabs, let first = tabs.first else {
            openWindow(at: FileManager.default.homeDirectoryForCurrentUser)
            return
        }
        let leader = openWindow(at: first)
        var opened = [leader]
        for url in tabs.dropFirst() {
            opened.append(openTab(at: url, beside: leader))
        }
        let active = opened.indices.contains(session.active) ? opened[session.active] : leader
        active.window?.makeKeyAndOrderFront(nil)
    }

    private static func isRestorable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue && !url.standardizedFileURL.path.hasPrefix(trash.path)
    }

    @discardableResult
    func openWindow(at url: URL, selecting: [URL] = []) -> BrowserWindowController {
        let controller = makeController(at: url, selecting: selecting)
        if let key = NSApp.keyWindow, let window = controller.window {
            window.setFrame(key.frame.offsetBy(dx: 24, dy: -24), display: false)
        } else {
            controller.window?.center()
        }
        controller.window?.tabbingMode = .disallowed
        controller.showWindow(nil)
        controller.window?.tabbingMode = .preferred
        return controller
    }

    @discardableResult
    func openTab(at url: URL, beside existing: BrowserWindowController, selecting: [URL] = [])
        -> BrowserWindowController
    {
        let controller = makeController(at: url, selecting: selecting)
        if let window = controller.window, let host = existing.window {
            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        } else {
            controller.showWindow(nil)
        }
        return controller
    }

    private func makeController(at url: URL, selecting: [URL]) -> BrowserWindowController {
        var location = url.canonical
        var selection = selecting
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            selection = [location]
            location = location.deletingLastPathComponent()
        }
        let controller = BrowserWindowController(location: location, selecting: selection)
        controller.onClose = { [weak self] closed in
            guard let self else { return }
            self.controllers.removeAll { $0 === closed }
            if !self.isTerminating, !self.controllers.isEmpty { self.saveSession() }
        }
        controllers.append(controller)
        return controller
    }

    /// Saves the key window's tabs in strip order for the next plain launch.
    func saveSession() {
        guard !isTerminating, Preferences.shared.restoreTabs else { return }
        let key = controllers.first { $0.window?.isKeyWindow == true } ?? controllers.last
        guard let key, let window = key.window else { return }
        let windows = window.tabbedWindows ?? [window]
        let tabs = windows.compactMap { tab in controllers.first { $0.window === tab } }
        let locations = tabs.map(\.activeDirectory).filter(Self.isRestorable)
        guard !locations.isEmpty else { return }
        let active = tabs.firstIndex { $0 === key } ?? 0
        Preferences.shared.session = (locations, min(active, locations.count - 1))
    }

    // MARK: App commands

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc func showShortcutReference(_ sender: Any?) {
        ShortcutReference.shared.toggle()
    }

    @objc func newBrowserWindow(_ sender: Any?) {
        let current = controllers.first { $0.window?.isKeyWindow == true }
        openWindow(at: current?.activeDirectory ?? FileManager.default.homeDirectoryForCurrentUser)
    }

    @objc func newBrowserTab(_ sender: Any?) {
        guard let current = controllers.first(where: { $0.window?.isKeyWindow == true }) ?? controllers.last else {
            openWindow(at: FileManager.default.homeDirectoryForCurrentUser)
            return
        }
        openTab(at: current.activeDirectory, beside: current)
    }

    @objc func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Strata",
            .applicationVersion: version,
            .credits: NSAttributedString(string: tr("Navigate every layer.")),
        ])
    }
}
