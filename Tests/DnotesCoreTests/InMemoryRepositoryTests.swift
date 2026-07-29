import Foundation
import Testing
@testable import DnotesCore

@Test @MainActor func inMemoryRepositoryConforms() async throws {
    try await assertRepositoryConformance { InMemoryNotesRepository() }
}

@Test @MainActor func inMemoryRepositorySeedsItsInitialEntries() async throws {
    let repository = InMemoryNotesRepository(entries: [
        (day: day29, text: "seeded #oss", isDone: false),
        (day: day30, text: "already done", isDone: true),
    ])
    try await repository.load()

    #expect(repository.entries.map(\.text) == ["seeded #oss", "already done"])
    #expect(repository.entries.map(\.isDone) == [false, true])
    #expect(repository.entries[0].tags == ["oss"])
}

@Test @MainActor func inMemoryRepositoryCanBeMadeUnavailable() async throws {
    let repository = InMemoryNotesRepository()
    repository.isAvailable = false

    await #expect(throws: NotesError.self) { try await repository.load() }
    await #expect(throws: NotesError.self) { try await repository.append(text: "x", on: day29) }
}

@Test @MainActor func inMemoryRepositoryCanInjectAWriteFailure() async throws {
    let repository = InMemoryNotesRepository()
    try await repository.load()
    repository.nextWriteError = .writeFailed("disk full")

    await #expect(throws: NotesError.writeFailed("disk full")) {
        try await repository.append(text: "x", on: day29)
    }
    #expect(repository.entries.isEmpty)

    // The injected failure applies once, so the retry path can be tested.
    try await repository.append(text: "x", on: day29)
    #expect(repository.entries.count == 1)
}
