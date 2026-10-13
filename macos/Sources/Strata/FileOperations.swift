// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
final class FileOperation: Identifiable {
    let id = UUID()
    let title: String
    let total: Int
    let cancelFlag = CancelFlag()
    var completed = 0
    var currentName = ""

    init(title: String, total: Int) {
        self.title = title
        self.total = total
    }
}

enum ConflictChoice: Sendable {
    case replace, keepBoth, skip, cancel
}

private struct TransferResult: Sendable {
    var outcomes: [TransferOutcome] = []
    var failures: [String] = []

    var created: [URL] { outcomes.compactMap(\.created) }
    var moved: [(URL, URL)] { outcomes.compactMap(\.moved).map { ($0.from, $0.to) } }
    var replaced: [(URL, URL)] { outcomes.compactMap(\.replaced).map { ($0.trashed, $0.original) } }
}

/// Runs file mutations off the main thread, asks about conflicts, reports
/// failures, and registers undo.
@MainActor
final class FileOperationCenter {
    static let shared = FileOperationCenter()
    nonisolated static let didChange = Notification.Name("StrataFileOperationsDidChange")

    private(set) var operations: [FileOperation] = []

    // MARK: Transfers

    /// Copies, moves, or duplicates `sources` into `destination` and calls
    /// `completion` with the resulting items.
    func transfer(
        _ sources: [URL], to destination: URL, mode: TransferMode, window: NSWindow?,
        completion: (@MainActor ([URL]) -> Void)? = nil
    ) {
        let destination = destination.canonical
        var accepted: [URL] = []
        for source in sources.map(\.canonical) {
            if mode != .duplicate, source == destination || source.isAncestor(of: destination) {
                Alerts.showError(
                    tr("Cannot move or copy a folder into itself"),
                    detail: quoted(source.lastPathComponent), window: window
                )
                return
            }
            if mode == .move, source.deletingLastPathComponent().canonical == destination { continue }
            accepted.append(source)
        }
        guard !accepted.isEmpty else { return }
        let title =
            mode == .move
            ? tr("Moving items")
            : tr("Copying items")
        let operation = begin(title: title, total: accepted.count)
        let undoManager = window?.undoManager
        Task.detached {
            let result = await Self.performTransfer(accepted, destination, mode, operation, window)
            await MainActor.run {
                let center = FileOperationCenter.shared
                center.finish(operation)
                center.registerTransferUndo(result, mode: mode, undoManager: undoManager)
                center.report(result.failures, title: tr("Some items could not be transferred"), window: window)
                completion?(result.created + result.moved.map(\.1))
            }
        }
    }

    nonisolated private static func performTransfer(
        _ sources: [URL], _ destination: URL, _ mode: TransferMode, _ operation: FileOperation,
        _ window: NSWindow?
    ) async -> TransferResult {
        let cancel = operation.cancelFlag
        var result = TransferResult()
        var choiceForAll: ConflictChoice?
        for source in sources {
            guard !cancel.isCancelled else { break }
            let name = source.lastPathComponent
            await MainActor.run { operation.currentName = name }
            await FileOperationCenter.shared.changed()
            var target = destination.appendingPathComponent(name)
            var replacing = false
            if mode == .duplicate || (mode == .copy && source.deletingLastPathComponent().canonical == destination) {
                target = FileMutations.numberedTarget(for: source, in: destination, keepOriginal: false)
            } else if FileMutations.exists(target) {
                var choice = choiceForAll
                if choice == nil {
                    let (picked, applyToAll) = await askConflict(name: name, folder: destination, window: window)
                    choice = picked
                    if applyToAll { choiceForAll = picked }
                }
                switch choice ?? .skip {
                case .cancel:
                    cancel.cancel()
                    continue
                case .skip:
                    await advance(operation)
                    continue
                case .keepBoth:
                    target = FileMutations.numberedTarget(for: source, in: destination, keepOriginal: true)
                case .replace:
                    replacing = true
                }
            }
            do {
                let outcome = try FileMutations.transfer(
                    source, to: target, mode: mode, replacing: replacing, cancel: cancel)
                result.outcomes.append(outcome)
            } catch let error as CocoaError where error.code == .userCancelled {
                break
            } catch {
                result.failures.append("\(quoted(name)): \(error.localizedDescription)")
            }
            await advance(operation)
        }
        return result
    }

