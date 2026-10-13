// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import StrataCore

struct ThemeCatalogTests {
    @Test func readsTheBundledCatalog() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/themes/catalog.toml")
        let themes = ThemeCatalog.parse(try String(contentsOf: catalog, encoding: .utf8))
        #expect(themes.count == 95)
        let azure = try #require(themes.first { $0.id == ThemeCatalog.defaultThemeID })
        #expect(azure.name == "Azure Glow")
        #expect(azure.background == RGBA(hex: "#03111e"))
        #expect(azure.isDark)
    }

    @Test func skipsIncompleteTablesAndIgnoresComments() {
        let toml = """
            # comment
            [[themes]]
            id = "light"  # trailing comment
            name = "Light"
            background = "#ffffff"
            surface = "#f0f0f0"
            text = "#111111"
            accent = "#0055ffcc"
            danger = "#cc0000"
            muted = "#dddddd"
            highlight = "#cccccc"
            border = "#bbbbbb"
            dim_text = "#666666"

            [[themes]]
            id = "broken"
            name = "Broken"
            background = "not a color"
            """
        let themes = ThemeCatalog.parse(toml)
        #expect(themes.map(\.id) == ["light"])
        #expect(themes.first?.isDark == false)
        #expect(themes.first?.accent.alpha == Double(0xcc) / 255)
        #expect(themes.first?.syntax.keyword == themes.first?.accent)
    }
}
