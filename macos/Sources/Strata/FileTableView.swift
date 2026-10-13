// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

@MainActor
protocol FileTableViewDelegate: AnyObject {
    func fileTable(_ table: FileTableView, handleKey event: NSEvent) -> Bool
    func fileTableMenu(_ table: FileTableView) -> NSMenu?
    func fileTableDidBecomeFirstResponder(_ table: FileTableView)
    func fileTableActivate(_ table: FileTableView)
}

/// A table that routes Strata shortcuts before NSTableView's defaults.
final class FileTableView: NSTableView {
    weak var fileDelegate: FileTableViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsTypeSelect = false
        allowsMultipleSelection = true
        allowsEmptySelection = true
        focusRingType = .none
        style = .inset
        doubleAction = #selector(activate)
        target = self
        registerForDraggedTypes([.fileURL])
        setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func activate() {
        guard clickedRow >= 0 else { return }
        fileDelegate?.fileTableActivate(self)
    }

    override func keyDown(with event: NSEvent) {
        if fileDelegate?.fileTable(self, handleKey: event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { fileDelegate?.fileTableDidBecomeFirstResponder(self) }
        return accepted
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes([row], byExtendingSelection: false)
        } else if row < 0 {
            deselectAll(nil)
        }
        window?.makeFirstResponder(self)
        return fileDelegate?.fileTableMenu(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row < 0, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift) {
            deselectAll(nil)
        }
        super.mouseDown(with: event)
    }

    var isFirstResponder: Bool { window?.firstResponder === self }

    /// Moves the cursor and selection to `row`, extending from the anchor when asked.
    func moveCursor(to row: Int, extend: Bool = false) {
        guard numberOfRows > 0 else { return }
        let target = row.clamped(to: 0...(numberOfRows - 1))
        if extend, let anchor = selectedRowIndexes.first {
            let range = min(anchor, target)...max(anchor, target)
            selectRowIndexes(IndexSet(integersIn: range), byExtendingSelection: false)
        } else {
            selectRowIndexes([target], byExtendingSelection: false)
        }
        scrollRowToVisible(target)
    }

    var cursorRow: Int {
        selectedRowIndexes.count > 1 ? selectedRowIndexes.last ?? -1 : selectedRow
    }

    var pageRowCount: Int {
        let height = enclosingScrollView?.contentView.bounds.height ?? 0
        return max(1, Int(height / max(rowHeight, 1)) - 1)
    }
}

/// A table cell with one text field whose color follows the row's selection.
final class TextCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField = label
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            label.textColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }
}

/// Icon, name, an optional dimmed detail, and a folder chevron.
final class FileCellView: NSTableCellView {
    let nameField = NSTextField(labelWithString: "")
    let detailField = NSTextField(labelWithString: "")
    let chevron = NSImageView()
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView = icon
        textField = nameField
        for view in [icon, nameField, detailField, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailField.lineBreakMode = .byTruncatingHead
        detailField.alignment = .right
        detailField.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        detailField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        chevron.image = IconProvider.symbol("chevron.right", size: 9, weight: .semibold)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            nameField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 8),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -4),
            detailField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.45),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var isDimmed = false

    func configure(_ entry: FileEntry, detail: String?, showsChevron: Bool) {
        let appearance = Appearance.shared
        icon.image = IconProvider.shared.icon(for: entry)
        nameField.stringValue = entry.name
        nameField.font = appearance.font()
        detailField.stringValue = detail ?? ""
        detailField.font = appearance.font(scale: 0.85)
        chevron.isHidden = !(showsChevron && entry.isFolder)
        isDimmed = entry.isHidden
        updateColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    /// Hidden items are dimmed; a selected row in a focused table uses the selection text color.
    private func updateColors() {
        let selected: NSColor? = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : nil
        nameField.textColor = selected ?? (isDimmed ? .secondaryLabelColor : .labelColor)
        detailField.textColor = selected ?? .secondaryLabelColor
        chevron.contentTintColor = selected ?? .secondaryLabelColor
    }
}

/// Edits a name inside a cell: Enter or focus loss commits, Escape cancels.
/// `finish` learns whether the browser should take keyboard focus back.
@MainActor
final class InlineRename: NSObject, NSTextFieldDelegate {
    private weak var field: NSTextField?
    private let original: String
    private let commit: (String) -> Void
    private let finish: (_ restoreFocus: Bool) -> Void
    private var isDone = false

    init(
        field: NSTextField, entry: FileEntry, commit: @escaping (String) -> Void,
        finish: @escaping (_ restoreFocus: Bool) -> Void
    ) {
        self.field = field
        original = entry.name
        self.commit = commit
        self.finish = finish
        super.init()
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.textColor = .labelColor
        field.isBezeled = false
        field.focusRingType = .exterior
        field.delegate = self
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = FileNames.editableRange(entry.name, isFolder: entry.isFolder)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            end(committing: false, restoreFocus: true)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            end(committing: true, restoreFocus: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        end(committing: true, restoreFocus: false)
    }

    private func end(committing: Bool, restoreFocus: Bool) {
        guard !isDone, let field else { return }
        isDone = true
        let text = field.stringValue
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.delegate = nil
        field.stringValue = original
        finish(restoreFocus)
        if committing, text != original, FileNames.isValid(text) {
            commit(text)
        }
    }
}
