// SPDX-License-Identifier: MIT

import AppKit

@MainActor
protocol FilterBarDelegate: AnyObject {
    func filterBar(_ bar: FilterBar, didChange text: String)
    func filterBarDidCancel(_ bar: FilterBar)
    func filterBarMoveDown(_ bar: FilterBar)
}

@MainActor
final class FilterBar: ThemedView, NSSearchFieldDelegate {
    weak var delegate: FilterBarDelegate?
    let field = NSSearchField()
    private let status = NSTextField.themedLabel(color: \.dimText, scale: 0.85)

    init() {
        super.init(fill: \.surface)
        borderEdges = .minY
        field.placeholderString = tr("Filter")
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        for child in [field, status] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 320),
            status.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    var text: String { field.stringValue }

    func setStatus(_ text: String) {
        status.stringValue = text
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    func clear() {
        field.stringValue = ""
        status.stringValue = ""
    }

    func controlTextDidChange(_ obj: Notification) {
        delegate?.filterBar(self, didChange: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            delegate?.filterBarDidCancel(self)
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertNewline(_:)):
            delegate?.filterBarMoveDown(self)
            return true
        default:
            return false
        }
    }
}

/// Shortcut hints, clipboard status, and the item count along the bottom.
@MainActor
final class FooterView: ThemedView {
    private let hints = NSTextField.themedLabel(color: \.dimText, scale: 0.82)
    private let status = NSTextField.themedLabel(color: \.dimText, scale: 0.82)

    init() {
        super.init(fill: \.background)
        borderEdges = .maxY
        hints.lineBreakMode = .byTruncatingTail
        status.alignment = .right
        status.setContentCompressionResistancePriority(.required, for: .horizontal)
        for child in [hints, status] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            hints.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            hints.centerYAnchor.constraint(equalTo: centerYAnchor),
            hints.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -16),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        hints.attributedStringValue = Self.hintText()
    }

    override func appearanceDidChange() {
        super.appearanceDidChange()
        hints.attributedStringValue = Self.hintText()
    }

    func setStatus(_ text: String) {
        status.stringValue = text
    }

    private static func hintText() -> NSAttributedString {
        let appearance = Appearance.shared
        let pairs: [(String, String)] = [
            ("↑↓ ←→", tr("Navigate")),
            (Bindings.enter.label, tr("Open")),
            (Bindings.space.label, tr("Quick preview")),
            (Bindings.filter.label, tr("Filter")),
            (Bindings.search.label, tr("Search")),
            ("\(Bindings.copy.label) \(Bindings.cut.label)", tr("Copy / cut")),
            (Bindings.trash.label, tr("Trash")),
            (Bindings.reference.label, tr("Shortcuts")),
        ]
        let text = NSMutableAttributedString()
        for (index, (keys, action)) in pairs.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "    ")) }
            text.append(
                NSAttributedString(
                    string: keys,
                    attributes: [
                        .font: appearance.font(scale: 0.82, weight: .semibold),
                        .foregroundColor: appearance.palette.text,
                    ]))
            text.append(
                NSAttributedString(
                    string: "  " + action,
                    attributes: [
                        .font: appearance.font(scale: 0.82), .foregroundColor: appearance.palette.dimText,
                    ]))
        }
        return text
    }
}

@MainActor
final class ProgressDock: ThemedView {
    private let stack = NSStackView()

    init() {
        super.init(fill: \.surface)
        borderEdges = .maxY
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: FileOperationCenter.didChange, object: nil
        )
        refresh()
    }

    @objc private func refresh() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let operations = FileOperationCenter.shared.operations
        isHidden = operations.isEmpty
        for operation in operations {
            let title = NSTextField.themedLabel(
                "\(operation.title)  \(operation.currentName)", color: \.text, scale: 0.85)
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = operation.total <= 1
            progress.minValue = 0
            progress.maxValue = Double(max(operation.total, 1))
            progress.doubleValue = Double(operation.completed)
            if progress.isIndeterminate { progress.startAnimation(nil) }
            let cancel = ClosureButton(symbol: "xmark.circle.fill", label: tr("Cancel")) {
                operation.cancelFlag.cancel()
            }
            let row = NSStackView(views: [title, progress, cancel])
            row.orientation = .horizontal
            row.spacing = 10
            progress.widthAnchor.constraint(equalToConstant: 220).isActive = true
            stack.addArrangedSubview(row)
        }
    }
}

/// An icon-only button that runs a closure and names itself for accessibility.
final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(symbol: String, label: String, size: CGFloat = 13, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        image = IconProvider.symbol(symbol, size: size)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(run)
        contentTintColor = Appearance.shared.palette.dimText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
