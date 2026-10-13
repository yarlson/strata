// SPDX-License-Identifier: MIT

import AppKit

@MainActor
protocol LocationBarDelegate: AnyObject {
    func locationBar(_ bar: LocationBar, navigateTo url: URL)
    func locationBarDidEndEditing(_ bar: LocationBar)
}

/// Clickable breadcrumbs that turn into a path field for typed locations.
@MainActor
final class LocationBar: NSView, NSTextFieldDelegate {
    weak var delegate: LocationBarDelegate?

    private let crumbs = NSStackView()
    private let field = NSTextField()
    private var location = FileManager.default.homeDirectoryForCurrentUser

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        crumbs.orientation = .horizontal
        crumbs.spacing = 2
        crumbs.alignment = .centerY
        crumbs.setHuggingPriority(.defaultLow, for: .horizontal)
        field.isHidden = true
        field.delegate = self
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderString = tr("Location")
        for child in [crumbs, field] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            crumbs.leadingAnchor.constraint(equalTo: leadingAnchor),
            crumbs.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            crumbs.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildCrumbs), name: Appearance.didChange, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 480, height: 28) }

    var isEditing: Bool { !field.isHidden }

    func show(_ url: URL) {
        location = url.canonical
        rebuildCrumbs()
    }

    func beginEditing() {
        field.stringValue = Self.displayPath(location) + (location.path == "/" ? "" : "/")
        field.font = Appearance.shared.font()
        crumbs.isHidden = true
        field.isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    private func endEditing() {
        guard isEditing else { return }
        field.isHidden = true
        crumbs.isHidden = false
        delegate?.locationBarDidEndEditing(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            endEditing()
            if let url = Self.resolve(text) {
                delegate?.locationBar(self, navigateTo: url)
            }
            return true
        }
        if selector == #selector(NSResponder.insertTab(_:)) {
            complete()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }

    /// Completes the last path component from the folder's subfolders.
    private func complete() {
        let text = field.stringValue
        let expanded = (text as NSString).expandingTildeInPath
        let directory = text.hasSuffix("/") ? expanded : (expanded as NSString).deletingLastPathComponent
        let prefix = text.hasSuffix("/") ? "" : (expanded as NSString).lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        let matches = names.filter {
            $0.lowercased().hasPrefix(prefix.lowercased())
                && (try? URL(fileURLWithPath: directory).appendingPathComponent($0).resourceValues(forKeys: [
                    .isDirectoryKey
                ]))?.isDirectory == true
        }.sorted()
        guard let first = matches.first else { return }
        let completed = matches.count == 1 ? first + "/" : commonPrefix(matches)
        let base = text.hasSuffix("/") ? text : (text as NSString).deletingLastPathComponent
        field.stringValue = (base.hasSuffix("/") || base.isEmpty ? base : base + "/") + completed
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    private func commonPrefix(_ names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.lowercased().hasPrefix(prefix.lowercased()) { prefix.removeLast() }
        }
        return prefix
    }

    /// Accepts `~`, absolute paths, `file://` URLs, and network URLs such as `smb://`.
    static func resolve(_ text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme, scheme != "file", text.contains("://") {
            return url
        }
        if let url = URL(string: text), url.isFileURL { return url }
        let path = (text as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    @objc private func rebuildCrumbs() {
        crumbs.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let appearance = Appearance.shared
        let home = FileManager.default.homeDirectoryForCurrentUser.canonical
        var trail: [(String, URL)] = []
        var current = location
        while true {
            if current == home {
                trail.append(("~", current))
                break
            }
            if current.path == "/" {
                trail.append(("/", current))
                break
            }
            trail.append((current.lastPathComponent, current))
            current = current.deletingLastPathComponent().canonical
        }
        for (index, (title, url)) in trail.reversed().enumerated() {
            if index > 0, title != "/" {
                let separator = NSTextField(labelWithString: "/")
                separator.font = appearance.font(scale: 0.95)
                separator.textColor = appearance.palette.dimText
                crumbs.addArrangedSubview(separator)
            }
            let button = CrumbButton(title: title, url: url) { [weak self] url in
                guard let self else { return }
                self.delegate?.locationBar(self, navigateTo: url)
            }
            button.isCurrent = index == trail.count - 1
            crumbs.addArrangedSubview(button)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { beginEditing() } else { super.mouseDown(with: event) }
    }
}

private final class CrumbButton: NSButton {
    private let url: URL
    private let handler: (URL) -> Void
    var isCurrent = false { didSet { restyle() } }

    init(title: String, url: URL, handler: @escaping (URL) -> Void) {
        self.url = url
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(clicked)
        lineBreakMode = .byTruncatingMiddle
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func restyle() {
        let appearance = Appearance.shared
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: appearance.font(scale: 0.95, weight: isCurrent ? .semibold : .regular),
                .foregroundColor: isCurrent ? appearance.palette.text : appearance.palette.dimText,
            ])
    }

    @objc private func clicked() { handler(url) }
}
