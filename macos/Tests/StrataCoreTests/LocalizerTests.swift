// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

private let package = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let catalogs = package.appendingPathComponent("Resources/locales")

struct LocalizerTests {
    @Test(arguments: [
        ("ru", 1, PluralCategory.one), ("ru", 21, .one), ("ru", 11, .many),
        ("ru", 3, .few), ("ru", 13, .many), ("ru", 25, .many),
        ("fr", 0, .one), ("fr", 1, .one), ("fr", 2, .other),
        ("en", 0, .other), ("en", 1, .one), ("ja", 1, .other),
    ])
    func selectsPluralCategories(locale: String, count: Int, expected: PluralCategory) {
        #expect(Localizer.pluralCategory(locale: locale, count: count) == expected)
    }

    @Test(arguments: [
        (["de-DE"], "de"), (["pt-PT"], "pt-BR"), (["zh-Hans-CN"], "zh-CN"),
        (["zh-Hant-TW", "ja-JP"], "ja"), (["nl-NL"], "en"), (["en_GB"], "en"),
    ])
    func resolvesPreferredLanguages(preferred: [String], expected: String) {
        #expect(Localizer.resolveLocale(preferred: preferred) == expected)
    }

    @Test func interpolationDoesNotExpandInsertedText() {
        let text = Localizer.interpolate("Open %{name}?", ["name": "%{name} copy"])
        #expect(text == "Open %{name} copy?")
    }

    @Test func translatesMessagesAndCounts() {
        let german = Localizer(locale: "de", catalogDirectory: catalogs)
        #expect(german.tr("Cancel") == "Abbrechen")
        #expect(german.count("items", 1) == "1 Element")
        let english = Localizer(locale: "en", catalogDirectory: catalogs)
        #expect(english.tr("keys.name.space") == "Space")
        #expect(english.count("items", 1_200) == "1,200 items")
    }

    @Test func missingMessagesFallBackToEnglishKeys() {
        let french = Localizer(locale: "fr", catalogDirectory: catalogs)
        #expect(french.tr("Unknown message %{x}", ["x": "1"]) == "Unknown message 1")
    }

    @Test func catalogsCoverEveryLanguageAndKeepPlaceholders() throws {
        let english = try catalog("en")
        #expect(!english.isEmpty)
        for locale in Localizer.supportedLocales {
            let translated = try catalog(locale)
            #expect(Set(translated.keys) == Set(english.keys), "\(locale) keys differ from English")
            for (key, value) in translated {
                #expect(placeholders(value) == placeholders(key), "\(locale): \(key)")
            }
        }
    }

    @Test func everyAppMessageHasACatalogEntry() throws {
        let known = Set(try catalog("en").keys)
        let sources = package.appendingPathComponent("Sources/Strata")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        let call = /\btr\(\s*"((?:[^"\\]|\\.)*)"/
        var missing: [String] = []
        var checked = 0
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: call) {
                let key = String(match.output.1).replacingOccurrences(of: "\\\"", with: "\"")
                checked += 1
                if !known.contains(key) { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        #expect(checked > 100, "The message scan found too few tr() calls")
        #expect(missing.isEmpty, "Untranslated messages: \(missing)")
    }

    private func catalog(_ locale: String) throws -> [String: String] {
        let data = try Data(contentsOf: catalogs.appendingPathComponent("\(locale).json"))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func placeholders(_ text: String) -> Set<String> {
        let regex = /%\{[a-z_0-9]+\}/
        return Set(text.matches(of: regex).map { String($0.output) })
    }
}
