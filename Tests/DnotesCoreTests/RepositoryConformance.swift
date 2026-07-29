import Foundation
import Testing
@testable import DnotesCore

let day29 = CalendarDay(iso: "2026-07-29")!
let day30 = CalendarDay(iso: "2026-07-30")!
let day01 = CalendarDay(iso: "2026-08-01")!

/// Behaviour every backend owes its callers, whatever it stores notes in. Task 6
/// runs this against the in-memory repository and Task 9 runs it against the
/// markdown one; a backend added later runs it before it is wired to anything.
@MainActor
func assertRepositoryConformance(
    _ makeRepository: @MainActor () async throws -> any NotesRepository
) async throws {
    // Appending returns the entry it created and makes it visible.
    let repository = try await makeRepository()
    try await repository.load()
    let created = try await repository.append(text: "first #oss", on: day29)
    #expect(created.text == "first #oss")
    #expect(created.day == day29)
    #expect(created.isDone == false)
    #expect(created.tags == ["oss"])
    #expect(repository.entries.map(\.text) == ["first #oss"])

    // Ids are stable enough to act on right after creation.
    try await repository.setDone(true, for: created)
    #expect(repository.entries.map(\.isDone) == [true])

    // Editing replaces the text and re-derives the tags.
    let done = repository.entries[0]
    try await repository.edit(done, to: "second #infra")
    #expect(repository.entries.map(\.text) == ["second #infra"])
    #expect(repository.entries[0].tags == ["infra"])

    // Deleting removes exactly one entry.
    try await repository.delete(repository.entries[0])
    #expect(repository.entries.isEmpty)

    // Entries come back ascending by day, insertion order within a day.
    let ordered = try await makeRepository()
    try await ordered.load()
    try await ordered.append(text: "b", on: day30)
    try await ordered.append(text: "a1", on: day29)
    try await ordered.append(text: "a2", on: day29)
    try await ordered.append(text: "c", on: day01)
    #expect(ordered.entries.map(\.text) == ["a1", "a2", "b", "c"])

    // Acting on an entry that is already gone is refused, not guessed at.
    let stale = try await makeRepository()
    try await stale.load()
    let victim = try await stale.append(text: "doomed", on: day29)
    try await stale.delete(victim)
    await #expect(throws: NotesError.self) { try await stale.setDone(true, for: victim) }
}
