// SPDX-License-Identifier: MIT

import AppKit
import CoreText
import StrataCore

/// The semantic colors and fonts every Strata view draws with.
struct Palette: @unchecked Sendable {
    var background: NSColor
    var surface: NSColor
    var text: NSColor
    var accent: NSColor
    var danger: NSColor
    var muted: NSColor
    var highlight: NSColor
    var border: NSColor
    var dimText: NSColor
    var keyword: NSColor
    var string: NSColor
    var constant: NSColor
    var type: NSColor
    var preprocessor: NSColor
    /// nil follows the system light or dark appearance.
    var appearance: NSAppearance?

    init(theme: Theme) {
        func color(_ rgba: RGBA) -> NSColor {
            NSColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        }
        background = color(theme.background)
        surface = color(theme.surface)
        text = color(theme.text)
        accent = color(theme.accent)
        danger = color(theme.danger)
        muted = color(theme.muted)
        highlight = color(theme.highlight)
        border = color(theme.border)
        dimText = color(theme.dimText)
        keyword = color(theme.syntax.keyword)
        string = color(theme.syntax.string)
        constant = color(theme.syntax.constant)
        type = color(theme.syntax.type)
        preprocessor = color(theme.syntax.preprocessor)
        appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    static let system = Palette(
        background: .windowBackgroundColor, surface: .controlBackgroundColor,
        text: .labelColor, accent: .controlAccentColor, danger: .systemRed,
        muted: .quaternarySystemFill, highlight: .unemphasizedSelectedContentBackgroundColor,
        border: .separatorColor, dimText: .secondaryLabelColor, keyword: .systemPurple,
        string: .systemGreen, constant: .systemOrange, type: .systemTeal,
        preprocessor: .systemBrown, appearance: nil
    )

    private init(
        background: NSColor, surface: NSColor, text: NSColor, accent: NSColor, danger: NSColor,
        muted: NSColor, highlight: NSColor, border: NSColor, dimText: NSColor, keyword: NSColor,
        string: NSColor, constant: NSColor, type: NSColor, preprocessor: NSColor,
        appearance: NSAppearance?
    ) {
        self.background = background
        self.surface = surface
        self.text = text
        self.accent = accent
        self.danger = danger
        self.muted = muted
        self.highlight = highlight
        self.border = border
        self.dimText = dimText
        self.keyword = keyword
        self.string = string
        self.constant = constant
        self.type = type
        self.preprocessor = preprocessor
        self.appearance = appearance
    }

    var selection: NSColor { accent.withAlphaComponent(0.22) }
}

/// Owns the active theme, density, and text size, and announces changes.
@MainActor
final class Appearance {
    static let shared = Appearance()
    nonisolated static let didChange = Notification.Name("StrataAppearanceDidChange")
    static let fontFamily = "JetBrains Mono"

    let themes: [Theme]
    private(set) var palette: Palette = .system
    private(set) var textSize: CGFloat = Preferences.defaultTextSize
    private(set) var density: Density = .compact

    private init() {
        if let url = Bundle.main.url(forResource: "JetBrainsMono[wght]", withExtension: "ttf", subdirectory: "fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let catalog = Bundle.main.url(forResource: "catalog", withExtension: "toml", subdirectory: "themes")
        themes = catalog.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(ThemeCatalog.parse) ?? []
        load()
        NotificationCenter.default.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                if [Preferences.Key.themeID, Preferences.Key.density, Preferences.Key.textSize].contains(key) {
                    Appearance.shared.load()
                    NotificationCenter.default.post(name: Appearance.didChange, object: Appearance.shared)
                }
            }
        }
    }

    func font(scale: CGFloat = 1, weight: NSFont.Weight = .regular) -> NSFont {
        let size = (textSize * scale).rounded()
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: Self.fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    var rowHeight: CGFloat {
        (textSize * (density == .compact ? 1.75 : 2.2)).rounded()
    }

    /// Reads the theme, text size, and density preferences. Callers announce the change.
    private func load() {
        let preferences = Preferences.shared
        let id = preferences.themeID
        palette =
            id == Preferences.systemThemeID
            ? .system
            : (themes.first { $0.id == id } ?? themes.first { $0.id == ThemeCatalog.defaultThemeID }).map(Palette.init)
                ?? .system
        textSize = preferences.textSize
        density = preferences.density
        NSApp?.appearance = palette.appearance
    }
}
