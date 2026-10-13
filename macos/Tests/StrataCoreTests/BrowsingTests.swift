// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

struct SortOrderTests {
    private func entry(_ name: String, folder: Bool = false, size: Int64? = nil) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/x/\(name)"), name: name, isFolder: folder, size: size)
    }

    @Test func listsFoldersFirstInNaturalNameOrder() {
        let sorted = SortOrder().sorted([
            entry("file10"), entry("b", folder: true), entry("file2"), entry("A", folder: true),
        ])
        #expect(sorted.map(\.name) == ["A", "b", "file2", "file10"])
    }

    @Test func descendingSizeKeepsFoldersFirst() {
        let sorted = SortOrder(key: .size, ascending: false).sorted([
            entry("small", size: 1), entry("dir", folder: true), entry("large", size: 9),
        ])
        #expect(sorted.map(\.name) == ["dir", "large", "small"])
    }
}

struct NavigationHistoryTests {
    @Test func backAndForwardRetraceVisits() {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b"), c = URL(fileURLWithPath: "/c")
        var history = NavigationHistory(start: a)
        history.visit(b)
        history.visit(c)
        #expect(history.goBack() == b)
        #expect(history.goBack() == a)
        #expect(history.goBack() == nil)
        #expect(history.goForward() == b)
        history.visit(a)
        #expect(!history.canGoForward)
    }

    @Test func revisitingTheCurrentLocationAddsNoEntry() {
        let a = URL(fileURLWithPath: "/a")
        var history = NavigationHistory(start: a)
        history.visit(a)
        #expect(!history.canGoBack)
    }
}

struct DirectoryListingTests {
    @Test func reportsFoldersFilesHiddenItemsAndLinkedFolders() throws {
        let root = try temporaryTree(["folder/inner.txt", "file.txt", ".hidden"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("folder")
        )

        let entries = Dictionary(uniqueKeysWithValues: try DirectoryListing.entries(of: root).map { ($0.name, $0) })

        #expect(Set(entries.keys) == ["folder", "file.txt", ".hidden", "link"])
        #expect(entries["folder"]?.isFolder == true)
        #expect(entries["file.txt"]?.isFolder == false)
        #expect(entries[".hidden"]?.isHidden == true)
        #expect(entries["link"]?.isFolder == true)
        #expect(entries["link"]?.isSymbolicLink == true)
    }
}
