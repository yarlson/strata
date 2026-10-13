// SPDX-License-Identifier: MIT

import AppKit
import Carbon.HIToolbox
import StrataCore
import Testing

@testable import Strata

extension AppTests {
    @MainActor
    @Suite
    struct FileCommandTests {
        /// A private pasteboard so tests never replace the user's clipboard.
        private func clipboard() -> (FileClipboard, NSPasteboard) {
            let pasteboard = NSPasteboard(name: .init("strata-tests-\(UUID().uuidString)"))
            return (FileClipboard(pasteboard: pasteboard), pasteboard)
        }

        private func paste(_ clipboard: FileClipboard, into directory: URL) async throws -> [URL] {
            var pasted: [URL]?
            clipboard.paste(into: directory, window: nil) { pasted = $0 }
            try await waitUntil { pasted != nil }
            return pasted ?? []
        }

        @Test func copiedItemsPasteAsCopiesAndStayOnTheClipboard() async throws {
            let root = try temporaryTree(["a.txt", "target/"])
            defer { try? FileManager.default.removeItem(at: root) }
            let (clipboard, pasteboard) = clipboard()
            defer { pasteboard.releaseGlobally() }
            let source = root.appendingPathComponent("a.txt").canonical

            clipboard.copy([source])
            let pasted = try await paste(clipboard, into: root.appendingPathComponent("target").canonical)

            #expect(pasted == [root.appendingPathComponent("target/a.txt").canonical])
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(clipboard.urls == [source])
            #expect(!clipboard.isCut)
        }

        @Test func pastingACopyIntoItsOwnFolderKeepsBoth() async throws {
            let root = try temporaryTree(["a.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let (clipboard, pasteboard) = clipboard()
            defer { pasteboard.releaseGlobally() }

            clipboard.copy([root.appendingPathComponent("a.txt").canonical])
            let pasted = try await paste(clipboard, into: root)

            #expect(pasted.map(\.lastPathComponent) == ["a (1).txt"])
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == [
                    "a (1).txt", "a.txt",
                ])
        }

        @Test func cutItemsMoveOnPasteAndLeaveTheClipboardEmpty() async throws {
            let root = try temporaryTree(["a.txt", "target/"])
            defer { try? FileManager.default.removeItem(at: root) }
            let (clipboard, pasteboard) = clipboard()
            defer { pasteboard.releaseGlobally() }
            let source = root.appendingPathComponent("a.txt").canonical

            clipboard.cut([source])
            #expect(clipboard.isCut)
            let pasted = try await paste(clipboard, into: root.appendingPathComponent("target").canonical)

            #expect(pasted == [root.appendingPathComponent("target/a.txt").canonical])
            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(clipboard.urls.isEmpty)
        }

        @Test func undoReversesARenameAndRedoRepeatsIt() async throws {
            let root = try temporaryTree(["draft.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .list)
            let undoManager = try #require(browser.window?.undoManager)

            let renamed = FileOperationCenter.shared.rename(
                root.appendingPathComponent("draft.txt").canonical, to: "final.txt", window: browser.window)
            #expect(renamed?.lastPathComponent == "final.txt")

            undoManager.undo()
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["draft.txt"])
            undoManager.redo()
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["final.txt"])
        }

        @Test func newFolderTakesTheFirstFreeNameAndStartsRenaming() async throws {
            let root = try temporaryTree(["new folder/"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .list)

            browser.newFolder(nil)

            try await waitUntil { browser.mode.isRenaming }
            #expect(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("new folder (1)").canonical.path))
            #expect(browser.selectedEntries.map(\.name) == ["new folder (1)"])
        }
    }

    @MainActor
    struct KeyBindingTests {
        @Test func lettersMatchTheLatinKeyOnNonLatinLayouts() {
            let cyrillicC = keyEvent(keyCode: kVK_ANSI_C, characters: "с", modifiers: .command)
            #expect(Bindings.copy.matches(cyrillicC))
            #expect(!Bindings.cut.matches(cyrillicC))
        }

        @Test func digitsMatchTheirTopRowPosition() {
            let azertyOne = keyEvent(keyCode: kVK_ANSI_1, characters: "&", modifiers: .command)
            #expect(Bindings.viewColumns.matches(azertyOne))
        }

        @Test func modifiersMustMatchExactly() {
            let plainC = keyEvent(keyCode: kVK_ANSI_C, characters: "c")
            let shiftCommandN = keyEvent(
                keyCode: kVK_ANSI_N, characters: "N", modifiers: [.command, .shift])
            #expect(!Bindings.copy.matches(plainC))
            #expect(Bindings.newFolder.matches(shiftCommandN))
            #expect(!Bindings.newWindow.matches(shiftCommandN))
        }

        @Test func labelsUseMacSymbolsInMenuOrder() {
            #expect(Bindings.newFolderWithSelection.label == "⌃⌘N")
            #expect(Bindings.deletePermanently.label == "⌥⌘⌫")
        }
    }
}
