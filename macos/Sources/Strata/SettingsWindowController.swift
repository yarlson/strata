// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Settings: General, Appearance, and Search. Every control edits a
/// preference; windows follow through `Preferences.didChange`.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let pages: [(NSViewController, String, String)] = [
            (GeneralSettings(), tr("General"), "gearshape"),
            (AppearanceSettings(), tr("Appearance"), "textformat.size"),
            (SearchSettings(), tr("Search"), "magnifyingglass"),
        ]
        for (controller, title, symbol) in pages {
            controller.title = title
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = tr("Settings")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 480))
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
private func checkbox(_ title: String, _ value: Bool, _ handler: @escaping (Bool) -> Void) -> NSButton {
    let button = ActionCheckbox(title: title, handler: handler)
    button.state = value ? .on : .off
    return button
}

private final class ActionCheckbox: NSButton {
    private let handler: (Bool) -> Void

    init(title: String, handler: @escaping (Bool) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        target = self
        action = #selector(toggled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func toggled() { handler(state == .on) }
}

private final class ActionPopUp: NSPopUpButton {
    private let handler: (Int) -> Void

    init(items: [String], selected: Int, handler: @escaping (Int) -> Void) {
        self.handler = handler
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: items)
        selectItem(at: selected)
        target = self
        action = #selector(changed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed() { handler(indexOfSelectedItem) }
}

private final class ActionSegments: NSSegmentedControl {
    private let handler: (Int) -> Void

    init(labels: [String], selected: Int, handler: @escaping (Int) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        segmentCount = labels.count
        for (index, label) in labels.enumerated() { setLabel(label, forSegment: index) }
        trackingMode = .selectOne
        selectedSegment = selected
        target = self
        action = #selector(changed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed() { handler(selectedSegment) }
}

@MainActor
private func formGrid(_ rows: [(String, NSView)]) -> NSGridView {
    let grid = NSGridView(
        views: rows.map { label, view in
            [NSTextField(labelWithString: label.isEmpty ? "" : label + ":"), view]
        })
    grid.column(at: 0).xPlacement = .trailing
    grid.rowAlignment = .firstBaseline
    grid.rowSpacing = 12
    grid.columnSpacing = 10
    return grid
}

@MainActor
private func pad(_ view: NSView) -> NSView {
    let container = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
        view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
        view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
        container.widthAnchor.constraint(equalToConstant: 560),
    ])
    return container
}

