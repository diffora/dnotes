import Foundation

/// The modifiers that mean anything to a shortcut.
///
/// Deliberately does not model `function`, `numericPad` or `capsLock`. macOS sets the
/// first two on every arrow key event, so code that asks "are the modifiers empty?"
/// against raw AppKit flags silently rejects arrow keys — which is exactly the bug
/// this type exists to make impossible.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// What a key press means to the notes list. Mapping keys to intent is a pure
/// function so it can be tested without a window or an event.
public enum ListKeyCommand: Equatable, Sendable {
    case moveUp
    case moveDown
    case toggleDone
    case beginEdit
    case delete
    case undo

    /// Virtual key codes, named. Carbon's `kVK_*` constants live in HIToolbox, which
    /// the core has no other reason to import.
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let space: UInt16 = 49
        static let e: UInt16 = 14
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
        static let z: UInt16 = 6
    }

    public static func from(keyCode: UInt16, modifiers: KeyModifiers) -> ListKeyCommand? {
        switch keyCode {
        case KeyCode.upArrow where modifiers.isSubset(of: .command):
            return .moveUp
        case KeyCode.downArrow where modifiers.isSubset(of: .command):
            return .moveDown
        case KeyCode.space where modifiers.isEmpty:
            return .toggleDone
        case KeyCode.returnKey, KeyCode.keypadEnter where modifiers.isEmpty:
            return .beginEdit
        case KeyCode.e where modifiers.isEmpty:
            return .beginEdit
        // Plain ⌫ as well as ⌘⌫: the design asks for both, and they share a key code.
        case KeyCode.delete, KeyCode.forwardDelete where modifiers.isSubset(of: .command):
            return .delete
        // ⌘Z only in the list. While a text field has focus the monitor bows out, so
        // typing keeps AppKit's own undo.
        case KeyCode.z where modifiers == .command:
            return .undo
        default:
            return nil
        }
    }
}
