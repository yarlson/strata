// SPDX-License-Identifier: MIT

import Foundation
import StrataCore

enum Strings {
    /// The language is chosen once at launch; changing it takes effect after a restart.
    static let localizer: Localizer = {
        guard let resources = Bundle.main.resourceURL else { return Localizer() }
        let choice = UserDefaults.standard.string(forKey: Preferences.Key.language) ?? Preferences.systemLanguage
        let locale =
            Localizer.supportedLocales.contains(choice)
            ? choice
            : Localizer.resolveLocale(preferred: Locale.preferredLanguages)
        return Localizer(locale: locale, catalogDirectory: resources.appendingPathComponent("locales"))
    }()

    static var locale: Locale { Locale(identifier: localizer.locale) }
}

func tr(_ key: String, _ values: [String: String] = [:]) -> String {
    Strings.localizer.tr(key, values)
}

func trCount(_ kind: String, _ count: Int) -> String {
    Strings.localizer.count(kind, count)
}

/// Quotes a name the way the active language quotes names inside sentences.
func quoted(_ name: String) -> String {
    switch Strings.localizer.locale {
    case "de": "„\(name)“"
    case "fr": "«\u{00A0}\(name)\u{00A0}»"
    case "ru": "«\(name)»"
    case "ja": "「\(name)」"
    default: "“\(name)”"
    }
}
