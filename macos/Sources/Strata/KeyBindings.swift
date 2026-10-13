// SPDX-License-Identifier: MIT

import AppKit
import Carbon.HIToolbox

enum KeyName: Equatable {
    case character(Character)
    case up, down, left, right, home, end, pageUp, pageDown
    case enter, escape, space, backspace, forwardDelete, tab
    case function(Int)
}

/// One shortcut. Letters match the key's label, or the Latin letter at that
/// position on non-Latin layouts; digits match the top-row position.
struct KeyBinding {
    let key: KeyName
    let modifiers: NSEvent.ModifierFlags

    init(_ key: KeyName, _ modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(Self.relevantModifiers) == modifiers
            && Self.keyName(event) == key
    }

    /// The label macOS menus use, such as ⇧⌘N.
    var label: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    private var keyLabel: String {
        switch key {
        case let .character(character): String(character).uppercased()
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .enter: "↩"
        case .escape: "⎋"
        case .space: tr("keys.name.space")
        case .backspace: "⌫"
        case .forwardDelete: "⌦"
        case .tab: "⇥"
        case let .function(number): "F\(number)"
        }
    }

    /// The `NSMenuItem` key equivalent for this binding.
    var menuKeyEquivalent: String {
        func scalar(_ value: Int) -> String { String(Character(UnicodeScalar(value)!)) }
        switch key {
        case let .character(character): return String(character)
        case .up: return scalar(NSUpArrowFunctionKey)
        case .down: return scalar(NSDownArrowFunctionKey)
        case .left: return scalar(NSLeftArrowFunctionKey)
        case .right: return scalar(NSRightArrowFunctionKey)
        case .home: return scalar(NSHomeFunctionKey)
        case .end: return scalar(NSEndFunctionKey)
        case .pageUp: return scalar(NSPageUpFunctionKey)
        case .pageDown: return scalar(NSPageDownFunctionKey)
        case .enter: return "\r"
        case .escape: return "\u{1b}"
        case .space: return " "
        case .backspace: return "\u{8}"
        case .forwardDelete: return scalar(NSDeleteFunctionKey)
        case .tab: return "\t"
        case let .function(number): return scalar(NSF1FunctionKey + number - 1)
        }
    }

    static func keyName(_ event: NSEvent) -> KeyName? {
        let code = Int(event.keyCode)
        if let special = specialKeys[code] { return special }
        if let digit = topRowDigits[code] { return .character(digit) }
        if let plain = event.characters(byApplyingModifiers: [])?.lowercased(),
            plain.count == 1, let character = plain.first, character.isASCII,
            !character.isWhitespace, character.asciiValue.map({ $0 >= 0x20 }) == true
        {
            return .character(character)
        }
        return ansiCharacters[code].map(KeyName.character)
    }

    private static let specialKeys: [Int: KeyName] = [
        kVK_UpArrow: .up, kVK_DownArrow: .down, kVK_LeftArrow: .left, kVK_RightArrow: .right,
        kVK_Home: .home, kVK_End: .end, kVK_PageUp: .pageUp, kVK_PageDown: .pageDown,
        kVK_Return: .enter, kVK_ANSI_KeypadEnter: .enter, kVK_Escape: .escape, kVK_Space: .space,
        kVK_Delete: .backspace, kVK_ForwardDelete: .forwardDelete, kVK_Tab: .tab,
        kVK_F1: .function(1), kVK_F2: .function(2), kVK_F3: .function(3), kVK_F4: .function(4),
        kVK_F5: .function(5), kVK_F6: .function(6),
    ]

    private static let topRowDigits: [Int: Character] = [
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]

    private static let ansiCharacters: [Int: Character] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e",
        kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j",
        kVK_ANSI_K: "k", kVK_ANSI_L: "l", kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o",
        kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x", kVK_ANSI_Y: "y",
        kVK_ANSI_Z: "z", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
    ]
}

/// Every Strata shortcut.
enum Bindings {
    static let copy = KeyBinding(.character("c"), .command)
    static let cut = KeyBinding(.character("x"), .command)
    static let paste = KeyBinding(.character("v"), .command)
    static let selectAll = KeyBinding(.character("a"), .command)
    static let undo = KeyBinding(.character("z"), .command)
    static let redo = KeyBinding(.character("z"), [.command, .shift])

