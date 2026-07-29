import Foundation
import Testing
@testable import DnotesCore

/// Rewrites a file behind the repository's back, with an mtime that is definitely
/// different from the one it read.
private func changeBehindOurBack(_ folder: TempFolder, _ name: String, to contents: String) {
    folder.write(name, contents, modified: Date().addingTimeInterval(60))
}

@Test @MainActor func appliesTheEditToTheCurrentContentAfterAnExternalChange() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n- two\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let two = repository.entries[1]

    // Someone inserted a line above ours in another editor: our line moved down.
    changeBehindOurBack(folder, "2026-07.md", to: "## 2026-07-29\n\n- inserted\n- one\n- two\n")

    try await repository.setDone(true, for: two)

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- inserted\n- one\n- [x] two\n")
}

@Test @MainActor func editsTheNthDuplicateAfterAnExternalChange() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- write the tests\n- other\n- write the tests\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let second = repository.entries.filter { $0.text == "write the tests" }[1]
    #expect(repository.location(of: second.id)?.duplicateOrdinal == 1)

    changeBehindOurBack(
        folder, "2026-07.md",
        to: "## 2026-07-29\n\n- new first\n- write the tests\n- other\n- write the tests\n"
    )

    try await repository.setDone(true, for: second)

    #expect(folder.read("2026-07.md")
            == "## 2026-07-29\n\n- new first\n- write the tests\n- other\n- [x] write the tests\n")
}

@Test @MainActor func cancelsWhenTheIdenticalLinesBecameFewer() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- write the tests\n- write the tests\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let second = repository.entries[1]

    // One of the two copies was removed elsewhere: the second occurrence is gone.
    let changed = "## 2026-07-29\n\n- write the tests\n"
    changeBehindOurBack(folder, "2026-07.md", to: changed)

    await #expect(throws: NotesError.ambiguousMatch) {
        try await repository.setDone(true, for: second)
    }
    #expect(folder.read("2026-07.md") == changed)
}

@Test @MainActor func cancelsWhenTheLineIsGone() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let one = repository.entries[0]

    let changed = "## 2026-07-29\n\n- something else entirely\n"
    changeBehindOurBack(folder, "2026-07.md", to: changed)

    await #expect(throws: NotesError.entryVanished) { try await repository.delete(one) }
    #expect(folder.read("2026-07.md") == changed)
}

@Test @MainActor func cancelsWhenTheDayIsGone() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let one = repository.entries[0]

    let changed = "## 2026-07-30\n\n- one\n"
    changeBehindOurBack(folder, "2026-07.md", to: changed)

    // The text matches, but in a different day — §4.4 says that never counts.
    await #expect(throws: NotesError.entryVanished) { try await repository.setDone(true, for: one) }
    #expect(folder.read("2026-07.md") == changed)
}

@Test @MainActor func neverMatchesAnIdenticalLineInAnotherDay() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- standup\n\n## 2026-07-30\n\n- standup\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    let onThe29th = repository.entries[0]

    changeBehindOurBack(
        folder, "2026-07.md",
        to: "## 2026-07-29\n\n- moved down\n- standup\n\n## 2026-07-30\n\n- standup\n"
    )

    try await repository.setDone(true, for: onThe29th)

    #expect(folder.read("2026-07.md")
            == "## 2026-07-29\n\n- moved down\n- [x] standup\n\n## 2026-07-30\n\n- standup\n")
}

@Test @MainActor func appendUsesTheCurrentContentNotAStaleCopy() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    changeBehindOurBack(folder, "2026-07.md", to: "## 2026-07-29\n\n- one\n- added elsewhere\n")

    try await repository.append(text: "ours", on: day29)

    #expect(folder.read("2026-07.md") == "## 2026-07-29\n\n- one\n- added elsewhere\n- ours\n")
}