private final class GeneralSettings: NSViewController {
    static let languageNames: [(String, String)] = [
        ("en", "English"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español"), ("ja", "日本語"),
        ("pt-BR", "Português (Brasil)"), ("ko", "한국어"), ("vi", "Tiếng Việt"), ("it", "Italiano"),
        ("ru", "Русский"), ("zh-CN", "简体中文"),
    ]

    override func loadView() {
        let preferences = Preferences.shared
        let modes = ViewMode.allCases
        let viewPopUp = ActionPopUp(
            items: [tr("Columns"), tr("Icons"), tr("List")],
            selected: modes.firstIndex(of: preferences.viewMode) ?? 0
        ) { Preferences.shared.viewMode = modes[$0] }
        let codes = [Preferences.systemLanguage] + Self.languageNames.map(\.0)
        let languagePopUp = ActionPopUp(
            items: [tr("Auto-detect")] + Self.languageNames.map(\.1),
            selected: codes.firstIndex(of: preferences.language) ?? 0
        ) { Preferences.shared.language = codes[$0] }
        let note = NSTextField(
            wrappingLabelWithString: tr("Auto-detect follows your system language. Restart Strata to apply changes."))
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let language = NSStackView(views: [languagePopUp, note])
        language.orientation = .vertical
        language.alignment = .leading
        view = pad(
            formGrid([
                (
                    tr("Startup"),
                    checkbox(tr("Restore open tabs"), preferences.restoreTabs) { Preferences.shared.restoreTabs = $0 }
                ),
                (tr("Default view"), viewPopUp),
                ("", checkbox(tr("Show hidden files"), preferences.showHidden) { Preferences.shared.showHidden = $0 }),
                (
                    "",
                    checkbox(tr("Show shortcut footer"), preferences.showFooter) { Preferences.shared.showFooter = $0 }
                ),
                ("", checkbox(tr("Show preview"), preferences.showPreview) { Preferences.shared.showPreview = $0 }),
                (
                    tr("Filter"),
                    checkbox(tr("Include subfolders"), preferences.filterIncludesSubfolders) {
                        Preferences.shared.filterIncludesSubfolders = $0
                    }
                ),
                (tr("Language"), language),
            ]))
    }
}

private final class AppearanceSettings: NSViewController {
    private let textSizeLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let preferences = Preferences.shared
        let density = ActionSegments(
            labels: [tr("Compact"), tr("Airy")], selected: preferences.density == .compact ? 0 : 1
        ) { Preferences.shared.density = $0 == 0 ? .compact : .airy }
        let stepper = NSStepper()
        stepper.minValue = Double(Preferences.textSizes.lowerBound)
        stepper.maxValue = Double(Preferences.textSizes.upperBound)
        stepper.increment = 1
        stepper.doubleValue = Double(preferences.textSize)
        stepper.target = self
        stepper.action = #selector(textSizeChanged(_:))
        textSizeLabel.stringValue = "\(Int(preferences.textSize)) pt"
        let size = NSStackView(views: [stepper, textSizeLabel])
        size.orientation = .horizontal
        view = pad(
            formGrid([
                (tr("Density"), density),
                (tr("Text size"), size),
            ]))
    }

    @objc private func textSizeChanged(_ sender: NSStepper) {
        Preferences.shared.textSize = CGFloat(sender.doubleValue)
        textSizeLabel.stringValue = "\(Int(Preferences.shared.textSize)) pt"
    }
}

private final class SearchSettings: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let field = NSTextField()
    private let error = NSTextField(labelWithString: "")

    override func loadView() {
        let intro = NSTextField(
            wrappingLabelWithString: tr(
                "Global search covers your home folder and mounted local drives. Excluded folder names match at any depth; absolute paths exclude only that folder."
            ))
        intro.preferredMaxLayoutWidth = 480
        field.placeholderString = tr("Folder name or absolute path")
        field.target = self
        field.action = #selector(add)
        let addButton = NSButton(title: tr("Add"), target: self, action: #selector(add))
        let browse = NSButton(title: tr("Browse…"), target: self, action: #selector(browse))
        let remove = NSButton(title: tr("Remove"), target: self, action: #selector(removeSelected))
        error.textColor = .systemRed
        let form = NSStackView(views: [field, addButton, browse])
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        table.addTableColumn(NSTableColumn(identifier: .init("rule")))
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true
        let stack = NSStackView(views: [
            NSTextField(labelWithString: tr("Global search exclusions")), intro, form, error, scroll, remove,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        view = pad(stack)
    }

    @objc private func add() {
        let rule = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard SearchExclusions.isValid(rule) else {
            error.stringValue = tr(
                "Enter a folder name or an absolute path inside a drive, not the root or home folder.")
            return
        }
        error.stringValue = ""
        var rules = Preferences.shared.searchExclusions
        if !rules.contains(rule) { rules.append(rule) }
        Preferences.shared.searchExclusions = rules
        field.stringValue = ""
        table.reloadData()
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.field.stringValue = url.path
            self?.add()
        }
    }

    @objc private func removeSelected() {
        let row = table.selectedRow
        var rules = Preferences.shared.searchExclusions
        guard rules.indices.contains(row) else { return }
        rules.remove(at: row)
        Preferences.shared.searchExclusions = rules
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Preferences.shared.searchExclusions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: Preferences.shared.searchExclusions[row])
    }
}
