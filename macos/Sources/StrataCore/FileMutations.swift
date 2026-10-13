// SPDX-License-Identifier: MIT

import Foundation

public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
}

public enum TransferMode: Sendable {
    case copy, move, duplicate
}

/// What one transferred item left behind, for undo.
public struct TransferOutcome: Sendable {
    public var created: URL?
    /// The source and its new location when the item moved.
    public var moved: (from: URL, to: URL)?
    /// Where a replaced item went in the Trash, and where it was.
    public var replaced: (trashed: URL, original: URL)?
}

/// Filesystem changes with Strata's safety rules: never overwrite silently,
/// stage replacements, and move replaced items to the Trash.
public enum FileMutations {
    public typealias Trash = @Sendable (URL) throws -> URL?

    public static let systemTrash: Trash = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    /// Renames in place. Fails for invalid or taken names; a case-only change
    /// works on case-insensitive volumes.
    public static func rename(_ url: URL, to name: String) throws -> URL {
        guard FileNames.isValid(name) else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: name])
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if isSameItem(url, target) {
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".strata-rename-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: url, to: temporary)
            do {
                try FileManager.default.moveItem(at: temporary, to: target)
            } catch {
                try? FileManager.default.moveItem(at: temporary, to: url)
                throw error
            }
        } else {
            try FileManager.default.moveItem(at: url, to: target)
        }
        return target
    }

    /// Creates `new folder` or an empty `new file` under the first free name.
    public static func create(folder: Bool, in directory: URL) throws -> URL {
        let base = folder ? FileNames.newFolder : FileNames.newFile
        let url = directory.appendingPathComponent(
            FileNames.available(base, isFolder: folder) {
                exists(directory.appendingPathComponent($0))
            })
        if folder {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } else {
            try Data().write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    /// The target a transfer writes when it keeps both items.
    public static func numberedTarget(for source: URL, in destination: URL, keepOriginal: Bool) -> URL {
        let isFolder =
            source.hasDirectoryPath
            || (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let name = FileNames.available(source.lastPathComponent, isFolder: isFolder, keepOriginal: keepOriginal) {
            exists(destination.appendingPathComponent($0))
        }
        return destination.appendingPathComponent(name)
    }

    /// Copies or moves `source` to `target`. With `replacing`, the new item is
    /// staged first and the existing target goes to the Trash before it is swapped in.
    public static func transfer(
        _ source: URL, to target: URL, mode: TransferMode, replacing: Bool,
        cancel: CancelFlag = CancelFlag(), trash: Trash = systemTrash
    ) throws -> TransferOutcome {
        var outcome = TransferOutcome()
        if mode == .move, sameVolume(source, target.deletingLastPathComponent()) {
            if replacing { outcome.replaced = try trash(target).map { ($0, target) } }
            do {
                try FileManager.default.moveItem(at: source, to: target)
            } catch {
                if let replaced = outcome.replaced {
                    try? FileManager.default.moveItem(at: replaced.trashed, to: replaced.original)
                }
                throw error
            }
            outcome.moved = (source, target)
            return outcome
        }
        let staged =
            replacing
            ? target.deletingLastPathComponent().appendingPathComponent(
                ".strata-\(UUID().uuidString)-\(target.lastPathComponent)")
            : target
        let manager = FileManager()
        let delegate = CancellingCopyDelegate(cancel: cancel)
        manager.delegate = delegate
        do {
            try manager.copyItem(at: source, to: staged)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        if cancel.isCancelled {
            try? FileManager.default.removeItem(at: staged)
            throw CocoaError(.userCancelled)
        }
        if replacing {
            outcome.replaced = try trash(target).map { ($0, target) }
            try FileManager.default.moveItem(at: staged, to: target)
        }
        if mode == .move {
            try FileManager.default.removeItem(at: source)
            outcome.moved = (source, target)
        } else {
            outcome.created = target
        }
        return outcome
    }

    /// Whether anything, including a dangling symbolic link, occupies `url`.
    public static func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    public static func sameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let left = (try? lhs.resourceValues(forKeys: key))?.volumeIdentifier,
            let right = (try? rhs.resourceValues(forKeys: key))?.volumeIdentifier
        else { return false }
        return left.isEqual(right)
    }

    /// Two names for one item, as on a case-insensitive volume.
    static func isSameItem(_ lhs: URL, _ rhs: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let left = (try? lhs.resourceValues(forKeys: key))?.fileResourceIdentifier,
            let right = (try? rhs.resourceValues(forKeys: key))?.fileResourceIdentifier
        else { return false }
        return left.isEqual(right)
    }
}

/// Skips the rest of a copy once its operation is cancelled.
private final class CancellingCopyDelegate: NSObject, FileManagerDelegate, @unchecked Sendable {
    let cancel: CancelFlag
    init(cancel: CancelFlag) { self.cancel = cancel }

    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        !cancel.isCancelled
    }
}

extension URL {
    /// The standardized file URL without a trailing slash, so one item has one URL.
    public var canonical: URL {
        URL(filePath: standardizedFileURL.path(percentEncoded: false), directoryHint: .notDirectory)
    }

    /// Whether this URL is a strict ancestor directory of `other`.
    public func isAncestor(of other: URL) -> Bool {
        let mine = standardizedFileURL.pathComponents
        let theirs = other.standardizedFileURL.pathComponents
        return theirs.count > mine.count && Array(theirs.prefix(mine.count)) == mine
    }
}