    nonisolated private static func askConflict(
        name: String, folder: URL, window: NSWindow?
    ) async -> (ConflictChoice, Bool) {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = tr("“%{name}” already exists", ["name": name])
                alert.informativeText = tr(
                    "An item named “%{name}” already exists in %{folder}. Replacing it will overwrite its contents.",
                    ["name": name, "folder": folder.path]
                )
                alert.addButton(withTitle: tr("Keep Both"))
                alert.addButton(withTitle: tr("Replace"))
                alert.addButton(withTitle: tr("Skip"))
                alert.addButton(withTitle: tr("Cancel"))
                alert.showsSuppressionButton = true
                alert.suppressionButton?.title = tr("Apply to all")
                Alerts.present(alert, window: window) { response in
                    let choice: ConflictChoice =
                        switch response {
                        case .alertFirstButtonReturn: .keepBoth
                        case .alertSecondButtonReturn: .replace
                        case .alertThirdButtonReturn: .skip
                        default: .cancel
                        }
                    continuation.resume(returning: (choice, alert.suppressionButton?.state == .on))
                }
            }
        }
    }

    nonisolated private static func advance(_ operation: FileOperation) async {
        await MainActor.run { operation.completed += 1 }
        await FileOperationCenter.shared.changed()
    }

    private func registerTransferUndo(_ result: TransferResult, mode: TransferMode, undoManager: UndoManager?) {
        guard let undoManager else { return }
        let name = mode == .move ? tr("Move") : tr("Copy")
        let restore = result.replaced
        if !result.created.isEmpty {
            let created = result.created
            undoManager.registerUndo(withTarget: self) { center in
                center.trash(created, window: nil, undoManager: undoManager, actionName: name) {
                    if !restore.isEmpty { center.relocate(restore, undoManager: undoManager, actionName: name) }
                }
            }
            undoManager.setActionName(name)
        } else if !result.moved.isEmpty {
            let reversed = result.moved.reversed().map { ($0.1, $0.0) } + restore
            undoManager.registerUndo(withTarget: self) { center in
                center.relocate(reversed, undoManager: undoManager, actionName: name)
            }
            undoManager.setActionName(name)
        }
    }

    /// Moves each item to an exact location; undo reverses it. Used by undo and redo.
    func relocate(_ pairs: [(URL, URL)], undoManager: UndoManager?, actionName: String) {
        var done: [(URL, URL)] = []
        var failures: [String] = []
        for (from, to) in pairs {
            do {
                try FileManager.default.moveItem(at: from, to: to)
                done.append((from, to))
            } catch {
                failures.append("\(quoted(from.lastPathComponent)): \(error.localizedDescription)")
            }
        }
        if let undoManager, !done.isEmpty {
            let reversed = done.reversed().map { ($0.1, $0.0) }
            undoManager.registerUndo(withTarget: self) { center in
                center.relocate(reversed, undoManager: undoManager, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        report(failures, title: tr("Some items could not be moved"), window: nil)
    }

    // MARK: Trash and delete

    /// Moves items to the Trash. When a location has no Trash, offers permanent deletion.
    func trash(
        _ urls: [URL], window: NSWindow?, undoManager: UndoManager?, actionName: String? = nil,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard !urls.isEmpty else { return }
        let operation = begin(title: tr("Move to Trash"), total: urls.count)
        Task.detached {
            var pairs: [(URL, URL)] = []
            var unsupported: [URL] = []
            var failures: [String] = []
            for url in urls {
                do {
                    if let trashed = try FileMutations.systemTrash(url) { pairs.append((trashed, url)) }
                } catch let error as CocoaError where error.code == .featureUnsupported {
                    unsupported.append(url)
                } catch {
                    failures.append("\(quoted(url.lastPathComponent)): \(error.localizedDescription)")
                }
                await Self.advance(operation)
            }
            await MainActor.run { [pairs, unsupported, failures] in
                let center = FileOperationCenter.shared
                center.finish(operation)
                if let undoManager, !pairs.isEmpty {
                    let name = actionName ?? tr("Move to Trash")
                    undoManager.registerUndo(withTarget: center) { center in
                        center.relocate(pairs, undoManager: undoManager, actionName: name)
                    }
                    undoManager.setActionName(name)
                }
                center.report(failures, title: tr("Some items could not be moved to the Trash"), window: window)
                if !unsupported.isEmpty {
                    center.confirmDelete(unsupported, trashUnsupported: true, window: window)
                }
                completion?()
            }
        }
    }

    func confirmDelete(_ urls: [URL], trashUnsupported: Bool = false, window: NSWindow?) {
        guard !urls.isEmpty else { return }
        let warning =
            if trashUnsupported {
                tr(
                    "This location doesn't support Trash. These items will be permanently deleted. This action cannot be undone."
                )
            } else if urls.count == 1 {
                tr("This item will be permanently deleted. This action cannot be undone.")
            } else {
                tr("These items will be permanently deleted. This action cannot be undone.")
            }
        let subject = urls.count == 1 ? quoted(urls[0].lastPathComponent) : trCount("items", urls.count)
        Alerts.confirmDestructive(
            tr("Permanently delete"), detail: "\(subject)\n\n\(warning)", action: tr("Delete Permanently"),
            window: window
        ) {
            self.deletePermanently(urls, window: window)
        }
    }

    private func deletePermanently(_ urls: [URL], window: NSWindow?) {
        let operation = begin(title: tr("Delete Permanently"), total: urls.count)
        Task.detached {
            var failures: [String] = []
            for url in urls {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    failures.append("\(quoted(url.lastPathComponent)): \(error.localizedDescription)")
                }
                await Self.advance(operation)
            }
            await MainActor.run { [failures] in
                FileOperationCenter.shared.finish(operation)
                FileOperationCenter.shared.report(
                    failures, title: tr("Some items could not be deleted"), window: window)
            }
        }
    }

    // MARK: Create and rename

    /// Creates `new folder` or `new file` under the first free name.
    func create(folder: Bool, in directory: URL, window: NSWindow?) -> URL? {
        do {
            let url = try FileMutations.create(folder: folder, in: directory)
            registerCreationUndo(
                [url], name: folder ? tr("New Folder") : tr("New File"), undoManager: window?.undoManager)
            return url
        } catch {
            if folder {
                Alerts.showError(
                    tr("Could not create folder: %{error}", ["error": error.localizedDescription]), window: window)
            } else {
                Alerts.showError(tr("Unable to complete operation"), detail: error.localizedDescription, window: window)
            }
            return nil
        }
    }

    /// Creates a folder and moves `items` into it.
    func createFolder(containing items: [URL], in directory: URL, window: NSWindow?) -> URL? {
        guard let folder = create(folder: true, in: directory, window: window) else { return nil }
        var failures: [String] = []
        for item in items {
            do {
                try FileManager.default.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
            } catch {
                failures.append("\(quoted(item.lastPathComponent)): \(error.localizedDescription)")
            }
        }
        report(failures, title: tr("Some items could not be moved"), window: window)
        return folder
    }

    /// Renames an item in place. Returns the new location, or nil when the name
    /// is unchanged or the rename failed.
    @discardableResult
    func rename(_ url: URL, to name: String, window: NSWindow?) -> URL? {
        guard name != url.lastPathComponent else { return nil }
        let target: URL
        do {
            target = try FileMutations.rename(url, to: name)
        } catch {
            Alerts.showError(
                tr("Could not rename %{name}", ["name": quoted(url.lastPathComponent)]),
                detail: error.localizedDescription, window: window
            )
            return nil
        }
        if let undoManager = window?.undoManager {
            undoManager.registerUndo(withTarget: self) { center in
                center.relocate([(target, url)], undoManager: undoManager, actionName: tr("Rename"))
            }
            undoManager.setActionName(tr("Rename"))
        }
        return target
    }

    private func registerCreationUndo(_ urls: [URL], name: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { center in
            center.trash(urls, window: nil, undoManager: undoManager, actionName: name)
        }
        undoManager.setActionName(name)
    }

    // MARK: Compress

    /// Writes a `.zip` next to the items: `<name>.zip` for one, `Archive.zip` for several.
    func compress(_ urls: [URL], window: NSWindow?, completion: (@MainActor (URL) -> Void)? = nil) {
        guard let first = urls.first else { return }
        let directory = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.lastPathComponent + ".zip" : "Archive.zip"
        let archive = directory.appendingPathComponent(
            FileNames.available(base, isFolder: false) {
                FileMutations.exists(directory.appendingPathComponent($0))
            })
        let operation = begin(title: tr("Compress"), total: 1)
        operation.currentName = archive.lastPathComponent
        let cancel = operation.cancelFlag
        Task.detached {
            let failure = await Self.runArchiver(urls, archive: archive, cancel: cancel)
            await MainActor.run {
                let center = FileOperationCenter.shared
                center.finish(operation)
                if let failure {
                    Alerts.showError(tr("Could not compress the selection"), detail: failure, window: window)
                } else if !cancel.isCancelled {
                    center.registerCreationUndo([archive], name: tr("Compress"), undoManager: window?.undoManager)
                    completion?(archive)
                }
            }
        }
    }

    /// Runs ditto for one item or zip for several. Returns an error message on failure.
    nonisolated private static func runArchiver(_ urls: [URL], archive: URL, cancel: CancelFlag) async -> String? {
        let process = Process()
        if urls.count == 1 {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, archive.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = archive.deletingLastPathComponent()
            process.arguments = ["-r", "-y", "-q", archive.path, "--"] + urls.map(\.lastPathComponent)
        }
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        while process.isRunning {
            if cancel.isCancelled { process.terminate() }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard process.terminationStatus != 0 else { return nil }
        try? FileManager.default.removeItem(at: archive)
        if cancel.isCancelled { return nil }
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Bookkeeping

    private func begin(title: String, total: Int) -> FileOperation {
        let operation = FileOperation(title: title, total: total)
        operations.append(operation)
        changed()
        return operation
    }

    private func finish(_ operation: FileOperation) {
        operations.removeAll { $0.id == operation.id }
        changed()
    }

    func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func report(_ failures: [String], title: String, window: NSWindow?) {
        guard !failures.isEmpty else { return }
        Alerts.showError(title, detail: failures.prefix(8).joined(separator: "\n"), window: window)
    }
}
