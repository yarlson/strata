// SPDX-License-Identifier: MIT

import Foundation

public enum SortKey: String, CaseIterable, Sendable {
    case name, size, kind, modified
}

public struct SortOrder: Hashable, Sendable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey = .name, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// Folders come first; ties fall back to the name so the order is stable.
    public func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted(by: areInIncreasingOrder)
    }

    public func areInIncreasingOrder(_ lhs: FileEntry, _ rhs: FileEntry) -> Bool {
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        let comparison = compare(lhs, rhs)
        if comparison != .orderedSame {
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        let names = lhs.name.localizedStandardCompare(rhs.name)
        if names != .orderedSame { return names == .orderedAscending }
        return lhs.name < rhs.name
    }

    private func compare(_ lhs: FileEntry, _ rhs: FileEntry) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .size:
            return order(lhs.size ?? -1, rhs.size ?? -1)
        case .kind:
            return (lhs.kindDescription ?? "").localizedStandardCompare(rhs.kindDescription ?? "")
        case .modified:
            return order(lhs.modified ?? .distantPast, rhs.modified ?? .distantPast)
        }
    }

    private func order<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }
}
