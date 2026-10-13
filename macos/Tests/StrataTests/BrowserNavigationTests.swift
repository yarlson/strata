// SPDX-License-Identifier: MIT

import AppKit
import Carbon.HIToolbox
import StrataCore
import Testing

@testable import Strata

extension AppTests {
    @MainActor
    @Suite
    struct BrowserNavigationTests {
        @Test func columnsRightOpensTheSelectedFolderAndLeftReturnsToIt() async throws {
            let root = try temporaryTree(["alpha/inner.txt", "beta.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .columns)
            let alpha = root.appendingPathComponent("alpha").canonical
            browser.mode.select([alpha])
            try await waitUntil { browser.selectedEntries.map(\.url) == [alpha] }

            press(arrow(kVK_RightArrow), in: browser)
            try await waitUntil {
                browser.activeDirectory == alpha && browser.selectedEntries.first?.name == "inner.txt"
            }

            press(arrow(kVK_LeftArrow), in: browser)
            #expect(browser.activeDirectory == root)
            #expect(browser.selectedEntries.map(\.url) == [alpha])
        }

        @Test func columnsBackspaceInTheFirstColumnOpensTheParentWithTheFolderSelected() async throws {
            let root = try temporaryTree(["child/file.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let child = root.appendingPathComponent("child").canonical
            let browser = try await openBrowser(at: child, mode: .columns)

            press(keyEvent(keyCode: kVK_Delete, characters: "\u{8}"), in: browser)

            try await waitUntil {
                browser.activeDirectory == root && browser.selectedEntries.map(\.url) == [child]
            }
            #expect(browser.history.canGoBack)
        }

        @Test func listEnterOpensAFolderAndBackSelectsTheFolderLeft() async throws {
            let root = try temporaryTree(["docs/readme.md", "notes.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let docs = root.appendingPathComponent("docs").canonical
            let browser = try await openBrowser(at: root, mode: .list)
            browser.mode.select([docs])
            try await waitUntil { browser.selectedEntries.map(\.url) == [docs] }

            press(keyEvent(keyCode: kVK_Return, characters: "\r"), in: browser)
            try await waitUntil { browser.activeDirectory == docs }
            browser.goBack()

            try await waitUntil {
                browser.activeDirectory == root && browser.selectedEntries.map(\.url) == [docs]
            }
            #expect(browser.history.canGoForward)
        }

        @Test func vimKeysMoveTheCursorLikeArrows() async throws {
            let root = try temporaryTree(["a.txt", "b.txt", "c.txt"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .list)
            browser.mode.select([root.appendingPathComponent("a.txt").canonical])
            try await waitUntil { browser.selectedEntries.count == 1 }

            press(keyEvent(keyCode: kVK_ANSI_J, characters: "j"), in: browser)
            press(keyEvent(keyCode: kVK_ANSI_J, characters: "j"), in: browser)
            press(keyEvent(keyCode: kVK_ANSI_K, characters: "k"), in: browser)

            #expect(browser.selectedEntries.map(\.name) == ["b.txt"])
        }

        @Test func paneFilterNarrowsTheListingAndClosingItRestoresIt() async throws {
            let root = try temporaryTree(["report.pdf", "photo.jpg", "nested/report-old.pdf"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .list)
            try await waitUntil { selectingAll(in: browser).count == 3 }

            browser.openFilter()
            browser.filterBar(browser.filterBar, didChange: "REPORT")
            try await waitUntil { selectingAll(in: browser).map(\.name) == ["report.pdf"] }

            browser.closeFilter()
            try await waitUntil { selectingAll(in: browser).count == 3 }
        }

        @Test func filterIncludingSubfoldersFindsNestedMatches() async throws {
            let root = try temporaryTree(["report.pdf", "nested/report-old.pdf", "photo.jpg"])
            defer { try? FileManager.default.removeItem(at: root) }
            let browser = try await openBrowser(at: root, mode: .list)
            Preferences.shared.filterIncludesSubfolders = true
            defer { Preferences.shared.filterIncludesSubfolders = false }

            browser.openFilter()
            browser.filterBar(browser.filterBar, didChange: "report")

            try await waitUntil {
                Set(selectingAll(in: browser).map(\.name)) == ["report.pdf", "report-old.pdf"]
            }
        }
    }
}
