import Foundation
import Testing
@testable import DnotesCore

@Test func findsOnlyMonthFiles() throws {
    let folder = TempFolder()
    folder.write("2026-06.md", "## 2026-06-01\n\n- june\n")
    folder.write("2026-07.md", "## 2026-07-29\n\n- july\n")
    folder.write("notes.md", "## 2026-05-01\n\n- legacy\n")
    folder.write("README.md", "# readme\n")
    folder.write("2026-07 2.md", "## 2026-07-29\n\n- icloud conflict copy\n")
    folder.write("2026-07 (conflicted copy).md", "## 2026-07-29\n\n- dropbox copy\n")
    folder.makeDirectory("archive")

    let files = try FileDiscovery.monthFiles(in: folder.url)

    #expect(files.map(\.month.description) == ["2026-06", "2026-07"])
}

@Test func returnsMonthsInAscendingOrder() throws {
    let folder = TempFolder()
    folder.write("2026-01.md", "")
    folder.write("2025-12.md", "")
    folder.write("2026-02.md", "")

    #expect(try FileDiscovery.monthFiles(in: folder.url).map(\.month.description)
            == ["2025-12", "2026-01", "2026-02"])
}

@Test @MainActor func loadsEntriesFromEveryMonthFile() async throws {
    let folder = TempFolder()
    folder.write("2026-06.md", "## 2026-06-30\n\n- june thing\n")
    folder.write("2026-07.md", "## 2026-07-29\n\n- july thing #oss\n- [x] done thing\n")

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    #expect(repository.entries.map(\.text) == ["june thing", "july thing #oss", "done thing"])
    #expect(repository.entries.map(\.isDone) == [false, false, true])
    #expect(repository.entries[1].tags == ["oss"])
    #expect(repository.entries[0].day == CalendarDay(iso: "2026-06-30")!)
}

@Test @MainActor func ignoresEntriesAboveTheFirstDayHeading() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "- orphan with no day\n\n## 2026-07-29\n\n- dated\n")

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    #expect(repository.entries.map(\.text) == ["dated"])
    #expect(folder.read("2026-07.md").contains("- orphan with no day"))
}

@Test @MainActor func numbersDuplicateLinesWithinTheirDay() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", """
    ## 2026-07-29

    - write the tests
    - something else
    - write the tests

    ## 2026-07-30

    - write the tests
    """)

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let duplicates = repository.entries.filter { $0.text == "write the tests" }

    // The ordinal is the backend's private business, so it is asserted here and
    // nowhere above the seam.
    #expect(duplicates.map { repository.location(of: $0.id)?.duplicateOrdinal } == [0, 1, 0])
    #expect(duplicates.map(\.day.description) == ["2026-07-29", "2026-07-29", "2026-07-30"])
}

@Test @MainActor func reportsAMissingFolder() async {
    let missing = URL(fileURLWithPath: "/nonexistent/dnotes")
    let repository = MarkdownNotesRepository(folder: missing)

    #expect(repository.isAvailable == false)
    await #expect(throws: NotesError.storeUnavailable(missing.path)) { try await repository.load() }
}

@Test @MainActor func anEmptyFolderLoadsToNothing() async throws {
    let folder = TempFolder()
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    #expect(repository.entries.isEmpty)
}

@Test @MainActor func setFolderSwitchesToADifferentSetOfNotes() async throws {
    let first = TempFolder()
    let second = TempFolder()
    first.write("2026-07.md", "## 2026-07-29\n\n- in the first folder\n")
    second.write("2026-07.md", "## 2026-07-29\n\n- in the second folder\n")

    let repository = MarkdownNotesRepository(folder: first.url)
    try await repository.load()
    try await repository.setFolder(second.url)

    #expect(repository.entries.map(\.text) == ["in the second folder"])
}
