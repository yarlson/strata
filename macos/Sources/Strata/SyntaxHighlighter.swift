// SPDX-License-Identifier: MIT

import AppKit

enum TokenKind: Sendable {
    case comment, string, number, keyword, type, preprocessor
}

struct Token: Sendable {
    let range: NSRange
    let kind: TokenKind
}

/// Lightweight lexical highlighting for common source languages.
enum SyntaxHighlighter {
    static let maximumLength = 400_000

    private struct Language {
        let lineComments: [String]
        let blockComment: (String, String)?
        let keywords: Set<String>
        let hashIsPreprocessor: Bool
    }

    private static let cFamilyKeywords: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
        "return", "function", "func", "fn", "let", "var", "const", "class", "struct", "enum",
        "interface", "protocol", "extension", "impl", "trait", "pub", "public", "private",
        "protected", "internal", "static", "final", "override", "import", "export", "from",
        "package", "use", "mod", "crate", "self", "Self", "super", "this", "new", "delete",
        "try", "catch", "throw", "throws", "finally", "async", "await", "yield", "true", "false",
        "null", "nil", "None", "undefined", "void", "in", "of", "as", "is", "where", "match",
        "mut", "ref", "type", "typedef", "namespace", "using", "template", "typename", "guard",
        "defer", "go", "chan", "select", "map", "range", "unsafe", "extern", "where", "loop",
        "instanceof", "typeof", "lambda", "def", "elif", "pass", "with", "not", "and", "or",
        "global", "nonlocal", "raise", "except", "then", "fi", "esac", "local", "echo", "end",
    ]

    private static let languages: [String: Language] = {
        let cLike = Language(
            lineComments: ["//"], blockComment: ("/*", "*/"), keywords: cFamilyKeywords, hashIsPreprocessor: false)
        let cPre = Language(
            lineComments: ["//"], blockComment: ("/*", "*/"), keywords: cFamilyKeywords, hashIsPreprocessor: true)
        let hash = Language(
            lineComments: ["#"], blockComment: nil, keywords: cFamilyKeywords, hashIsPreprocessor: false)
        let dash = Language(
            lineComments: ["--"], blockComment: ("/*", "*/"),
            keywords: [
                "select", "from", "where", "insert", "update", "delete", "create", "table", "into",
                "values", "join", "left", "right", "inner", "on", "group", "by", "order", "limit",
                "and", "or", "not", "null", "as", "local", "function", "end", "then", "if", "else",
                "return", "for", "in", "do", "while", "true", "false", "nil",
            ], hashIsPreprocessor: false)
        var map: [String: Language] = [:]
        for ext in [
            "swift", "rs", "js", "mjs", "cjs", "ts", "tsx", "jsx", "java", "kt", "kts", "go", "scala", "dart", "cs",
            "php", "zig", "css", "scss", "less", "json", "jsonc",
        ] {
            map[ext] = cLike
        }
        for ext in ["c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm"] { map[ext] = cPre }
        for ext in [
            "py", "rb", "sh", "bash", "zsh", "fish", "toml", "yaml", "yml", "conf", "ini", "r", "pl", "ps1", "mk",
            "cmake", "dockerfile", "gitignore", "env",
        ] {
            map[ext] = hash
        }
        for ext in ["sql", "lua", "hs"] { map[ext] = dash }
        return map
    }()

    static func tokens(_ text: String, fileName: String) -> [Token] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let key = ext.isEmpty ? fileName.lowercased() : ext
        guard let language = languages[key] ?? (fileName == "Makefile" ? languages["mk"] : nil) else { return [] }
        let source = text as NSString
        guard source.length <= maximumLength else { return [] }
        var tokens: [Token] = []
        var index = 0
        let length = source.length
        func starts(_ marker: String, at position: Int) -> Bool {
            let markerLength = (marker as NSString).length
            return position + markerLength <= length
                && source.substring(with: NSRange(location: position, length: markerLength)) == marker
        }
        while index < length {
            let character = source.character(at: index)
            if language.lineComments.contains(where: { starts($0, at: index) }) {
                let end = source.range(of: "\n", options: [], range: NSRange(location: index, length: length - index))
                let stop = end.location == NSNotFound ? length : end.location
                let kind: TokenKind = language.hashIsPreprocessor ? .preprocessor : .comment
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: kind))
                index = stop
            } else if language.hashIsPreprocessor, character == 0x23, isLineStart(source, index) {
                let end = source.range(of: "\n", options: [], range: NSRange(location: index, length: length - index))
                let stop = end.location == NSNotFound ? length : end.location
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .preprocessor))
                index = stop
            } else if let block = language.blockComment, starts(block.0, at: index) {
                let searchStart = index + (block.0 as NSString).length
                let end = source.range(
                    of: block.1, options: [], range: NSRange(location: searchStart, length: length - searchStart))
                let stop = end.location == NSNotFound ? length : end.location + end.length
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .comment))
                index = stop
            } else if character == 0x22 || character == 0x27 || character == 0x60 {
                var position = index + 1
                while position < length {
                    let next = source.character(at: position)
                    if next == 0x5C { position += 2; continue }
                    if next == character || (next == 0x0A && character != 0x60) { break }
                    position += 1
                }
                let stop = min(position + 1, length)
                tokens.append(Token(range: NSRange(location: index, length: stop - index), kind: .string))
                index = stop
            } else if isDigit(character), index == 0 || !isWord(source.character(at: index - 1)) {
                var position = index
                while position < length,
                    isWord(source.character(at: position)) || source.character(at: position) == 0x2E
                {
                    position += 1
                }
                tokens.append(Token(range: NSRange(location: index, length: position - index), kind: .number))
                index = position
            } else if isWordStart(character) {
                var position = index
                while position < length, isWord(source.character(at: position)) { position += 1 }
                let range = NSRange(location: index, length: position - index)
                let word = source.substring(with: range)
                if language.keywords.contains(word) {
                    tokens.append(Token(range: range, kind: .keyword))
                } else if let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first),
                    word.count > 1
                {
                    tokens.append(Token(range: range, kind: .type))
                }
                index = position
            } else {
                index += 1
            }
        }
        return tokens
    }

    @MainActor
    static func color(_ kind: TokenKind, _ palette: Palette) -> NSColor {
        switch kind {
        case .comment: palette.dimText
        case .string: palette.string
        case .number: palette.constant
        case .keyword: palette.keyword
        case .type: palette.type
        case .preprocessor: palette.preprocessor
        }
    }

    private static func isLineStart(_ source: NSString, _ index: Int) -> Bool {
        var position = index - 1
        while position >= 0 {
            let character = source.character(at: position)
            if character == 0x0A { return true }
            if character != 0x20 && character != 0x09 { return false }
            position -= 1
        }
        return true
    }

    private static func isDigit(_ character: unichar) -> Bool { character >= 0x30 && character <= 0x39 }
    private static func isWordStart(_ character: unichar) -> Bool {
        (character >= 0x41 && character <= 0x5A) || (character >= 0x61 && character <= 0x7A) || character == 0x5F
    }
    private static func isWord(_ character: unichar) -> Bool { isWordStart(character) || isDigit(character) }
}