    static let newWindow = KeyBinding(.character("n"), .command)
    static let newTab = KeyBinding(.character("t"), .command)
    static let closeTab = KeyBinding(.character("w"), .command)
    static let newFolder = KeyBinding(.character("n"), [.command, .shift])
    static let newFolderWithSelection = KeyBinding(.character("n"), [.command, .control])
    static let newFile = KeyBinding(.character("n"), [.command, .option])
    static let rename = KeyBinding(.function(2))
    static let renameCommand = KeyBinding(.character("r"), .command)
    static let duplicate = KeyBinding(.character("d"), .command)
    static let properties = KeyBinding(.character("i"), .command)
    static let propertiesEnter = KeyBinding(.enter, .option)
    static let copyPath = KeyBinding(.character("c"), [.command, .option])
    static let copyPathPlain = KeyBinding(.character("y"))
    static let pin = KeyBinding(.character("t"), [.command, .control])
    static let pinPlain = KeyBinding(.character("p"))
    static let terminal = KeyBinding(.character("t"), [.command, .option])
    static let trash = KeyBinding(.backspace, .command)
    static let trashForwardDelete = KeyBinding(.forwardDelete)
    static let deletePermanently = KeyBinding(.backspace, [.command, .option])
    static let deletePermanentlyForwardDelete = KeyBinding(.forwardDelete, .shift)

    static let search = KeyBinding(.character("k"), .command)
    static let jumpToFolder = KeyBinding(.character("k"), [.command, .shift])
    static let location = KeyBinding(.character("l"), .command)
    static let filter = KeyBinding(.character("f"), .command)
    static let refresh = KeyBinding(.function(5))
    static let hiddenFiles = KeyBinding(.character("."), [.command, .shift])

    static let viewColumns = KeyBinding(.character("1"), .command)
    static let viewIcons = KeyBinding(.character("2"), .command)
    static let viewList = KeyBinding(.character("3"), .command)
    static let textLarger = KeyBinding(.character("="), .command)
    static let textSmaller = KeyBinding(.character("-"), .command)
    static let textReset = KeyBinding(.character("0"), .command)
    static let sidebar = KeyBinding(.character("b"), .command)
    static let sidebarFocus = KeyBinding(.character("b"), [.command, .shift])
    static let preview = KeyBinding(.character("p"), [.command, .shift])
    static let settings = KeyBinding(.character(","), .command)
    static let reference = KeyBinding(.function(1))

    static let back = KeyBinding(.character("["), .command)
    static let forward = KeyBinding(.character("]"), .command)
    static let enclosingFolder = KeyBinding(.up, .command)
    static let home = KeyBinding(.character("h"), [.command, .shift])
    static let open = KeyBinding(.down, .command)
    static let openInNewTab = KeyBinding(.enter, .command)
    static let openInNewWindow = KeyBinding(.enter, .shift)
    static let quickLook = KeyBinding(.character("y"), .command)

    static let historyBackAlt = KeyBinding(.left, .option)
    static let historyForwardAlt = KeyBinding(.right, .option)
    static let parentAlt = KeyBinding(.up, .option)
    static let homeAlt = KeyBinding(.home, .option)

    static let up = KeyBinding(.up)
    static let down = KeyBinding(.down)
    static let left = KeyBinding(.left)
    static let right = KeyBinding(.right)
    static let vimUp = KeyBinding(.character("k"))
    static let vimDown = KeyBinding(.character("j"))
    static let vimLeft = KeyBinding(.character("h"))
    static let vimRight = KeyBinding(.character("l"))
    static let firstItem = KeyBinding(.home)
    static let lastItem = KeyBinding(.end)
    static let pageUp = KeyBinding(.pageUp)
    static let pageDown = KeyBinding(.pageDown)
    static let extendUp = KeyBinding(.up, .shift)
    static let extendDown = KeyBinding(.down, .shift)
    static let enter = KeyBinding(.enter)
    static let escape = KeyBinding(.escape)
    static let space = KeyBinding(.space)
    static let backspace = KeyBinding(.backspace)
    static let focusNext = KeyBinding(.tab)
    static let focusPrevious = KeyBinding(.tab, .shift)
    static let filterSlash = KeyBinding(.character("/"))
}
