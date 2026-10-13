// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

struct FuzzyQueryTests {
    private func score(_ query: String, _ path: String) -> Int? {
        let url = URL(fileURLWithPath: path)
        return FuzzyQuery(query)?.score(
            name: FuzzyQuery.fold(url.lastPathComponent),
            path: FuzzyQuery.fold(url.deletingLastPathComponent().path)
        )
    }

    @Test func rejectsTermsThatAreNotSubsequences() {
        #expect(score("xyz", "/home/notes.txt") == nil)
        #expect(score("notes zzz", "/home/notes.txt") == nil)
    }

    @Test func ranksNameMatchesAheadOfPathOnlyMatches() throws {
        let inName = try #require(score("report", "/work/report.pdf"))
        let inPath = try #require(score("report", "/report/summary.pdf"))
        #expect(inName > inPath)
    }

    @Test func ranksContiguousMatchesAheadOfScatteredOnes() throws {
        let contiguous = try #require(score("strata", "/x/strata.svg"))
        let scattered = try #require(score("strata", "/x/s-t-r-a-t-a.svg"))
        #expect(contiguous > scattered)
    }

    @Test func requiresEveryTerm() {
        #expect(score("work pdf", "/work/report.pdf") != nil)
    }
}

struct SearchExclusionsTests {
    private let home = URL(fileURLWithPath: "/Users/me")

    @Test(arguments: [
        ("build", true), ("/Volumes/Data/archive", true), ("~/Projects/old", true),
        ("/", false), ("~", false), ("~/", false), ("relative/path", false),
        ("/a/../b", false), ("..", false), ("", false),
    ])
    func validatesRules(rule: String, isValid: Bool) {
        #expect(SearchExclusions.isValid(rule) == isValid)
    }

    @Test func excludesNamesAnywherePathsAsSubtreesAndGeneratedTrees() {
        let exclusions = SearchExclusions(rules: ["Build", "~/Projects/old"], home: home)
        #expect(exclusions.excludes(["/", "Users", "me", "app", "build"], path: "/Users/me/app/build"))
        #expect(exclusions.excludes(["/", "Users", "me", "Projects", "old", "x"], path: "/Users/me/Projects/old/x"))
        #expect(!exclusions.excludes(["/", "Users", "me", "Projects", "older"], path: "/Users/me/Projects/older"))
        #expect(exclusions.excludes(["/", "Users", "me", "web", "node_modules"], path: "/Users/me/web/node_modules"))
        #expect(exclusions.excludes(["/", "Users", "me", "Library", "Caches"], path: "/Users/me/Library/Caches"))
        #expect(!exclusions.excludes(["/", "Users", "me", ".cargo"], path: "/Users/me/.cargo"))
    }
}

struct SearchIndexTests {
    @Test func indexesVisibleItemsAndSkipsExcludedTrees() throws {
        let root = try temporaryTree([
            "docs/report.pdf", "docs/.secret.txt", "web/node_modules/pkg/index.js", "web/app.js",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = SearchIndex(
            roots: [root], exclusions: SearchExclusions(rules: [], home: root), includeHidden: false
        )
        index.start()
        let snapshot = try waitUntilFinished(index)

        let names = Set(snapshot.items.joined().map(\.name))
        #expect(names == ["docs", "report.pdf", "web", "app.js"])
        let results = SearchIndex.search(try #require(FuzzyQuery("report")), in: snapshot)
        #expect(results.first?.name == "report.pdf")
        let folders = SearchIndex.search(try #require(FuzzyQuery("docs")), in: snapshot, foldersOnly: true)
        #expect(folders.first?.name == "docs")
        #expect(folders.allSatisfy { $0.isFolder })
        #expect(!snapshot.isTruncated)
    }

    @Test func reportsTruncationWhenTheEntryBudgetRunsOut() throws {
        let root = try temporaryTree(["a/1", "b/2", "c/3"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = SearchIndex(
            roots: [root], exclusions: SearchExclusions(rules: [], home: root),
            includeHidden: false, maxEntries: 2
        )
        index.start()
        #expect(try waitUntilFinished(index).isTruncated)
    }

    private func waitUntilFinished(_ index: SearchIndex) throws -> SearchIndex.Snapshot {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let snapshot = index.snapshot()
            if snapshot.isFinished { return snapshot }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw CancellationError()
    }
}

func temporaryTree(_ files: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("strata-tests-\(UUID().uuidString)")
    for file in files {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }
    return root.resolvingSymlinksInPath()
}
