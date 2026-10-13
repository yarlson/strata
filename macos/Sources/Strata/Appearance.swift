// SPDX-License-Identifier: MIT

import AppKit

/// Owns the text size and density preferences, and announces changes. Colors
/// come from the system and follow its light or dark appearance and accent.
@MainActor
final class Appearance {
    static let shared = Appearance()
    nonisolated static let didChange = Notification.Name("StrataAppearanceDidChange")

    private(set) var textSize: CGFloat = Preferences.defaultTextSize
    private(set) var density: Density = .compact

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            MainActor.assumeIsolated {
                if [Preferences.Key.density, Preferences.Key.textSize].contains(key) {
                    Appearance.shared.load()
                    NotificationCenter.default.post(name: Appearance.didChange, object: Appearance.shared)
                }
            }
        }
    }

    func font(scale: CGFloat = 1, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: (textSize * scale).rounded(), weight: weight)
    }

    func codeFont(scale: CGFloat = 1) -> NSFont {
        .monospacedSystemFont(ofSize: (textSize * scale).rounded(), weight: .regular)
    }

    var rowHeight: CGFloat {
        (textSize * (density == .compact ? 1.75 : 2.2)).rounded()
    }

    /// Reads the text size and density preferences. Callers announce the change.
    private func load() {
        let preferences = Preferences.shared
        textSize = preferences.textSize
        density = preferences.density
    }
}
