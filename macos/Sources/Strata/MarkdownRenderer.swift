// SPDX-License-Identifier: MIT

import AppKit

/// Turns Markdown into rich text: headings, emphasis, code, lists,
/// quotes, and links, with a break between blocks.
@MainActor
enum MarkdownRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        let appearance = Appearance.shared
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(
                string: markdown,
                attributes: [
                    .font: appearance.font(), .foregroundColor: NSColor.labelColor,
                ])
        }
        let output = NSMutableAttributedString()
        var previousBlock: Int?
        var previousWasListItem = false
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            let isListItem = components.contains { if case .listItem = $0.kind { true } else { false } }
            let isBlockStart = block != previousBlock
            if isBlockStart, previousBlock != nil {
                output.append(NSAttributedString(string: isListItem && previousWasListItem ? "\n" : "\n\n"))
            }
            previousBlock = block
            previousWasListItem = isListItem

            var attributes = blockAttributes(components, appearance)
            applyInline(run, to: &attributes, appearance)
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }
            if isBlockStart, let marker = marker(components) {
                output.append(NSAttributedString(string: marker, attributes: attributes))
            }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }

    private static func blockAttributes(
        _ components: [PresentationIntent.IntentType], _ appearance: Appearance
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: appearance.font(), .foregroundColor: NSColor.labelColor,
        ]
        for component in components {
            switch component.kind {
            case let .header(level):
                let scales: [CGFloat] = [1.6, 1.35, 1.2, 1.1, 1.0, 1.0]
                attributes[.font] = appearance.font(scale: scales[min(max(level, 1), 6) - 1], weight: .bold)
                attributes[.foregroundColor] = NSColor.labelColor
            case .codeBlock:
                attributes[.font] = appearance.codeFont(scale: 0.92)
                attributes[.backgroundColor] = NSColor.quaternarySystemFill
            case .blockQuote:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            default:
                break
            }
        }
        return attributes
    }

    private static func applyInline(
        _ run: AttributedString.Runs.Run, to attributes: inout [NSAttributedString.Key: Any],
        _ appearance: Appearance
    ) {
        guard let inline = run.inlinePresentationIntent else { return }
        let base = attributes[.font] as? NSFont ?? appearance.font()
        if inline.contains(.code) {
            attributes[.font] = appearance.codeFont(scale: 0.92)
            attributes[.backgroundColor] = NSColor.quaternarySystemFill
            return
        }
        var font = base
        if inline.contains(.stronglyEmphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if inline.contains(.emphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        attributes[.font] = font
        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
    }

    private static func marker(_ components: [PresentationIntent.IntentType]) -> String? {
        for (index, component) in components.enumerated() {
            switch component.kind {
            case let .listItem(ordinal):
                let ordered = components.dropFirst(index).contains {
                    if case .orderedList = $0.kind { true } else { false }
                }
                let depth = components.filter { if case .listItem = $0.kind { true } else { false } }.count
                let indent = String(repeating: "    ", count: max(depth - 1, 0))
                return indent + (ordered ? "\(ordinal). " : "• ")
            case .blockQuote:
                return "▎ "
            case .thematicBreak:
                return "———"
            default:
                continue
            }
        }
        return nil
    }
}
