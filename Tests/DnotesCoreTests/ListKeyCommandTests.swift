import Testing
@testable import DnotesCore

private typealias Key = ListKeyCommand.KeyCode

/// The regression this file exists for: macOS sets `.function` and `.numericPad` on
/// every arrow key event. The first version of the key monitor asked AppKit's raw
/// flags whether the modifiers were empty, so arrow keys never matched and navigation
/// did nothing. `KeyModifiers` does not model those flags at all, which is what makes
/// the mistake unavailable — this test pins the behaviour that matters.
@Test func arrowsNavigateWithNoModifiersOfConsequence() {
    #expect(ListKeyCommand.from(keyCode: Key.upArrow, modifiers: []) == .moveUp)
    #expect(ListKeyCommand.from(keyCode: Key.downArrow, modifiers: []) == .moveDown)
}

@Test func arrowsStillNavigateWithCommandHeld() {
    #expect(ListKeyCommand.from(keyCode: Key.upArrow, modifiers: .command) == .moveUp)
    #expect(ListKeyCommand.from(keyCode: Key.downArrow, modifiers: .command) == .moveDown)
}

@Test(arguments: [KeyModifiers.option, .control, .shift])
func arrowsWithOtherModifiersAreLeftAlone(_ modifiers: KeyModifiers) {
    #expect(ListKeyCommand.from(keyCode: Key.upArrow, modifiers: modifiers) == nil)
    #expect(ListKeyCommand.from(keyCode: Key.downArrow, modifiers: modifiers) == nil)
}

@Test func spaceTogglesDone() {
    #expect(ListKeyCommand.from(keyCode: Key.space, modifiers: []) == .toggleDone)
    #expect(ListKeyCommand.from(keyCode: Key.space, modifiers: .command) == nil)
}

@Test func returnAndEBothBeginEditing() {
    #expect(ListKeyCommand.from(keyCode: Key.returnKey, modifiers: []) == .beginEdit)
    #expect(ListKeyCommand.from(keyCode: Key.keypadEnter, modifiers: []) == .beginEdit)
    #expect(ListKeyCommand.from(keyCode: Key.e, modifiers: []) == .beginEdit)
}

@Test func eWithAModifierIsNotAnEdit() {
    // ⌘E and ⌥E belong to whatever else wants them, not to the list.
    #expect(ListKeyCommand.from(keyCode: Key.e, modifiers: .command) == nil)
    #expect(ListKeyCommand.from(keyCode: Key.e, modifiers: .option) == nil)
}

@Test func backspaceDeletesWithOrWithoutCommand() {
    #expect(ListKeyCommand.from(keyCode: Key.delete, modifiers: []) == .delete)
    #expect(ListKeyCommand.from(keyCode: Key.delete, modifiers: .command) == .delete)
    #expect(ListKeyCommand.from(keyCode: Key.forwardDelete, modifiers: []) == .delete)
}

@Test func commandZUndoesButPlainZDoesNot() {
    #expect(ListKeyCommand.from(keyCode: Key.z, modifiers: .command) == .undo)
    // Plain z is a letter someone might be typing; ⇧⌘Z is redo, which does not exist.
    #expect(ListKeyCommand.from(keyCode: Key.z, modifiers: []) == nil)
    #expect(ListKeyCommand.from(keyCode: Key.z, modifiers: [.command, .shift]) == nil)
}

@Test func unknownKeysMeanNothing() {
    #expect(ListKeyCommand.from(keyCode: 0, modifiers: []) == nil)      // A
    #expect(ListKeyCommand.from(keyCode: 48, modifiers: []) == nil)     // Tab
}
