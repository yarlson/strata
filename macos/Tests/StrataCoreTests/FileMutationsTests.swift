// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

struct FileMutationsTests {
    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// A stand-in Trash inside the test folder so tests never touch the user's Trash.
    private func trash(in root: URL) -> FileMutations.Trash {
        let bin = root.appendingPathComponent(".test-trash")
        return { url in
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let target = bin.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    @Test func renameNeverReplacesAnExistingItem() throws {
        let root = try temporaryTree(["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a", to: root.appendingPathComponent("a.txt"))
        try write("b", to: root.appendingPathComponent("b.txt"))

        #expect(throws: (any Error).self) {
            try FileMutations.rename(root.appendingPathComponent("a.txt"), to: "b.txt")
        }

        #expect(try contents(root.appendingPathComponent("a.txt")) == "a")
        #expect(try contents(root.appendingPathComponent("b.txt")) == "b")
    }

    @Test func renameChangesOnlyTheLetterCase() throws {
        let root = try temporaryTree(["notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }

        let renamed = try FileMutations.rename(root.appendingPathComponent("notes.txt"), to: "Notes.txt")

        #expect(renamed.lastPathComponent == "Notes.txt")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Notes.txt"])
    }

    @Test func renameRejectsInvalidNames() throws {
        let root = try temporaryTree(["a.txt"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) { try FileMutations.rename(root.appendingPathComponent("a.txt"), to: "x/y") }
        #expect(FileMutations.exists(root.appendingPathComponent("a.txt")))
    }

    @Test func createUsesTheFirstFreeDefaultName() throws {
        let root = try temporaryTree(["new folder/keep", "new file"])
        defer { try? FileManager.default.removeItem(at: root) }

        let folder = try FileMutations.create(folder: true, in: root)
        let file = try FileMutations.create(folder: false, in: root)

        #expect(folder.lastPathComponent == "new folder (1)")
        #expect(file.lastPathComponent == "new file (1)")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("new folder/keep").path))
    }

    @Test func copyIntoItsOwnFolderKeepsBoth() throws {
        let root = try temporaryTree(["photo.jpg"])
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.jpg")
        try write("original", to: source)

        let target = FileMutations.numberedTarget(for: source, in: root, keepOriginal: false)
        let outcome = try FileMutations.transfer(source, to: target, mode: .copy, replacing: false)

        #expect(outcome.created?.lastPathComponent == "photo (1).jpg")
        #expect(try contents(source) == "original")
        #expect(try contents(target) == "original")
    }

    @Test func moveRelocatesTheItem() throws {
        let root = try temporaryTree(["a.txt", "folder/keep"])
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt")
        let target = root.appendingPathComponent("folder/a.txt")

        let outcome = try FileMutations.transfer(source, to: target, mode: .move, replacing: false)

        #expect(outcome.moved?.from == source)
        #expect(outcome.moved?.to == target)
        #expect(!FileMutations.exists(source))
        #expect(FileMutations.exists(target))
    }

    @Test func copyWithoutReplacingRefusesAnOccupiedTarget() throws {
        let root = try temporaryTree(["a.txt", "folder/a.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        try write("incoming", to: root.appendingPathComponent("a.txt"))
        try write("existing", to: root.appendingPathComponent("folder/a.txt"))

        #expect(throws: (any Error).self) {
            try FileMutations.transfer(
                root.appendingPathComponent("a.txt"), to: root.appendingPathComponent("folder/a.txt"),
                mode: .copy, replacing: false, trash: trash(in: root)
            )
        }
        #expect(try contents(root.appendingPathComponent("folder/a.txt")) == "existing")
    }

    @Test(arguments: [TransferMode.copy, .move])
    func replacingSendsTheExistingItemToTheTrash(mode: TransferMode) throws {
        let root = try temporaryTree(["a.txt", "folder/a.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt")
        let target = root.appendingPathComponent("folder/a.txt")
        try write("incoming", to: source)
        try write("existing", to: target)

        let outcome = try FileMutations.transfer(
            source, to: target, mode: mode, replacing: true, trash: trash(in: root))

        #expect(try contents(target) == "incoming")
        let trashed = try #require(outcome.replaced?.trashed)
        #expect(try contents(trashed) == "existing")
        #expect(outcome.replaced?.original == target)
        #expect(FileMutations.exists(source) == (mode == .copy))
    }

    @Test func cancelledCopyLeavesNothingBehind() throws {
        let root = try temporaryTree(["folder/one", "folder/two", "destination/keep"])
        defer { try? FileManager.default.removeItem(at: root) }
        let cancel = CancelFlag()
        cancel.cancel()
        let target = root.appendingPathComponent("destination/folder")

        #expect(throws: (any Error).self) {
            try FileMutations.transfer(
                root.appendingPathComponent("folder"), to: target, mode: .copy, replacing: false, cancel: cancel)
        }
        #expect(!FileMutations.exists(target))
        #expect(FileMutations.exists(root.appendingPathComponent("folder/one")))
    }

    @Test func ancestorCheckCoversOnlyStrictDescendants() {
        let parent = URL(fileURLWithPath: "/a/b")
        #expect(parent.isAncestor(of: URL(fileURLWithPath: "/a/b/c")))
        #expect(!parent.isAncestor(of: URL(fileURLWithPath: "/a/b")))
        #expect(!parent.isAncestor(of: URL(fileURLWithPath: "/a/bc")))
    }
}
