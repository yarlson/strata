// SPDX-License-Identifier: MIT

import AppKit
import Quartz
import StrataCore
import UniformTypeIdentifiers

/// The preview pane: a header with metadata, then rendered text, Markdown,
/// a folder summary, or a Quick Look preview.
@MainActor
final class PreviewController {
    nonisolated static let textReadLimit = 1_048_576

    let view = ThemedView(fill: \.background)
    var onClose: (() -> Void)? {
        didSet { closeButton.isHidden = onClose == nil }
    }

    private let icon = NSImageView()
    private let title = NSTextField.themedLabel(weight: .semibold)
    private let openButton = NSButton()
    private let closeButton = NSButton()
    private let metadata = NSStackView()
    private let content = ThemedView(fill: \.background)
    private let codeView = CodeView()
    private let message = NSTextField.themedLabel(color: \.dimText)
    private lazy var quickLook: QLPreviewView = {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.shouldCloseWithWindow = false
        preview.autostarts = false
        return preview
    }()
    private var current: URL?
    private var generation = 0
    private var observer: NSObjectProtocol?

    init() {
        build()
        observer = NotificationCenter.default.addObserver(
            forName: Appearance.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadCurrent() }
        }
    }

    isolated deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    func show(_ entry: FileEntry?) {
        guard let entry else {
            clear()
            return
        }
        if entry.url == current { return }
        current = entry.url
        generation += 1
        openButton.isHidden = false
        icon.image = IconProvider.shared.icon(for: entry)
        title.stringValue = entry.name
        view.isHidden = false
        setMetadata([
            (tr("Size"), entry.size.map(Formatters.size) ?? "—"),
            (tr("Modified"), entry.modified.map(Formatters.date) ?? "—"),
            (tr("Type"), entry.kindDescription ?? "—"),
        ])
        if entry.isFolder {
            showFolder(entry)
        } else if Self.isMarkdown(entry) {
            loadText(entry, markdown: true)
        } else if Self.isText(entry) {
            loadText(entry, markdown: false)
        } else {
            showQuickLook(entry.url)
        }
    }

    func showSelection(count: Int, totalSize: Int64) {
        current = nil
        generation += 1
        openButton.isHidden = true
        icon.image = IconProvider.symbol("square.stack.3d.up", size: 16)
        title.stringValue = trCount("items", count)
        setMetadata([(tr("Size"), Formatters.size(totalSize))])
        showMessage(trCount("selected_items", count))
    }

    func clear() {
        current = nil
        generation += 1
        openButton.isHidden = true
        title.stringValue = ""
        icon.image = nil
        setMetadata([])
        showMessage("")
    }

    // MARK: Content

    private func showFolder(_ entry: FileEntry) {
        showMessage(tr("Calculating…"))
        let generation = generation
        let showHidden = Preferences.shared.showHidden
        Task.detached {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: entry.url.path)) ?? []
            let count = showHidden ? names.count : names.filter { !$0.hasPrefix(".") }.count
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.showMessage(count == 0 ? tr("This folder is empty") : trCount("items", count))
            }
        }
    }

    private func loadText(_ entry: FileEntry, markdown: Bool) {
        let generation = generation
        Task.detached {
            let text = Self.readText(entry.url)
            let tokens = markdown || text == nil ? [] : SyntaxHighlighter.tokens(text ?? "", fileName: entry.name)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                guard let text else {
                    self.showQuickLook(entry.url)
                    return
                }
                if markdown {
                    self.codeView.showRichText(MarkdownRenderer.render(text))
                } else {
                    self.codeView.showCode(text, tokens: tokens)
                }
                self.setContent(self.codeView)
            }
        }
    }

    /// Reads up to the preview limit as UTF-8 text, or nil for binary data.
    nonisolated static func readText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: textReadLimit) else { return nil }
        if data.prefix(8_192).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data.dropLast(min(3, data.count)), as: UTF8.self)
    }

    private func showQuickLook(_ url: URL) {
        quickLook.previewItem = url as NSURL
        setContent(quickLook)
    }

    private func showMessage(_ text: String) {
        message.stringValue = text
        setContent(message, centered: true)
    }

    private func setContent(_ child: NSView, centered: Bool = false) {
        if child !== quickLook, quickLook.superview != nil {
            quickLook.previewItem = nil
        }
        content.subviews.forEach { $0.removeFromSuperview() }
        child.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(child)
        if centered {
            NSLayoutConstraint.activate([
                child.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                child.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                child.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -32),
            ])
        } else {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: content.topAnchor),
                child.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }
    }

    private func reloadCurrent() {
        guard let url = current, let entry = try? FileEntry(url: url) else { return }
        current = nil
        show(entry)
    }

    static func isMarkdown(_ entry: FileEntry) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(entry.url.pathExtension.lowercased())
    }

    static func isText(_ entry: FileEntry) -> Bool {
        guard let identifier = entry.typeIdentifier, let type = UTType(identifier) else { return false }
        if type.conforms(to: .html) || type.conforms(to: .rtf) || type.conforms(to: .pdf) { return false }
        if [UTType.text, .sourceCode, .json, .xml, .yaml, .shellScript, .script, .propertyList].contains(
            where: type.conforms(to:))
        {
            return true
        }
        return type.isDynamic && (entry.size ?? .max) <= Int64(textReadLimit)
    }

    // MARK: Layout

    private func setMetadata(_ items: [(String, String)]) {
        metadata.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (label, value) in items {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 2
            let caption = NSTextField.themedLabel(
                label.uppercased(with: Strings.locale), color: \.dimText, scale: 0.75, weight: .semibold
            )
            let text = NSTextField.themedLabel(value, color: \.text, scale: 0.88)
            column.addArrangedSubview(caption)
            column.addArrangedSubview(text)
            metadata.addArrangedSubview(column)
        }
    }

    private func build() {
        let header = ThemedView(fill: \.background)
        header.borderEdges = .minY
        for button in [openButton, closeButton] {
            button.isBordered = false
            button.bezelStyle = .accessoryBarAction
            button.imagePosition = .imageOnly
            button.target = self
            button.contentTintColor = Appearance.shared.palette.dimText
        }
        openButton.image = IconProvider.symbol("arrow.up.forward.app", size: 13)
        openButton.toolTip = tr("Open")
        openButton.setAccessibilityLabel(tr("Open"))
        openButton.action = #selector(openCurrent)
        closeButton.image = IconProvider.symbol("xmark", size: 11, weight: .semibold)
        closeButton.toolTip = tr("Close")
        closeButton.setAccessibilityLabel(tr("Close"))
        closeButton.action = #selector(closePreview)
        closeButton.isHidden = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.lineBreakMode = .byTruncatingMiddle
        metadata.orientation = .horizontal
        metadata.alignment = .top
        metadata.distribution = .fillEqually
        metadata.spacing = 16

        for child in [icon, title, openButton, closeButton, metadata] {
            child.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(child)
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(content)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            icon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            icon.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            closeButton.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            openButton.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            metadata.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            metadata.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            metadata.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -14),
            metadata.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        message.alignment = .center
        message.maximumNumberOfLines = 3
        message.lineBreakMode = .byWordWrapping
    }

    @objc private func openCurrent() {
        guard let current else { return }
        NSWorkspace.shared.open(current)
    }

    @objc private func closePreview() {
        onClose?()
    }
}

