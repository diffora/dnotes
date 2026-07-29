import Foundation
import Testing
@testable import DnotesCore

/// Keeps each repository built by the conformance checks alive with its own folder.
@MainActor
final class TempFolderPool {
    private var folders: [TempFolder] = []
    func next() -> TempFolder {
        let folder = TempFolder()
        folders.append(folder)
        return folder
    }
}

@Test @MainActor func markdownRepositoryConforms() async throws {
    // The same checks the in-memory repository passes, against real files. This is
    // what makes the seam a seam rather than a wish.
    let folders = TempFolderPool()
    try await assertRepositoryConformance {
        MarkdownNotesRepository(folder: folders.next().url)
    }
}

@Test @MainActor func appendsIntoAnExistingDay() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    let created = try await repository.append(text: "two", on: day29)

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n- two\n")
    #expect(created.text == "two")
    #expect(repository.entries.map(\.text) == ["one", "two"])
}

@Test @MainActor func appendsIntoANewDayOfAnExistingMonth() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.append(text: "fresh", on: day30)

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n\n## 2026-07-30\n\n- fresh\n")
}

@Test @MainActor func appendsIntoANewMonthFile() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.append(text: "august", on: day01)

    #expect(folder.exists("2026-08.md"))
    #expect(folder.read("2026-08.md") == "## 2026-08-01\n\n- august\n")
    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n")
    #expect(repository.entries.map(\.text) == ["one", "august"])
}

@Test @MainActor func appendsIntoAnEmptyFolder() async throws {
    let folder = TempFolder()
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.append(text: "first ever", on: day29)

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- first ever\n")
}

@Test @MainActor func completesAnEntryAndLeavesNeighboursAlone() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n- two\n> quote\n- three\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.setDone(true, for: repository.entries[1])

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n- [x] two\n> quote\n- three\n")
    #expect(repository.entries.map(\.isDone) == [false, true, false])
}

@Test @MainActor func reopensAnEntry() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- [x] done\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.setDone(false, for: repository.entries[0])

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- done\n")
}

@Test @MainActor func editsAnEntrysText() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- old #oss\n- other\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.edit(repository.entries[0], to: "new #infra")

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- new #infra\n- other\n")
    #expect(repository.entries[0].tags == ["infra"])
}

@Test @MainActor func deletesExactlyOneLine() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n- two\n- three\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    try await repository.delete(repository.entries[1])

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n- three\n")
}

@Test @MainActor func refusesToWriteIntoAReadOnlyFolder() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    folder.setReadOnly(true)
    defer { folder.setReadOnly(false) }

    await #expect(throws: NotesError.self) { try await repository.append(text: "two", on: day29) }
    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n")
}

@Test @MainActor func refusesToWriteIntoAVanishedFolder() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let path = folder.url.path
    try FileManager.default.removeItem(at: folder.url)

    #expect(repository.isAvailable == false)
    await #expect(throws: NotesError.storeUnavailable(path)) {
        try await repository.append(text: "two", on: day29)
    }
}
