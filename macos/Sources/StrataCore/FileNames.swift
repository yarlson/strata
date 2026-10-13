// SPDX-License-Identifier: MIT

import Foundation

public enum FileNames {
    public static let newFolder = "new folder"
    public static let newFile = "new file"

    /// Rejects empty and whitespace-only names, `.` and `..`, and names
    /// containing `/` or NUL. Valid names are used exactly as typed.
    public static func isValid(_ name: String) -> Bool {
        guard name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            return false
        }
        return name.unicodeScalars.contains { !$0.properties.isWhitespace }
    }

    /// Splits a name into the stem and extension that numbering preserves.
    /// Folder names and dot-files have no extension.
    public static func stemAndExtension(_ name: String, isFolder: Bool) -> (String, String?) {
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, nil)
        }
        let ext = String(name[name.index(after: dot)...])
        return ext.isEmpty ? (name, nil) : (String(name[..<dot]), ext)
    }

    /// The first free name among `name`, then `stem (1).ext`, `stem (2).ext`, …
    /// A name that already ends in ` (n)` continues from `n + 1`.
    public static func available(
        _ name: String, isFolder: Bool, keepOriginal: Bool = true, isTaken: (String) -> Bool
    ) -> String {
        if keepOriginal, !isTaken(name) { return name }
        let (stem, ext) = stemAndExtension(name, isFolder: isFolder)
        let (base, number) = numberedStem(stem)
        var index = (number ?? 0) + 1
        while true {
            let candidate = "\(base) (\(index))" + (ext.map { ".\($0)" } ?? "")
            if !isTaken(candidate) { return candidate }
            index += 1
        }
    }

    /// The UTF-16 range a rename field selects: a file's stem, or a whole folder name.
    public static func editableRange(_ name: String, isFolder: Bool) -> NSRange {
        let (stem, _) = stemAndExtension(name, isFolder: isFolder)
        return NSRange(location: 0, length: stem.utf16.count)
    }

    static func numberedStem(_ stem: String) -> (String, Int?) {
        guard stem.hasSuffix(")"), let open = stem.range(of: " (", options: .backwards) else {
            return (stem, nil)
        }
        let digits = stem[open.upperBound..<stem.index(before: stem.endIndex)]
        guard let first = digits.first, first != "0", digits.allSatisfy(\.isASCIIDigit),
            let number = Int(digits)
        else { return (stem, nil) }
        return (String(stem[..<open.lowerBound]), number)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
