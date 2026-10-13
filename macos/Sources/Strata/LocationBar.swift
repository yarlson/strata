// SPDX-License-Identifier: MIT

import AppKit

@MainActor
protocol LocationBarDelegate: AnyObject {
    func locationBar(_ bar: LocationBar, navigateTo url: URL)
    func locationBarDidEndEditing(_ bar: LocationBar)
}

/// A path control that turns into a text field for typed locations.
@MainActor
final class LocationBar: NSView, NSTextFieldDelegate {
    weak var delegate: LocationBarDelegate?

    private let path = NSPathControl()
    private let field = NSTextField()
    private var location = FileManager.default.homeDirectoryForCurrentUser

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        path.pathStyle = .standard
        path.isEditable = false
        path.focusRingType = .none
        path.target = self
        path.action = #selector(pathClicked)
        path.doubleAction = #selector(beginEditing)
        // Below the fitting-size priority, so toolbar layout truncates the path instead of overflowing buttons.
        path.setContentCompressionResistancePriority(.init(40), for: .horizontal)
        field.isHidden = true
        field.delegate = self
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderString = tr("Location")
        for child in [path, field] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            path.leadingAnchor.constraint(equalTo: leadingAnchor),
            path.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            path.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// No preferred width: the toolbar gives the location bar the space left after the buttons.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    var isEditing: Bool { !field.isHidden }

    func show(_ url: URL) {
        location = url.canonical
        path.url = location
    }

    @objc private func pathClicked() {
        guard let url = path.clickedPathItem?.url, url != location else { return }
        delegate?.locationBar(self, navigateTo: url)
    }

    @objc func beginEditing() {
        field.stringValue = Self.displayPath(location) + (location.path == "/" ? "" : "/")
        path.isHidden = true
        field.isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    private func endEditing() {
        guard isEditing else { return }
        field.isHidden = true
        path.isHidden = false
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
}
