// SPDX-License-Identifier: MIT

import Testing

@testable import StrataCore

struct NameQueryTests {
    @Test(arguments: [
        ("REPORT", "annual-report.pdf", NameMatch.literal),
        ("trahs", "strata-trash.svg", NameMatch.typo),
        ("srtata", "strata-trash.svg", NameMatch.typo),
        ("trasch", "strata-trash.svg", NameMatch.typo),
    ])
    func matchesSubstringsAndOneTypoWithinAWord(query: String, name: String, expected: NameMatch) {
        #expect(NameQuery(query)?.match(name) == expected)
    }

    @Test(arguments: [
        ("trash", "strata-search.svg"),
        ("trs", "strata-trash.svg"),
        ("tr-hs", "strata-trash.svg"),
        ("trahss", "strata-trash.svg"),
    ])
    func keepsShortPunctuatedAndDistantQueriesLiteral(query: String, name: String) {
        #expect(NameQuery(query)?.match(name) == nil)
    }

    @Test(arguments: [
        ("*.MOV", "clip.mov", true),
        ("*.MOV", "clip.MOV.bak", false),
        ("IMG*", "IMG_0001.HEIC", true),
        ("IMG*", "my IMG.png", false),
        ("IMG*.MOV", "IMG_0002.MOV", true),
        ("IMG*.MOV", "IMG_0002.MP4", false),
        ("*holiday*", "2024 Holiday trip", true),
        ("*", "anything", true),
        ("a*a", "a", false),
        ("?.txt*", "?.txt", true),
    ])
    func matchesWholeNameWildcardPatterns(pattern: String, name: String, matches: Bool) {
        #expect((NameQuery(pattern)?.match(name) != nil) == matches)
    }

    @Test func emptyQueryMatchesNothing() {
        #expect(NameQuery("") == nil)
    }
}
