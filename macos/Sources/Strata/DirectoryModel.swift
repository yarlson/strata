// SPDX-License-Identifier: MIT

import AppKit
import StrataCore

/// Reports changes to a directory's entries, or the directory itself moving away.
final class DirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onEvent: @escaping @Sendable (_ vanished: Bool) -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [source] in
            onEvent(!source.data.isDisjoint(with: [.delete, .rename]))
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}

/// One directory's entries as the browser shows them: hidden items, sort order,
/// and the pane filter applied. Loads off the main thread and follows changes.
@MainActor
final class DirectoryModel {
    enum State: Equatable {
        case loading, loaded, failed(String)
    }

    static let filterResultLimit = 1_000

    let url: URL
    private(set) var entries: [FileEntry] = []
    private(set) var state: State = .loading
    var onChange: (() -> Void)?
    var onVanish: (() -> Void)?

    var filterText = "" {
        didSet { if filterText != oldValue { filterDidChange() } }
    }
    var isFiltering: Bool { !filterText.isEmpty }
    private(set) var isFilterIncomplete = false

    private var allEntries: [FileEntry] = []
    private var generation = 0
    private var watcher: DirectoryWatcher?
    private var reloadScheduled = false
    private var filterIndex: SearchIndex?
    private var filterTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(url: URL) {
        self.url = url.canonical
        observers.append(
            NotificationCenter.default.addObserver(
                forName: Preferences.didChange, object: nil, queue: .main
            ) { [weak self] note in
                let key = note.userInfo?["key"] as? String
                MainActor.assumeIsolated { self?.preferenceDidChange(key) }
            })
    }

    isolated deinit {
        filterTimer?.invalidate()
        filterIndex?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func load() {
        generation += 1
        let generation = generation
        let url = url
        if watcher == nil {
            watcher = DirectoryWatcher(url: url) { [weak self] vanished in
                MainActor.assumeIsolated { self?.watcherFired(vanished: vanished) }
            }
        }
        Task.detached(priority: .userInitiated) {
            let result = Result { try DirectoryListing.entries(of: url) }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                switch result {
                case let .success(entries):
                    allEntries = entries
                    state = .loaded
                case let .failure(error):
                    allEntries = []
                    state = .failed(Self.message(for: error))
                }
                if isFiltering, Preferences.shared.filterIncludesSubfolders {
                    startFilterIndex()
                }
                recompute()
            }
        }
    }

    func index(of url: URL) -> Int? {
        entries.firstIndex { $0.url == url }
    }

    /// Whether an entry sits below this directory rather than directly in it.
    func isNested(_ entry: FileEntry) -> Bool {
        entry.url.deletingLastPathComponent().canonical != url
    }

    private func watcherFired(vanished: Bool) {
        if vanished, !FileManager.default.fileExists(atPath: url.path) {
            onVanish?()
            return
        }
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadScheduled = false
                self?.load()
            }
        }
    }

    private func preferenceDidChange(_ key: String?) {
        switch key {
        case Preferences.Key.showHidden:
            if filterIndex != nil { startFilterIndex() }
            recompute()
        case Preferences.Key.sortKey, Preferences.Key.sortAscending:
            recompute()
        case Preferences.Key.filterIncludesSubfolders:
            filterDidChange()
        default:
            break
        }
    }

    private func filterDidChange() {
        filterIndex?.cancel()
        filterIndex = nil
        filterTimer?.invalidate()
        filterTimer = nil
        if isFiltering, Preferences.shared.filterIncludesSubfolders {
            startFilterIndex()
        }
        recompute()
    }

    private func startFilterIndex() {
        filterIndex?.cancel()
        let index = SearchIndex(
            roots: [url],
            exclusions: SearchExclusions(rules: [], home: FileManager.default.homeDirectoryForCurrentUser),
            includeHidden: Preferences.shared.showHidden,
            maxEntries: 50_000, timeBudget: 5
        )
        filterIndex = index
        index.start()
        filterTimer?.invalidate()
        filterTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let index = self.filterIndex else { return }
                if index.snapshot().isFinished {
                    self.filterTimer?.invalidate()
                    self.filterTimer = nil
                }
                self.recompute()
            }
        }
    }

    private func recompute() {
        let preferences = Preferences.shared
        let showHidden = preferences.showHidden
        let order = preferences.sortOrder
        guard let query = NameQuery(filterText) else {
            isFilterIncomplete = false
            entries = order.sorted(allEntries.filter { showHidden || !$0.isHidden })
            onChange?()
            return
        }
        if let index = filterIndex {
            let snapshot = index.snapshot()
            var matches: [(NameMatch, Int, IndexedItem)] = []
            for item in snapshot.items.joined() {
                if let match = query.match(item.name) {
                    matches.append((match, item.url.pathComponents.count, item))
                }
            }
            matches.sort { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2.name.localizedStandardCompare(rhs.2.name) == .orderedAscending
            }
            entries = matches.prefix(Self.filterResultLimit).compactMap { try? FileEntry(url: $0.2.url) }
            isFilterIncomplete =
                !snapshot.isFinished || snapshot.isTruncated
                || matches.count > Self.filterResultLimit
        } else {
            let visible = allEntries.filter { showHidden || !$0.isHidden }
            let matched = visible.compactMap { entry in query.match(entry.name).map { ($0, entry) } }
            entries = matched.sorted { lhs, rhs in
                lhs.0 != rhs.0 ? lhs.0 < rhs.0 : order.areInIncreasingOrder(lhs.1, rhs.1)
            }.map(\.1)
            isFilterIncomplete = false
        }
        onChange?()
    }

    static func message(for error: Error) -> String {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
            return tr(
                "Strata does not have permission to open this folder. Allow access in System Settings → Privacy & Security → Files and Folders or Full Disk Access."
            )
        }
        return error.localizedDescription
    }
}
