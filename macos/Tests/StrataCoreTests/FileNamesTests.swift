// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

struct FileNamesTests {
    @Test(arguments: [
        ("notes.txt", true),
        (" padded ", true),
        (".hidden", true),
        ("日本語", true),
        ("", false),
        ("   ", false),
        ("\u{3000}\u{00A0}", false),
        (".", false),
        ("..", false),
        ("a/b", false),
        ("nul\0byte", false),
    ])
    func validatesNames(name: String, isValid: Bool) {
        #expect(FileNames.isValid(name) == isValid)
    }

    @Test(arguments: [
        ("new folder", true, ["new folder"], "new folder (1)"),
        ("new folder", true, ["new folder", "new folder (1)"], "new folder (2)"),
        ("photo.jpg", false, ["photo.jpg"], "photo (1).jpg"),
        ("photo (3).jpg", false, ["photo (3).jpg"], "photo (4).jpg"),
        ("photo (03).jpg", false, ["photo (03).jpg"], "photo (03) (1).jpg"),
        (".bashrc", false, [".bashrc"], ".bashrc (1)"),
        ("release.v1", true, ["release.v1"], "release.v1 (1)"),
        ("free.txt", false, [], "free.txt"),
    ])
    func allocatesTheFirstFreeNumberedName(name: String, isFolder: Bool, taken: [String], expected: String) {
        let available = FileNames.available(name, isFolder: isFolder) { taken.contains($0) }
        #expect(available == expected)
    }

    @Test func duplicatingNeverKeepsTheOriginalName() {
        let duplicate = FileNames.available("a.txt", isFolder: false, keepOriginal: false) { _ in false }
        #expect(duplicate == "a (1).txt")
    }

    @Test func renameSelectsTheStemOfFilesAndAllOfAFolderName() {
        #expect(FileNames.editableRange("report.final.pdf", isFolder: false) == NSRange(location: 0, length: 12))
        #expect(FileNames.editableRange("v1.2", isFolder: true) == NSRange(location: 0, length: 4))
        #expect(FileNames.editableRange(".zshrc", isFolder: false) == NSRange(location: 0, length: 6))
    }
}
