import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func makeList(_ texts: [String], today: CalendarDay = day29)
    -> (NotesListModel, NotesModel, InMemoryNotesRepository) {
    let repository = InMemoryNotesRepository(
        entries: texts.map { (day: today, text: $0, isDone: false) }
    )
    let pending = PendingQueue(defaults: makeTestDefaults())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = today.startOfDay(in: calendar)!.addingTimeInterval(12 * 3600)
    let notes = NotesModel(repository: repository, pending: pending,
                           calendar: calendar, now: { now })
    return (NotesListModel(notes: notes), notes, repository)
}

@Test @MainActor func downArrowStartsAtTheTopWhenNothingIsSelected() async {
    let (list, notes, _) = makeList(["a", "b", "c"])
    await notes.load()

    #expect(list.moveSelection(by: 1))
    #expect(list.selectedEntry?.text == "a")
}

@Test @MainActor func upArrowStartsAtTheBottomWhenNothingIsSelected() async {
    let (list, notes, _) = makeList(["a", "b", "c"])
    await notes.load()

    #expect(list.moveSelection(by: -1))
    #expect(list.selectedEntry?.text == "c")
}

@Test @MainActor func selectionClampsRatherThanWraps() async {
    let (list, notes, _) = makeList(["a", "b", "c"])
    await notes.load()
    list.moveSelection(by: 1)   // a

    list.moveSelection(by: -1)
    #expect(list.selectedEntry?.text == "a")   // stayed, did not jump to c

    list.moveSelection(by: 99)
    #expect(list.selectedEntry?.text == "c")
    list.moveSelection(by: 1)
    #expect(list.selectedEntry?.text == "c")
}

@Test @MainActor func movingInAnEmptyListDoesNothing() async {
    let (list, notes, _) = makeList([])
    await notes.load()

    #expect(!list.moveSelection(by: 1))
    #expect(list.selection == nil)
}

@Test @MainActor func editingNeedsASelection() async {
    let (list, notes, _) = makeList(["a"])
    await notes.load()

    #expect(!list.beginEditing())
    list.moveSelection(by: 1)
    #expect(list.beginEditing())
    #expect(list.editing == list.selection)
}

@Test @MainActor func committingAnEditWritesThroughAndLeavesEditMode() async {
    let (list, notes, repository) = makeList(["old"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()

    await list.commitEdit("new")

    #expect(list.editing == nil)
    #expect(repository.entries.map(\.text) == ["new"])
}

@Test @MainActor func cancellingAnEditChangesNothing() async {
    let (list, notes, repository) = makeList(["old"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()

    list.cancelEditing()

    #expect(list.editing == nil)
    #expect(repository.entries.map(\.text) == ["old"])
}

/// `commitEditingIfNeeded` cannot await — it runs from a `didSet` on selection — so
/// tests have to let the spawned task finish.
@MainActor
private func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@Test @MainActor func movingToAnotherNoteCommitsTheEdit() async {
    // §8: typed text is never dropped silently. Undo makes an unwanted save
    // recoverable; lost typing would not be.
    let (list, notes, repository) = makeList(["a", "b"])
    await notes.load()
    list.moveSelection(by: 1)          // a
    list.beginEditing()
    list.editingText = "a, rewritten"

    list.selection = list.entries[1].id   // click on b

    await settle()
    #expect(list.editing == nil)
    #expect(repository.entries.map(\.text) == ["a, rewritten", "b"])
}

@Test @MainActor func movingAwayWithoutChangingAnythingWritesNothing() async {
    let (list, notes, repository) = makeList(["a", "b"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()                // editingText == "a", untouched

    list.selection = list.entries[1].id

    await settle()
    #expect(repository.entries.map(\.text) == ["a", "b"])
}

@Test @MainActor func escapeStillDiscardsTheEdit() async {
    let (list, notes, repository) = makeList(["a"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()
    list.editingText = "typed but abandoned"

    list.cancelEditing()

    await settle()
    #expect(list.editing == nil)
    #expect(repository.entries.map(\.text) == ["a"])
}

@Test @MainActor func reselectingTheSameRowDoesNotEndTheEdit() async {
    let (list, notes, _) = makeList(["a"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()

    list.selection = list.selection   // a click on the row already being edited

    await settle()
    #expect(list.editing != nil)
}

@Test @MainActor func beginEditingStartsFromTheEntrysCurrentText() async {
    let (list, notes, _) = makeList(["as written"])
    await notes.load()
    list.moveSelection(by: 1)

    list.beginEditing()

    #expect(list.editingText == "as written")
}

@Test @MainActor func togglingActsOnTheSelection() async {
    let (list, notes, repository) = makeList(["a", "b"])
    await notes.load()
    list.moveSelection(by: 1)   // a

    #expect(await list.toggleSelected())
    #expect(repository.entries.map(\.isDone) == [true, false])
}

@Test @MainActor func deletingMovesTheSelectionToTheNeighbour() async {
    let (list, notes, repository) = makeList(["a", "b", "c"])
    await notes.load()
    list.moveSelection(by: 1)   // a
    list.moveSelection(by: 1)   // b

    #expect(await list.deleteSelected())

    #expect(repository.entries.map(\.text) == ["a", "c"])
    // The row that took b's place, so a run of deletes needs no mouse in between.
    #expect(list.selectedEntry?.text == "c")
}

@Test @MainActor func deletingTheLastRowSelectsTheOneBefore() async {
    let (list, notes, _) = makeList(["a", "b"])
    await notes.load()
    list.moveSelection(by: -1)   // b, the last

    await list.deleteSelected()

    #expect(list.selectedEntry?.text == "a")
}

@Test @MainActor func deletingTheOnlyRowClearsTheSelection() async {
    let (list, notes, _) = makeList(["only"])
    await notes.load()
    list.moveSelection(by: 1)

    await list.deleteSelected()

    #expect(list.selection == nil)
    #expect(list.selectedEntry == nil)
}

@Test @MainActor func nothingActsWhileEditing() async {
    // The key monitor also refuses to act while editing, but the model must not
    // depend on that: a stray command during an edit would be data loss.
    let (list, notes, repository) = makeList(["a"])
    await notes.load()
    list.moveSelection(by: 1)
    list.beginEditing()

    #expect(!(await list.toggleSelected()))
    #expect(!(await list.deleteSelected()))
    #expect(repository.entries.map(\.text) == ["a"])
    #expect(repository.entries.map(\.isDone) == [false])
}

@Test @MainActor func aSelectionThatDisappearedResolvesToNothing() async {
    let (list, notes, repository) = makeList(["a"])
    await notes.load()
    list.moveSelection(by: 1)

    try? await repository.delete(repository.entries[0])
    await notes.load()

    #expect(list.selectedEntry == nil)
    #expect(!(await list.deleteSelected()))
}
