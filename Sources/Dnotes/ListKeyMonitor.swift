import AppKit
import DnotesCore

extension KeyModifiers {
    /// Translates AppKit's flags, dropping the ones that are noise for a shortcut:
    /// macOS sets `.function` and `.numericPad` on every arrow key, and `.capsLock`
    /// says nothing about intent. Asking raw AppKit flags whether the modifiers are
    /// empty is what broke arrow navigation once already.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

/// Keyboard control for the notes list, taken at the AppKit level.
///
/// SwiftUI's `onKeyPress` on a focusable scroll view competes with the scroll view's
/// own arrow handling and depends on which view happens to hold focus — for keys this
/// central that is not good enough. A local event monitor sees the key first and
/// decides, which is the same approach the capture panel uses for `⌘,` and `⌘L`.
///
/// It deliberately keeps out of the way of text: whenever a field editor is the first
/// responder, or a row is being edited, every key is passed straight through. That is
/// what lets `e` and `⌫` be plain keys in the list without stealing them from the
/// search box or the inline editor.
@MainActor
final class ListKeyMonitor {
    private let list: NotesListModel
    private weak var window: NSWindow?
    private var monitor: Any?

    init(window: NSWindow, list: NotesListModel) {
        self.window = window
        self.list = list

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }

    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the key was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }

        // NSTextView covers both the search field and the inline row editor, since
        // SwiftUI text fields are backed by the window's field editor.
        if window.firstResponder is NSText { return false }
        if list.editing != nil { return false }

        guard let command = ListKeyCommand.from(keyCode: event.keyCode,
                                                modifiers: KeyModifiers(event.modifierFlags))
        else { return false }

        switch command {
        case .moveUp:
            return list.moveSelection(by: -1)
        case .moveDown:
            return list.moveSelection(by: 1)
        case .toggleDone:
            guard list.selectedEntry != nil else { return false }
            Task { await list.toggleSelected() }
            return true
        case .beginEdit:
            return list.beginEditing()
        case .delete:
            guard list.selectedEntry != nil else { return false }
            Task { await list.deleteSelected() }
            return true
        case .undo:
            guard list.canUndo else { return false }
            Task { await list.undo() }
            return true
        }
    }
}
