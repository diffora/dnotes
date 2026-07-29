import Foundation
import Observation

/// Selection and inline-edit state for the notes list.
///
/// Separate from the view because two things need it: the SwiftUI list that draws it,
/// and the AppKit key monitor that drives it. Being a plain observable type also makes
/// the fiddly parts — where the selection lands after a delete, what an arrow key does
/// when nothing is selected — testable without a window.
@MainActor
@Observable
public final class NotesListModel {
    public var selection: EntryID? {
        didSet {
            guard oldValue != selection else { return }
            // Moving to another note ends the edit instead of leaving a stray field
            // open on a row nobody is looking at. It *commits* rather than discards:
            // §8 does not allow typed text to vanish, and an unwanted save is
            // recoverable with undo while lost typing is not. `esc` still discards,
            // because that is what asking to cancel means.
            commitEditingIfNeeded()
        }
    }

    public private(set) var editing: EntryID?

    /// The text being edited. Held here rather than in the row's own state so that
    /// leaving the row can still commit it.
    public var editingText: String = ""

    private let notes: NotesModel

    public init(notes: NotesModel) {
        self.notes = notes
    }

    public var entries: [NoteEntry] { notes.visibleEntries }

    public var canUndo: Bool { notes.canUndo }

    public func undo() async {
        guard editing == nil else { return }
        await notes.undo()
    }

    public var selectedEntry: NoteEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    /// Clamped, not wrapped: running off the end of a list should stop, not teleport
    /// to the other end. With nothing selected, down starts at the top and up at the
    /// bottom. Returns whether the key was used, so the caller knows to swallow it.
    @discardableResult
    public func moveSelection(by delta: Int) -> Bool {
        let all = entries
        guard !all.isEmpty else {
            selection = nil
            return false
        }
        guard let current = all.firstIndex(where: { $0.id == selection }) else {
            selection = delta >= 0 ? all.first?.id : all.last?.id
            return true
        }
        selection = all[min(max(current + delta, 0), all.count - 1)].id
        return true
    }

    @discardableResult
    public func beginEditing() -> Bool {
        guard editing == nil, let entry = selectedEntry else { return false }
        editingText = entry.text
        editing = entry.id
        return true
    }

    /// Explicit cancel: the typed text is dropped, which is the whole point of `esc`.
    public func cancelEditing() {
        editing = nil
        editingText = ""
    }

    public func commitEdit(_ text: String) async {
        editingText = text
        await finishEditing()
    }

    /// Fire-and-forget commit for callers that cannot await — a selection change
    /// arriving from a click, for instance.
    private func commitEditingIfNeeded() {
        guard editing != nil else { return }
        Task { await finishEditing() }
    }

    private func finishEditing() async {
        guard let target = editing else { return }
        let text = editingText
        editing = nil
        editingText = ""

        // `notes.edit` ignores an unchanged or empty string, so a click-away that
        // changed nothing writes nothing.
        guard let entry = entries.first(where: { $0.id == target }) else { return }
        await notes.edit(entry, to: text)
    }

    @discardableResult
    public func toggleSelected() async -> Bool {
        guard editing == nil, let entry = selectedEntry else { return false }
        await notes.toggle(entry)
        return true
    }

    /// Deletes and leaves the selection on the neighbour that took its place, so a run
    /// of deletes does not need the mouse in between.
    @discardableResult
    public func deleteSelected() async -> Bool {
        guard editing == nil, let entry = selectedEntry else { return false }
        let index = entries.firstIndex { $0.id == entry.id } ?? 0
        await notes.delete(entry)

        let remaining = entries
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        return true
    }
}
