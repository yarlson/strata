// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

enum ViewMode: String, CaseIterable {
    case columns, icons, list
}

enum Density: String, CaseIterable {
    case compact, airy
}

/// Application-wide settings stored in user defaults. Every change posts
/// `Preferences.didChange` so open windows update live.
@MainActor
final class Preferences {
    static let shared = Preferences()
    nonisolated static let didChange = Notification.Name("StrataPreferencesDidChange")
    nonisolated static let systemLanguage = "system"
    nonisolated static let systemThemeID = "macos"

    enum Key {
        static let viewMode = "viewMode"
        static let showHidden = "showHidden"
        static let themeID = "themeID"
        static let density = "density"
        static let textSize = "textSize"
        static let restoreTabs = "restoreTabs"
        static let showFooter = "showFooter"
        static let filterIncludesSubfolders = "filterIncludesSubfolders"
        static let language = "language"
        static let searchExclusions = "searchExclusions"
        static let pinned = "pinned"
        static let sortKey = "sortKey"
        static let sortAscending = "sortAscending"
        static let showPreview = "showPreview"
        static let sessionTabs = "sessionTabs"
        static let sessionActiveTab = "sessionActiveTab"
    }

    nonisolated static let defaultTextSize: CGFloat = 13
    nonisolated static let textSizes: ClosedRange<CGFloat> = 10...20

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.viewMode: ViewMode.columns.rawValue,
            Key.showHidden: false,
            Key.themeID: ThemeCatalog.defaultThemeID,
            Key.density: Density.compact.rawValue,
            Key.textSize: Double(Self.defaultTextSize),
            Key.restoreTabs: true,
            Key.showFooter: true,
            Key.filterIncludesSubfolders: true,
            Key.language: Self.systemLanguage,
            Key.searchExclusions: [String](),
            Key.pinned: [String](),
            Key.sortKey: SortKey.name.rawValue,
            Key.sortAscending: true,
            Key.showPreview: true,
        ])
    }

    var viewMode: ViewMode {
        get { ViewMode(rawValue: defaults.string(forKey: Key.viewMode) ?? "") ?? .columns }
        set { set(newValue.rawValue, Key.viewMode) }
    }

    var showHidden: Bool {
        get { defaults.bool(forKey: Key.showHidden) }
        set { set(newValue, Key.showHidden) }
    }

    var themeID: String {
        get { defaults.string(forKey: Key.themeID) ?? ThemeCatalog.defaultThemeID }
        set { set(newValue, Key.themeID) }
    }

    var density: Density {
        get { Density(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .compact }
        set { set(newValue.rawValue, Key.density) }
    }

    var textSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.textSize)).clamped(to: Self.textSizes) }
        set { set(Double(newValue.clamped(to: Self.textSizes)), Key.textSize) }
    }

    var restoreTabs: Bool {
        get { defaults.bool(forKey: Key.restoreTabs) }
        set { set(newValue, Key.restoreTabs) }
    }

    var showFooter: Bool {
        get { defaults.bool(forKey: Key.showFooter) }
        set { set(newValue, Key.showFooter) }
    }

    var filterIncludesSubfolders: Bool {
        get { defaults.bool(forKey: Key.filterIncludesSubfolders) }
        set { set(newValue, Key.filterIncludesSubfolders) }
    }

    var language: String {
        get { defaults.string(forKey: Key.language) ?? Self.systemLanguage }
        set { set(newValue, Key.language) }
    }

    var searchExclusions: [String] {
        get { defaults.stringArray(forKey: Key.searchExclusions) ?? [] }
        set { set(newValue, Key.searchExclusions) }
    }

    var pinned: [URL] {
        get { (defaults.stringArray(forKey: Key.pinned) ?? []).map { URL(filePath: $0, directoryHint: .notDirectory) } }
        set { set(newValue.map(\.path), Key.pinned) }
    }

    var sortOrder: StrataCore.SortOrder {
        get {
            StrataCore.SortOrder(
                key: SortKey(rawValue: defaults.string(forKey: Key.sortKey) ?? "") ?? .name,
                ascending: defaults.bool(forKey: Key.sortAscending)
            )
        }
        set {
            defaults.set(newValue.key.rawValue, forKey: Key.sortKey)
            set(newValue.ascending, Key.sortAscending)
        }
    }

    var showPreview: Bool {
        get { defaults.bool(forKey: Key.showPreview) }
        set { set(newValue, Key.showPreview) }
    }

    var session: (tabs: [URL], active: Int) {
        get {
            let tabs = (defaults.stringArray(forKey: Key.sessionTabs) ?? []).map { URL(fileURLWithPath: $0) }
            return (tabs, defaults.integer(forKey: Key.sessionActiveTab))
        }
        set {
            defaults.set(newValue.tabs.map(\.path), forKey: Key.sessionTabs)
            defaults.set(newValue.active, forKey: Key.sessionActiveTab)
        }
    }

    func isPinned(_ url: URL) -> Bool {
        pinned.contains(url.canonical)
    }

    func togglePin(_ url: URL) {
        let url = url.canonical
        pinned = isPinned(url) ? pinned.filter { $0 != url } : pinned + [url]
    }

    private func set(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["key": key])
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
