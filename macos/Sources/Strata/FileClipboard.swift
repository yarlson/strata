// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Copies and cuts files through the general pasteboard so other apps can
/// paste them too. A cut is remembered until the pasteboard changes.
@MainActor
final class FileClipboard {
    static let shared = FileClipboard()
    nonisolated static let didChange = Notification.Name("StrataClipboardDidChange")

    private var cutChangeCount: Int?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ urls: [URL]) {
        write(urls)
        cutChangeCount = nil
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func cut(_ urls: [URL]) {
        write(urls)
        cutChangeCount = pasteboard.changeCount
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    var isCut: Bool { cutChangeCount == pasteboard.changeCount }

    var urls: [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    /// Pastes into `directory`; a cut moves the items and empties the clipboard.
    func paste(into directory: URL, window: NSWindow?, completion: @escaping @MainActor ([URL]) -> Void) {
        let items = urls
        guard !items.isEmpty else { return }
        let mode: TransferMode = isCut ? .move : .copy
        if mode == .move {
            pasteboard.clearContents()
            cutChangeCount = nil
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
        FileOperationCenter.shared.transfer(items, to: directory, mode: mode, window: window, completion: completion)
    }

    /// "Copied · 2 items" style status for the footer, or nil when empty.
    var status: String? {
        let count = urls.count
        guard count > 0 else { return nil }
        return "\(isCut ? tr("Cut") : tr("Copied")) · \(trCount("items", count))"
    }

    private func write(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }
}
