import Foundation

/// A global hotkey as Carbon wants it: a virtual key code and a modifier mask.
/// Carbon's constants are hard-coded rather than imported so this type stays in
/// `DnotesCore`, where it can be tested without AppKit.
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public static let command: UInt32 = 1 << 8   // cmdKey
    public static let shift: UInt32 = 1 << 9     // shiftKey
    public static let option: UInt32 = 1 << 11   // optionKey
    public static let control: UInt32 = 1 << 12  // controlKey

    public static let spaceKeyCode: UInt32 = 49  // kVK_Space

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let captureDefault = HotKeyCombo(keyCode: spaceKeyCode, modifiers: option)
    public static let mainWindowDefault = HotKeyCombo(keyCode: spaceKeyCode,
                                                      modifiers: option | shift)

    /// Modifier order follows the menu-bar convention: ⌃⌥⇧⌘.
    public var displayString: String {
        var out = ""
        if modifiers & Self.control != 0 { out += "⌃" }
        if modifiers & Self.option != 0 { out += "⌥" }
        if modifiers & Self.shift != 0 { out += "⇧" }
        if modifiers & Self.command != 0 { out += "⌘" }
        return out + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let named = namedKeys[keyCode] { return named }
        return letterKeys[keyCode] ?? "key \(keyCode)"
    }

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape",
    ]

    private static let letterKeys: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]
}
