import AppKit
import Carbon.HIToolbox

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt
    /// What the recorder saw on the actual keyboard layout, e.g. "'" or "є".
    /// Optional so old stored shortcuts keep working.
    var label: String?

    init(keyCode: UInt32, modifiers: UInt, label: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    static let standard = KeyCombo(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt(NSEvent.ModifierFlags([.option, .command]).rawValue)
    )

    static let selection = KeyCombo(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt(NSEvent.ModifierFlags([.option, .command]).rawValue)
    )

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var isValid: Bool {
        !flags.intersection([.command, .option, .control]).isEmpty
    }

    var displayString: String { displayString(.en) }

    func displayString(_ language: AppLanguage) -> String {
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        parts += keyDisplay(language)
        return parts
    }

    private func keyDisplay(_ language: AppLanguage) -> String {
        if let label = Self.normalizedLabel(label) {
            return label
        }
        return Self.keyName(for: keyCode, language: language)
    }

    static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 3 else { return nil }
        for scalar in trimmed.unicodeScalars {
            let code = scalar.value
            if code < 0x20 || (0x7F...0x9F).contains(code) { return nil }
            if (0xF700...0xF8FF).contains(code) { return nil }
            if CharacterSet.nonBaseCharacters.contains(scalar) { return nil }
        }
        return trimmed.count == 1 ? trimmed.uppercased() : trimmed
    }

    static func keyName(for code: UInt32, language: AppLanguage) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Punctuation — the fallback that used to show "key 39".
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"

        // Navigation and editing keys.
        case kVK_Space: return L10n.t("Space", language)
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return L10n.t("Delete", language)
        case kVK_ForwardDelete: return L10n.t("Forward Delete", language)
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Help: return "Help"

        // Function keys.
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

        default: return L10n.format("key %d", language, Int(code))
        }
    }
}
