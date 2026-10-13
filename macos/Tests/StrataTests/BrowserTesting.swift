// SPDX-License-Identifier: MIT

import AppKit
import Carbon.HIToolbox
import Foundation
import StrataCore
import Testing

@testable import Strata

struct TimedOut: Error {}

/// Lets main-actor work and run-loop timers proceed until `condition` holds.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw TimedOut() }
        runTimers()
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// Fires due run-loop timers, which the test runner's main thread does not service.
@MainActor
private func runTimers() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
}

/// All app tests share preferences and the main actor, so they run one at a time.
@MainActor
@Suite(.serialized)
enum AppTests {}

func temporaryTree(_ files: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("strata-app-tests-\(UUID().uuidString)")
    for file in files {
        let url = root.appendingPathComponent(file)
        if file.hasSuffix("/") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.utf8).write(to: url)
        }
    }
    return root.resolvingSymlinksInPath().canonical
}

/// A key press as the window server would deliver it.
@MainActor
func keyEvent(
    keyCode: Int, characters: String, modifiers: NSEvent.ModifierFlags = [], window: NSWindow? = nil
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
    )!
}

@MainActor
func arrow(_ code: Int) -> NSEvent {
    let scalar =
        switch code {
        case kVK_LeftArrow: NSLeftArrowFunctionKey
        case kVK_RightArrow: NSRightArrowFunctionKey
        case kVK_UpArrow: NSUpArrowFunctionKey
        default: NSDownArrowFunctionKey
        }
    return keyEvent(keyCode: code, characters: String(Character(UnicodeScalar(scalar)!)))
}

/// Opens an offscreen browser window in `mode` and waits for its listing.
@MainActor
func openBrowser(at root: URL, mode: ViewMode) async throws -> BrowserWindowController {
    _ = NSApplication.shared
    let preferences = Preferences.shared
    preferences.viewMode = mode
    preferences.showHidden = false
    preferences.filterIncludesSubfolders = false
    preferences.sortOrder = .init()
    let controller = BrowserWindowController(location: root)
    try await waitUntil {
        controller.window?.firstResponder is NSTableView
            || controller.window?.firstResponder is NSCollectionView
    }
    return controller
}

/// Selects every listed item and returns the selection.
@MainActor
func selectingAll(in controller: BrowserWindowController) -> [FileEntry] {
    controller.selectAll(nil)
    return controller.selectedEntries
}

/// Sends a key to whatever the browser window focuses.
@MainActor
func press(_ event: NSEvent, in controller: BrowserWindowController) {
    controller.window?.firstResponder?.keyDown(with: event)
}
