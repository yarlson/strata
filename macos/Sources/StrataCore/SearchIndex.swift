// SPDX-License-Identifier: MIT

import Foundation

public struct IndexedItem: Sendable {
    public let url: URL
    public let name: String
    public let isFolder: Bool
    let foldedName: [Character]
    let foldedParent: [Character]
}

public struct SearchExclusions: Sendable {
    /// Generated trees pruned everywhere, as trailing path components.
    static let generatedTrees: [[String]] = [
        [".cache"], [".cargo", "registry"], [".cargo", "git"], [".rustup", "downloads"],
        [".gradle", "caches"], [".gradle", "wrapper", "dists"], [".m2", "repository"],
        [".npm", "_cacache"], [".bun", "install", "cache"], ["go", "pkg", "mod"],
        ["node_modules"], ["target"], [".venv"], ["__pycache__"], [".Trash"],
        ["Library", "Caches"], ["Library", "Containers"], ["Library", "Group Containers"],
        ["Library", "Developer"], ["Library", "Metadata"],
    ]

    private let folderNames: Set<String>
    private let paths: [String]

    /// `rules` are folder names (any depth, case-insensitive) or absolute
    /// directory paths (that subtree, case-sensitive). `~/` expands to `home`.
    public init(rules: [String], home: URL) {
        var names = Set<String>()
        var paths: [String] = []
        for rule in rules.map({ $0.trimmingCharacters(in: .whitespaces) }) where Self.isValid(rule) {
            if rule.hasPrefix("~/") {
                paths.append(home.appendingPathComponent(String(rule.dropFirst(2))).standardizedFileURL.path)
            } else if rule.hasPrefix("/") {
                paths.append(URL(fileURLWithPath: rule).standardizedFileURL.path)
            } else {
                names.insert(rule.lowercased())
            }
        }
        folderNames = names
        self.paths = paths
    }

    /// Root, the whole home folder, relative paths, and `..` are rejected.
    public static func isValid(_ rule: String) -> Bool {
        guard !rule.isEmpty, rule != "/", rule != "~", rule != "~/" else { return false }
        if rule.hasPrefix("/") || rule.hasPrefix("~/") {
            return !rule.split(separator: "/").contains("..")
        }
        return !rule.contains("/") && rule != "." && rule != ".."
    }

    func excludes(_ components: [String], path: String) -> Bool {
        if let last = components.last, folderNames.contains(last.lowercased()) { return true }
        if paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return Self.generatedTrees.contains { components.count >= $0.count && Array(components.suffix($0.count)) == $0 }
    }
}

/// A bounded background index of names below a set of roots. Readers see the
/// items found so far while traversal continues.
public final class SearchIndex: @unchecked Sendable {
    public static let resultLimit = 100
    static let chunkSize = 4096

    public let roots: [URL]
    private let exclusions: SearchExclusions
    private let includeHidden: Bool
    private let maxEntries: Int
    private let maxDepth: Int
    private let timeBudget: TimeInterval

    private let lock = NSLock()
    private var chunks: [[IndexedItem]] = []
    private var pending: [IndexedItem] = []
    private var isFinished = false
    private var isTruncated = false
    private var isCancelled = false

    public init(
        roots: [URL], exclusions: SearchExclusions, includeHidden: Bool,
        maxEntries: Int = 200_000, maxDepth: Int = 64, timeBudget: TimeInterval = 10
    ) {
        self.roots = roots
        self.exclusions = exclusions
        self.includeHidden = includeHidden
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.timeBudget = timeBudget
    }

    public func start() {
        let thread = Thread { [self] in traverse() }
        thread.name = "search-index"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    public func cancel() {
        lock.withLock { isCancelled = true }
    }

    public struct Snapshot: Sendable {
        public let items: [[IndexedItem]]
        public let isFinished: Bool
        public let isTruncated: Bool
        public var count: Int { items.reduce(0) { $0 + $1.count } }
    }

    public func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(items: chunks + [pending], isFinished: isFinished, isTruncated: isTruncated)
        }
    }

    public static func search(
        _ query: FuzzyQuery, in snapshot: Snapshot, foldersOnly: Bool = false,
        limit: Int = resultLimit
    ) -> [IndexedItem] {
        var scored: [(Int, IndexedItem)] = []
        for chunk in snapshot.items {
            for item in chunk where !foldersOnly || item.isFolder {
                if let score = query.score(name: item.foldedName, path: item.foldedParent) {
                    scored.append((score, item))
                }
            }
        }
        scored.sort { lhs, rhs in
            lhs.0 != rhs.0 ? lhs.0 > rhs.0 : lhs.1.url.path.count < rhs.1.url.path.count
        }
        return scored.prefix(limit).map(\.1)
    }

    private func traverse() {
        let deadline = Date().addingTimeInterval(timeBudget)
        var count = 0
        var queue: [(URL, [String], Int)] = roots.map { ($0, $0.pathComponents, 0) }
        var head = 0
        defer { finish(truncated: head < queue.count) }
        while head < queue.count {
            if lock.withLock({ isCancelled }) || Date() > deadline || count >= maxEntries { return }
            let (directory, components, depth) = queue[head]
            head += 1
            guard
                let children = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey],
                    options: includeHidden ? [] : [.skipsHiddenFiles]
                )
            else { continue }
            var batch: [IndexedItem] = []
            let parent = FuzzyQuery.fold(directory.path)
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
                let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
                let name = child.lastPathComponent
                let childComponents = components + [name]
                if isFolder, exclusions.excludes(childComponents, path: child.path) { continue }
                batch.append(
                    IndexedItem(
                        url: child.canonical, name: name, isFolder: isFolder,
                        foldedName: FuzzyQuery.fold(name), foldedParent: parent
                    ))
                if isFolder, !(values?.isSymbolicLink ?? false), depth + 1 < maxDepth {
                    queue.append((child, childComponents, depth + 1))
                }
            }
            count += batch.count
            publish(batch)
            if head > 4096 {
                queue.removeFirst(head)
                head = 0
            }
        }
    }

    private func publish(_ batch: [IndexedItem]) {
        guard !batch.isEmpty else { return }
        lock.withLock {
            pending.append(contentsOf: batch)
            while pending.count >= Self.chunkSize {
                chunks.append(Array(pending.prefix(Self.chunkSize)))
                pending.removeFirst(Self.chunkSize)
            }
        }
    }

    private func finish(truncated: Bool) {
        lock.withLock {
            isFinished = true
            isTruncated = truncated
        }
    }
}
