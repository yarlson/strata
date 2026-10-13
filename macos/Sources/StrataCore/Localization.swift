// SPDX-License-Identifier: MIT

import Foundation

public enum PluralCategory: String, Sendable {
    case one, few, many, other
}

/// Looks up English-keyed messages in Strata's shared JSON catalogs and the
/// macOS overlay catalog, with English fallback.
public struct Localizer: Sendable {
    public static let supportedLocales = [
        "en", "fr", "de", "es", "ja", "pt-BR", "ko", "vi", "it", "ru", "zh-CN",
    ]

    public let locale: String
    private let messages: [String: String]
    private let fallback: [String: String]
    private let counts: [String: [String: String]]

    /// `catalogDirectory` holds `<locale>.json`, `messages/<locale>.json`, and
    /// `counts.json`; `overlayDirectory` holds macOS-only `<locale>.json` files.
    public init(locale: String, catalogDirectory: URL, overlayDirectory: URL) {
        self.locale = locale
        messages = Self.flatCatalog(locale, catalogDirectory, overlayDirectory)
        fallback = locale == "en" ? [:] : Self.flatCatalog("en", catalogDirectory, overlayDirectory)
        counts = Self.countCatalog(catalogDirectory.appendingPathComponent("counts.json"))
    }

    /// A localizer that returns every key unchanged.
    public init() {
        locale = "en"
        messages = [:]
        fallback = [:]
        counts = [:]
    }

    public func tr(_ key: String, _ values: [String: String] = [:]) -> String {
        let template = messages[key] ?? fallback[key] ?? key
        return Self.interpolate(template, values)
    }

    /// Formats `counts.<kind>.<category>` for `count`, for example "3 items".
    public func count(_ kind: String, _ count: Int, _ values: [String: String] = [:]) -> String {
        let category = Self.pluralCategory(locale: locale, count: count)
        let forms =
            counts["counts.\(kind).\(category.rawValue)"]
            ?? counts["counts.\(kind).other"]
        let template = forms?[locale] ?? forms?["en"] ?? "%{count}"
        var arguments = values
        arguments["count"] = count.formatted(.number.locale(Locale(identifier: locale)))
        return Self.interpolate(template, arguments)
    }

    public static func pluralCategory(locale: String, count: Int) -> PluralCategory {
        let value = abs(count)
        switch locale {
        case "ja", "ko", "vi", "zh-CN":
            return .other
        case "fr", "pt-BR":
            return value <= 1 ? .one : .other
        case "ru":
            if value % 10 == 1 && value % 100 != 11 { return .one }
            if (2...4).contains(value % 10) && !(12...14).contains(value % 100) { return .few }
            return .many
        default:
            return value == 1 ? .one : .other
        }
    }

    /// Picks the first supported locale from preferred language identifiers
    /// such as `pt-BR`, `zh-Hans-CN`, or `de_DE`.
    public static func resolveLocale(preferred: [String]) -> String {
        for identifier in preferred {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            let parts = normalized.split(separator: "-").map(String.init)
            guard let language = parts.first?.lowercased() else { continue }
            switch language {
            case "zh":
                if parts.contains(where: { ["Hant", "TW", "HK", "MO"].contains($0) }) { continue }
                return "zh-CN"
            case "pt":
                return "pt-BR"
            default:
                if supportedLocales.contains(language) { return language }
            }
        }
        return "en"
    }

    /// Replaces each `%{name}` with its value. Inserted values are never rescanned.
    public static func interpolate(_ template: String, _ values: [String: String]) -> String {
        guard !values.isEmpty, template.contains("%{") else { return template }
        var result = ""
        var rest = template[...]
        while let start = rest.range(of: "%{") {
            result += rest[..<start.lowerBound]
            let afterStart = rest[start.upperBound...]
            guard let end = afterStart.firstIndex(of: "}") else {
                rest = rest[start.lowerBound...]
                break
            }
            let name = String(afterStart[..<end])
            result += values[name] ?? "%{\(name)}"
            rest = afterStart[afterStart.index(after: end)...]
        }
        return result + rest
    }

    private static func flatCatalog(
        _ locale: String, _ catalogDirectory: URL, _ overlayDirectory: URL
    ) -> [String: String] {
        var merged: [String: String] = [:]
        for url in [
            catalogDirectory.appendingPathComponent("\(locale).json"),
            catalogDirectory.appendingPathComponent("messages/\(locale).json"),
            overlayDirectory.appendingPathComponent("\(locale).json"),
        ] {
            guard let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for case let (key, value as String) in object {
                merged[key] = value
            }
        }
        return merged
    }

    private static func countCatalog(_ url: URL) -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var forms: [String: [String: String]] = [:]
        for case let (key, value as [String: String]) in object {
            forms[key] = value
        }
        return forms
    }
}
