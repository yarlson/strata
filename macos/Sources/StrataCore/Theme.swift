// SPDX-License-Identifier: MIT

import Foundation

public struct RGBA: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#rrggbb` or `#rrggbbaa`.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : hex[...]
        guard digits.count == 6 || digits.count == 8,
            let value = UInt64(digits, radix: 16)
        else { return nil }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        red = Double((rgb >> 16) & 0xff) / 255
        green = Double((rgb >> 8) & 0xff) / 255
        blue = Double(rgb & 0xff) / 255
        alpha = hasAlpha ? Double(value & 0xff) / 255 : 1
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

public struct SyntaxPalette: Hashable, Sendable {
    public var keyword: RGBA
    public var string: RGBA
    public var constant: RGBA
    public var type: RGBA
    public var preprocessor: RGBA
}

public struct Theme: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var background: RGBA
    public var surface: RGBA
    public var text: RGBA
    public var accent: RGBA
    public var danger: RGBA
    public var muted: RGBA
    public var highlight: RGBA
    public var border: RGBA
    public var dimText: RGBA
    public var syntax: SyntaxPalette

    public var isDark: Bool { background.luminance < 0.5 }
}

/// Reads Strata's theme catalog: `[[themes]]` tables of `key = "#rrggbb"` pairs.
public enum ThemeCatalog {
    public static let defaultThemeID = "azure-glow"

    public static func parse(_ toml: String) -> [Theme] {
        var tables: [[String: String]] = []
        for rawLine in toml.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[[themes]]" {
                tables.append([:])
                continue
            }
            guard !tables.isEmpty, !line.hasPrefix("#"),
                let (key, value) = keyValue(line)
            else { continue }
            tables[tables.count - 1][key] = value
        }
        return tables.compactMap(theme)
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let rest = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("\""),
            let closing = rest.dropFirst().firstIndex(of: "\"")
        else { return nil }
        return (key, String(rest[rest.index(after: rest.startIndex)..<closing]))
    }

    private static func theme(_ table: [String: String]) -> Theme? {
        func color(_ key: String) -> RGBA? { table[key].flatMap(RGBA.init(hex:)) }
        guard let id = table["id"], let name = table["name"],
            let background = color("background"), let surface = color("surface"),
            let text = color("text"), let accent = color("accent"),
            let danger = color("danger"), let muted = color("muted"),
            let highlight = color("highlight"), let border = color("border"),
            let dimText = color("dim_text")
        else { return nil }
        let syntax = SyntaxPalette(
            keyword: color("syntax_keyword") ?? accent,
            string: color("syntax_string") ?? text,
            constant: color("syntax_constant") ?? accent,
            type: color("syntax_type") ?? text,
            preprocessor: color("syntax_preprocessor") ?? dimText
        )
        return Theme(
            id: id, name: name, background: background, surface: surface, text: text,
            accent: accent, danger: danger, muted: muted, highlight: highlight,
            border: border, dimText: dimText, syntax: syntax
        )
    }
}
