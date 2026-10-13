// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
final class PropertiesWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [URL: PropertiesWindowController] = [:]

    private let url: URL
    private let cancel = CancelFlag()
    private let sizeLabel = NSTextField.themedLabel(scale: 0.95)

    static func show(for url: URL) {
        let url = url.canonical
        if let existing = open[url] {
            existing.showWindow(nil)
            return
        }
        let controller = PropertiesWindowController(url: url)
        open[url] = controller
        controller.showWindow(nil)
    }

    private init(url: URL) {
        self.url = url
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true
        )
        panel.title = tr("Properties")
        panel.isReleasedWhenClosed = false
        panel.appearance = Appearance.shared.palette.appearance
        super.init(window: panel)
        panel.delegate = self
        build(panel)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        cancel.cancel()
        Self.open[url] = nil
    }

    private func build(_ panel: NSPanel) {
        let content = ThemedView(fill: \.background)
        let entry = try? FileEntry(url: url)
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        let name = NSTextField.themedLabel(
            url.path == "/" ? DirectoryTableController.displayName(url) : url.lastPathComponent,
            scale: 1.1, weight: .semibold
        )
        name.isSelectable = true
        var rows: [(String, NSView)] = [
            (tr("Type"), value(entry?.kindDescription ?? "—")),
            (tr("Size"), sizeLabel),
            (tr("Location"), value(LocationBar.displayPath(url.deletingLastPathComponent()), selectable: true)),
            (tr("Created"), value(entry?.created.map(Formatters.date) ?? "—")),
            (tr("Modified"), value(entry?.modified.map(Formatters.date) ?? "—")),
            (tr("Permissions"), value(Self.permissions(url))),
        ]
        rows.append(contentsOf: volumeRows())
        let grid = NSGridView(
            views: rows.map { label, view in
                [NSTextField.themedLabel(label, color: \.dimText, scale: 0.9), view]
            })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        for child in [icon, name, grid] {
            child.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            name.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            name.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            grid.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
        ])
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 420, height: content.fittingSize.height))
        computeSize(entry)
    }

    private func value(_ text: String, selectable: Bool = false) -> NSTextField {
        let label = NSTextField.themedLabel(text, scale: 0.95)
        label.isSelectable = selectable
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        return label
    }

    private func volumeRows() -> [(String, NSView)] {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeURLKey,
            .volumeLocalizedFormatDescriptionKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
            values.volume?.canonical == url,
            let total = values.volumeTotalCapacity
        else { return [] }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return [
            (tr("Filesystem"), value(values.volumeLocalizedFormatDescription ?? "—")),
            (tr("Capacity"), value(Formatters.size(Int64(total)))),
            (tr("Free"), value(Formatters.size(available))),
            (tr("Used"), value(Formatters.size(Int64(total) - available))),
        ]
    }

    private func computeSize(_ entry: FileEntry?) {
        guard let entry, entry.isFolder || entry.isPackage else {
            sizeLabel.stringValue = entry?.size.map(Formatters.size) ?? "—"
            return
        }
        sizeLabel.stringValue = tr("Calculating…")
        let url = url
        let cancel = cancel
        Task.detached(priority: .utility) {
            var total: Int64 = 0
            var count = 0
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: [],
                errorHandler: { _, _ in true }
            )
            while let item = enumerator?.nextObject() as? URL {
                if cancel.isCancelled { return }
                let values = try? item.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(values?.fileSize ?? 0)
                count += 1
            }
            await MainActor.run { [weak self, total, count] in
                self?.sizeLabel.stringValue = "\(Formatters.size(total)) · \(trCount("items", count))"
            }
        }
    }

    static func permissions(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
        else { return "—" }
        let symbols = Array("rwxrwxrwx")
        let text = String((0..<9).map { mode & (1 << (8 - $0)) != 0 ? symbols[$0] : "-" })
        let owner = attributes[.ownerAccountName] as? String ?? ""
        let group = attributes[.groupOwnerAccountName] as? String ?? ""
        return "\(text)  \(owner):\(group)"
    }
}
