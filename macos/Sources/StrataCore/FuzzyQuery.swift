// SPDX-License-Identifier: MIT

import Foundation

/// Global search scoring. Every space-separated term must match the path as a
/// subsequence; matches inside the filename, at word starts, and in runs score higher.
public struct FuzzyQuery: Sendable {
    private let terms: [[Character]]

    public init?(_ text: String) {
        let terms = NameQuery.fold(text).split(whereSeparator: \.isWhitespace).map(Array.init)
        guard !terms.isEmpty else { return nil }
        self.terms = terms
    }

    /// Returns a score, higher is better, or nil when a term does not match.
    /// `path` is the folded parent path and `name` the folded filename.
    public func score(name: [Character], path: [Character]) -> Int? {
        var total = 0
        for term in terms {
            if let score = Self.score(term, in: name, isName: true) {
                total += score + 64
            } else if let score = Self.score(term, in: path + ["/"] + name, isName: false) {
                total += score
            } else {
                return nil
            }
        }
        return total - name.count / 4
    }

    public static func fold(_ text: String) -> [Character] { Array(NameQuery.fold(text)) }

    private static func score(_ term: [Character], in text: [Character], isName: Bool) -> Int? {
        guard term.count <= text.count else { return nil }
        if let start = firstRange(of: term, in: text) {
            let boundary = start == 0 || isBoundary(text[start - 1]) ? 24 : 0
            let prefix = isName && start == 0 ? 32 : 0
            return term.count * 24 + boundary + prefix
        }
        var score = 0
        var textIndex = 0
        var previous = -2
        for character in term {
            while textIndex < text.count, text[textIndex] != character { textIndex += 1 }
            guard textIndex < text.count else { return nil }
            score += 8
            if textIndex == previous + 1 { score += 12 }
            if textIndex == 0 || isBoundary(text[textIndex - 1]) { score += 10 }
            if previous >= 0 { score -= min(textIndex - previous - 1, 6) }
            previous = textIndex
            textIndex += 1
        }
        return score
    }

    private static func firstRange(of term: [Character], in text: [Character]) -> Int? {
        guard let first = term.first else { return nil }
        var index = 0
        while index + term.count <= text.count {
            if text[index] == first, text[index..<(index + term.count)].elementsEqual(term) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func isBoundary(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }
}
