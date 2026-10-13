// SPDX-License-Identifier: MIT

import Foundation

/// How a filename matched a pane filter. Literal matches rank ahead of typo matches.
public enum NameMatch: Int, Comparable, Sendable {
    case literal = 0
    case typo = 1

    public static func < (lhs: NameMatch, rhs: NameMatch) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A pane filter query: a case-insensitive substring, a `*` whole-name pattern,
/// or, for plain words of four or more letters or digits, one typo within a word.
public struct NameQuery: Sendable {
    private enum Pattern: Sendable {
        case substring(String, typoTolerant: Bool)
        case wildcard([String])
    }

    private let pattern: Pattern

    public init?(_ text: String) {
        guard !text.isEmpty else { return nil }
        let folded = Self.fold(text)
        if folded.contains("*") {
            pattern = .wildcard(folded.components(separatedBy: "*"))
        } else {
            let alphanumeric = folded.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            pattern = .substring(folded, typoTolerant: alphanumeric && folded.count >= 4)
        }
    }

    public func match(_ name: String) -> NameMatch? {
        let folded = Self.fold(name)
        switch pattern {
        case let .wildcard(parts):
            return Self.matchesWildcard(folded, parts) ? .literal : nil
        case let .substring(query, typoTolerant):
            if folded.contains(query) { return .literal }
            guard typoTolerant else { return nil }
            let words = folded.split { !$0.isLetter && !$0.isNumber }
            return words.contains { Self.isOneEditApart(Array(query), Array($0)) } ? .typo : nil
        }
    }

    static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func matchesWildcard(_ name: String, _ parts: [String]) -> Bool {
        guard let first = parts.first, let last = parts.last, parts.count > 1 else {
            return name == parts.first
        }
        guard name.hasPrefix(first) else { return false }
        var remainder = name.dropFirst(first.count)
        for middle in parts.dropFirst().dropLast() where !middle.isEmpty {
            guard let range = remainder.range(of: middle) else { return false }
            remainder = remainder[range.upperBound...]
        }
        return remainder.count >= last.count && remainder.hasSuffix(last)
    }

    /// Optimal string alignment distance of at most one: one inserted, missing,
    /// substituted, or adjacent swapped character.
    static func isOneEditApart(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        if lhs == rhs { return true }
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        switch longer.count - shorter.count {
        case 0:
            let differences = shorter.indices.filter { shorter[$0] != longer[$0] }
            if differences.count == 1 { return true }
            guard differences.count == 2, differences[1] == differences[0] + 1 else { return false }
            let index = differences[0]
            return shorter[index] == longer[index + 1] && shorter[index + 1] == longer[index]
        case 1:
            var index = 0
            while index < shorter.count, shorter[index] == longer[index] { index += 1 }
            return shorter[index...] == longer[(index + 1)...]
        default:
            return false
        }
    }
}
