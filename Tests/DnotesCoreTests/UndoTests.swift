import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func makeModel(_ seeded: [(day: CalendarDay, text: String, isDone: Bool)] = [],
                       today: CalendarDay = day29)
    -> (NotesModel, InMemoryNotesRepository) {
    let repository = InMemoryNotesRepository(entries: seeded)
    let pending = PendingQueue(defaults: makeTestDefaults())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = today.startOfDay(in: calendar)!.addingTimeInterval(12 * 3600)
    return (NotesModel(repository: repository, pending: pending,
                       calendar: calendar, now: { now }), repository)
}

@Test @MainActor func nothingToUndoAtFirst() async {
    let (model, _) = makeModel([(day: day29, text: "a", isDone: false)])
    await model.load()

    #expect(!model.canUndo)
    await model.undo()   // must not crash or change anything
    #expect(model.entries.count == 1)
}

@Test @MainActor func undoBringsBackADeletedEntry() async {
    // The reason undo exists: plain ⌫ deletes with no confirmation.
    let (model, repository) = makeModel([(day: day29, text: "precious", isDone: false)])
    await model.load()

    await model.delete(model.entries[0])
    #expect(repository.entries.isEmpty)
    #expect(model.canUndo)

    await model.undo()

    #expect(repository.entries.map(\.text) == ["precious"])
    #expect(repository.entries.map(\.day) == [day29])
}

@Test @MainActor func undoRestoresToTheEntrysOwnDayNotToday() async {
    let (model, repository) = makeModel([(day: day29, text: "yesterday's", isDone: false)],
                                        today: day30)
    await model.load()

    await model.delete(model.entries[0])
    await model.undo()

    #expect(repository.entries.map(\.day) == [day29])
}

@Test @MainActor func undoReopensAnEntryThatWasCompleted() async {
    let (model, repository) = makeModel([(day: day29, text: "task", isDone: false)])
    await model.load()

    await model.toggle(model.entries[0])
    #expect(repository.entries.map(\.isDone) == [true])

    await model.undo()
    #expect(repository.entries.map(\.isDone) == [false])
}

@Test @MainActor func undoCompletesAnEntryThatWasReopened() async {
    let (model, repository) = makeModel([(day: day29, text: "task", isDone: true)])
    await model.load()

    await model.toggle(model.entries[0])
    #expect(repository.entries.map(\.isDone) == [false])

    await model.undo()
    #expect(repository.entries.map(\.isDone) == [true])
}

@Test @MainActor func undoPutsTheOldTextBack() async {
    let (model, repository) = makeModel([(day: day29, text: "before", isDone: false)])
    await model.load()

    await model.edit(model.entries[0], to: "after")
    #expect(repository.entries.map(\.text) == ["after"])

    await model.undo()
    #expect(repository.entries.map(\.text) == ["before"])
}

@Test @MainActor func undoRemovesACapture() async {
    let (model, repository) = makeModel()
    await model.load()

    await model.add("mistyped")
    #expect(repository.entries.count == 1)

    await model.undo()
    #expect(repository.entries.isEmpty)
}

@Test @MainActor func undoingIsNotItselfUndoable() async {
    // Otherwise ⌘Z would flip between two states forever instead of walking back.
    let (model, repository) = makeModel([(day: day29, text: "a", isDone: false)])
    await model.load()

    await model.delete(model.entries[0])
    await model.undo()

    #expect(!model.canUndo)
    #expect(repository.entries.map(\.text) == ["a"])
}

@Test @MainActor func undoWalksBackwardsThroughSeveralChanges() async {
    let (model, repository) = makeModel()
    await model.load()

    await model.add("one")
    await model.add("two")
    await model.add("three")

    await model.undo()
    #expect(repository.entries.map(\.text) == ["one", "two"])
    await model.undo()
    #expect(repository.entries.map(\.text) == ["one"])
    await model.undo()
    #expect(repository.entries.isEmpty)
    #expect(!model.canUndo)
}

@Test @MainActor func undoOfSomethingAlreadyGoneIsHarmless() async {
    let (model, repository) = makeModel([(day: day29, text: "a", isDone: false)])
    await model.load()

    await model.toggle(model.entries[0])          // recorded: set back to open
    try? await repository.delete(repository.entries[0])   // vanished behind our back
    await model.load()

    await model.undo()                            // finds nothing, does nothing
    #expect(repository.entries.isEmpty)
}

@Test @MainActor func aFailedChangeIsNotRecordedAsUndoable() async {
    let (model, repository) = makeModel([(day: day29, text: "a", isDone: false)])
    await model.load()
    repository.nextWriteError = .writeFailed("no space")

    await model.delete(model.entries[0])

    #expect(repository.entries.count == 1)
    #expect(!model.canUndo)   // nothing happened, so there is nothing to reverse
}

@Test @MainActor func theUndoStackIsBounded() async {
    let (model, _) = makeModel()
    await model.load()

    for index in 0..<60 { await model.add("entry \(index)") }

    var undone = 0
    while model.canUndo {
        await model.undo()
        undone += 1
        if undone > 100 { break }   // guard against a stack that never empties
    }
    #expect(undone == 50)   // NotesModel.undoLimit
}