@MainActor
final class CodeView: NSView {
    private let scrollView = NSTextView.scrollableTextView()
    private var textView: NSTextView { scrollView.documentView as! NSTextView }
    private let ruler: LineNumberRuler

    override init(frame frameRect: NSRect) {
        ruler = LineNumberRuler(scrollView: scrollView)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalRulerView = ruler
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isAutomaticLinkDetectionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func showCode(_ text: String, tokens: [Token]) {
        let palette = Appearance.shared.palette
        let storage = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Appearance.shared.font(scale: 0.95), .foregroundColor: palette.text,
            ])
        for token in tokens where NSMaxRange(token.range) <= storage.length {
            storage.addAttribute(
                .foregroundColor, value: SyntaxHighlighter.color(token.kind, palette), range: token.range)
        }
        scrollView.rulersVisible = true
        display(storage)
    }

    func showRichText(_ text: NSAttributedString) {
        scrollView.rulersVisible = false
        display(text)
    }

    private func display(_ text: NSAttributedString) {
        textView.textStorage?.setAttributedString(text)
        textView.linkTextAttributes = [
            .foregroundColor: Appearance.shared.palette.accent, .cursor: NSCursor.pointingHand,
        ]
        textView.scroll(.zero)
        ruler.needsDisplay = true
    }
}

final class LineNumberRuler: NSRulerView {
    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 44
        clientView = scrollView.documentView
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
            let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else { return }
        let palette = Appearance.shared.palette
        palette.background.setFill()
        bounds.intersection(rect).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Appearance.shared.font(scale: 0.82), .foregroundColor: palette.dimText,
        ]
        let text = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: characters.location), options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in
            line += 1
        }
        var index = characters.location
        let inset = textView.textContainerInset.height
        while index < NSMaxRange(characters) || (index == 0 && text.length == 0) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY + inset - visible.minY
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 8, y: y + (fragment.height - size.height) / 2),
                withAttributes: attributes)
            line += 1
            if NSMaxRange(lineRange) <= index { break }
            index = NSMaxRange(lineRange)
            if text.length == 0 { break }
        }
    }
}
