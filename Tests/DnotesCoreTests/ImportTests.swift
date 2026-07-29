import Foundation
import Testing
@testable import DnotesCore

private let legacy = """
a preamble line

## 2026-06-30

- june entry
- [x] june done

> an unparsed line

## 2026-07-29

- open source editor plugin #oss
- single node metrics — ABC-1234 #infra

"""

@Test @MainActor func splitsALegacyFileByMonth() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    #expect(folder.exists("2026-06.md"))
    #expect(folder.exists("2026-07.md"))
    #expect(repository.entries.map(\.text) == [
        "june entry", "june done",
        "open source editor plugin #oss",
        "single node metrics — ABC-1234 #infra",
    ])
}

@Test @MainActor func importKeepsEveryLineIncludingUnparsedOnes() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)
    try await MarkdownNotesRepository(folder: folder.url).load()

    let rejoined = folder.read("2026-06.md") + folder.read("2026-07.md")
    #expect(rejoined == legacy)
}

@Test @MainActor func preambleGoesToTheTopOfTheEarliestFile() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)
    try await MarkdownNotesRepository(folder: folder.url).load()

    #expect(folder.read("2026-06.md").hasPrefix("a preamble line\n"))
}

@Test @MainActor func importLeavesNotesMdOnDisk() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)
    try await MarkdownNotesRepository(folder: folder.url).load()

    #expect(folder.exists("notes.md"))
    #expect(folder.read("notes.md") == legacy)
}

@Test @MainActor func importRunsOnlyOnce() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)
    try await MarkdownNotesRepository(folder: folder.url).load()

    // A month file now exists, so the next launch must not import again — even if
    // notes.md has grown since.
    folder.write("notes.md", legacy + "## 2026-08-01\n\n- august\n")
    let second = MarkdownNotesRepository(folder: folder.url)
    try await second.load()

    #expect(!folder.exists("2026-08.md"))
    #expect(!second.entries.contains { $0.text == "august" })
}

@Test @MainActor func aFolderThatAlreadyHasMonthFilesIsNotImportedInto() async throws {
    let folder = TempFolder()
    folder.write("notes.md", legacy)
    folder.write("2026-07.md", "## 2026-07-29\n\n- existing\n")

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    #expect(!folder.exists("2026-06.md"))
    #expect(repository.entries.map(\.text) == ["existing"])
}

@Test @MainActor func aLegacyFileWithNoDayHeadingsIsLeftAlone() async throws {
    let folder = TempFolder()
    folder.write("notes.md", "just some prose\nwith no day headings\n")

    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    #expect(repository.entries.isEmpty)
    #expect(try FileDiscovery.monthFiles(in: folder.url).isEmpty)
    #expect(folder.read("notes.md") == "just some prose\nwith no day headings\n")
}

@Test func atomicWriteReplacesContentAndReportsTheNewMTime() throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "old\n", modified: Date(timeIntervalSince1970: 1_000_000))

    let mtime = try AtomicWriter.write("new\n", to: folder.path("2026-07.md"))

    #expect(folder.read("2026-07.md") == "new\n")
    #expect(mtime == folder.modificationDate("2026-07.md"))
    #expect(mtime > Date(timeIntervalSince1970: 1_000_000))
}

@Test func atomicWriteLeavesNoTemporaryFilesBehind() throws {
    let folder = TempFolder()
    try AtomicWriter.write("new\n", to: folder.path("2026-07.md"))

    let all = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
    #expect(all == ["2026-07.md"])
}
