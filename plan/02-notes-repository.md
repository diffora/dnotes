# Tasks 6–10: The storage seam and its markdown backend

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) and [The storage seam](README.md#the-storage-seam) first — both apply to every task here.

Design §10 step 2, tested per §9.2.

Task 6 defines the protocol everything above storage talks to, plus a second conformer so the seam
is exercised from the first commit. Tasks 7–10 build the markdown backend §4 specifies: discovery,
import, the write path with the §4.4 mtime guard, and FSEvents watching. The backend is driven by a
folder path injected at init, so tests run against a temporary directory and never against the
owner's notes.

---

### Task 6: The storage seam — protocol, `NoteEntry`, in-memory conformer

**Files:**
- Create: `Sources/DnotesCore/NotesRepository.swift`, `Sources/DnotesCore/InMemoryNotesRepository.swift`
- Test: `Tests/DnotesCoreTests/RepositoryConformance.swift`, `Tests/DnotesCoreTests/InMemoryRepositoryTests.swift`

**Interfaces:**
- Consumes: `CalendarDay` (Task 2), `TagScanner` (Task 4).
- Produces: `EntryID`, `NoteEntry`, `NotesError`, `protocol NotesRepository`,
  `InMemoryNotesRepository`, exactly as written in
  [README.md](README.md#the-storage-seam-task-6). Also the reusable test function
  `assertRepositoryConformance(_:)`, which Task 9 runs against the markdown backend.

**Why `NoteEntry` has no `month` and no `lineIndex`:** those are markdown facts. §4.1 says an
entry's identity is "file + line number, recomputed on every read" — that is a statement about how
*the file backend* identifies a line, not about what a note is. Above the seam an entry is an
opaque `EntryID` plus what the user typed. A backend that keeps notes in rows or documents mints
its ids however it likes and nothing above notices.

- [ ] **Step 1: Write the reusable conformance checks**

`Tests/DnotesCoreTests/RepositoryConformance.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing in-memory tests**

`Tests/DnotesCoreTests/InMemoryRepositoryTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter "InMemory|Conformance"`
Expected: FAIL, `cannot find 'InMemoryNotesRepository' in scope`.

- [ ] **Step 4: Define the seam**

`Sources/DnotesCore/NotesRepository.swift`:

```swift
import Foundation

/// Opaque above the storage layer. Only the backend that minted an id knows what is
/// inside it — for the markdown backend that is "file + line", recomputed on every
/// read (§4.1) and never written into a file.
public struct EntryID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// One entry as everything above storage sees it: what the user typed, which day it
/// belongs to, and whether it is closed. No file, no line number. `tags` is derived
/// from `text` (§4.1) — no backend stores it separately.
public struct NoteEntry: Identifiable, Hashable, Sendable {
    public let id: EntryID
    public let day: CalendarDay
    public let text: String
    public let isDone: Bool
    public let tags: [String]

    public init(id: EntryID, day: CalendarDay, text: String, isDone: Bool, tags: [String]) {
        self.id = id
        self.day = day
        self.text = text
        self.isDone = isDone
        self.tags = tags
    }
}

public enum NotesError: Error, Equatable {
    /// The store cannot be reached at all: folder missing, not downloaded, endpoint down.
    case storeUnavailable(String)
    /// The entry is no longer where it was and cannot be identified safely (§4.4).
    case entryVanished
    /// Identical candidates could not be told apart — cancelled rather than guessed (§4.4).
    case ambiguousMatch
    case writeFailed(String)
}

/// The storage seam. `NotesModel` and every view know this and nothing below it.
///
/// The methods are `async` although the markdown backend never suspends: that is
/// what makes a database or a remote backend a drop-in rather than a redesign.
@MainActor
public protocol NotesRepository: AnyObject {
    /// Ascending by day, then by the store's own insertion order within a day.
    var entries: [NoteEntry] { get }

    /// Whether the store can be read and written right now.
    var isAvailable: Bool { get }

    /// Fired after a change that did *not* originate from this object's own methods.
    var onExternalChange: (@MainActor () -> Void)? { get set }

    func load() async throws
    @discardableResult func append(text: String, on day: CalendarDay) async throws -> NoteEntry
    func setDone(_ done: Bool, for entry: NoteEntry) async throws
    func edit(_ entry: NoteEntry, to newText: String) async throws
    func delete(_ entry: NoteEntry) async throws

    func startObserving()
    func stopObserving()
}
```

- [ ] **Step 5: Write the second conformer**

`Sources/DnotesCore/InMemoryNotesRepository.swift`:

```swift
import Foundation

/// The second conformer: what `NotesModel`'s tests and SwiftUI previews run against,
/// and the thing that keeps the seam honest. If a change to `NotesModel` cannot be
/// expressed against this type, it has reached through the seam.
@MainActor
public final class InMemoryNotesRepository: NotesRepository {
    private struct Record {
        let id: EntryID
        var day: CalendarDay
        var text: String
        var isDone: Bool
    }

    private var records: [Record] = []
    private var nextNumber = 0

    public var isAvailable: Bool = true
    /// Makes the next write fail once, so the §8 error paths can be driven from a test.
    public var nextWriteError: NotesError?
    public var onExternalChange: (@MainActor () -> Void)?

    public init(entries: [(day: CalendarDay, text: String, isDone: Bool)] = []) {
        for entry in entries {
            records.append(Record(id: mintID(), day: entry.day, text: entry.text, isDone: entry.isDone))
        }
    }

    public var entries: [NoteEntry] {
        records.enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map { NoteEntry(id: $0.element.id, day: $0.element.day, text: $0.element.text,
                             isDone: $0.element.isDone, tags: TagScanner.tags(in: $0.element.text)) }
    }

    public func load() async throws {
        try requireAvailable()
    }

    @discardableResult
    public func append(text: String, on day: CalendarDay) async throws -> NoteEntry {
        try requireWritable()
        let record = Record(id: mintID(), day: day, text: text, isDone: false)
        records.append(record)
        return NoteEntry(id: record.id, day: day, text: text, isDone: false,
                         tags: TagScanner.tags(in: text))
    }

    public func setDone(_ done: Bool, for entry: NoteEntry) async throws {
        try update(entry) { $0.isDone = done }
    }

    public func edit(_ entry: NoteEntry, to newText: String) async throws {
        try update(entry) { $0.text = newText }
    }

    public func delete(_ entry: NoteEntry) async throws {
        try requireWritable()
        guard let index = records.firstIndex(where: { $0.id == entry.id }) else {
            throw NotesError.entryVanished
        }
        records.remove(at: index)
    }

    public func startObserving() {}
    public func stopObserving() {}

    private func update(_ entry: NoteEntry, _ apply: (inout Record) -> Void) throws {
        try requireWritable()
        guard let index = records.firstIndex(where: { $0.id == entry.id }) else {
            throw NotesError.entryVanished
        }
        apply(&records[index])
    }

    private func requireAvailable() throws {
        guard isAvailable else { throw NotesError.storeUnavailable("in-memory store disabled") }
    }

    private func requireWritable() throws {
        try requireAvailable()
        if let error = nextWriteError {
            nextWriteError = nil
            throw error
        }
    }

    private func mintID() -> EntryID {
        nextNumber += 1
        return EntryID("memory/\(nextNumber)")
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter "InMemory|Conformance"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DnotesCore/NotesRepository.swift Sources/DnotesCore/InMemoryNotesRepository.swift Tests/DnotesCoreTests/RepositoryConformance.swift Tests/DnotesCoreTests/InMemoryRepositoryTests.swift
git commit -m "feat: storage protocol with an in-memory conformer

NoteEntry carries an opaque EntryID instead of a file and a line number, so
nothing above storage knows what a month file is. The conformance checks
are reused by the markdown backend in a later commit."
```

---

### Task 7: Markdown backend — file discovery and load

**Files:**
- Create: `Sources/DnotesCore/Markdown/FileDiscovery.swift`,
  `Sources/DnotesCore/Markdown/EntryLocation.swift`,
  `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`
- Test: `Tests/DnotesCoreTests/TempFolder.swift`, `Tests/DnotesCoreTests/FileDiscoveryTests.swift`

**Interfaces:**
- Consumes: `Document`, `CalendarDay`, `MonthID` (Tasks 2–5); the seam (Task 6).
- Produces: `MonthFile`, `FileDiscovery.monthFiles(in:)`, the internal `EntryLocation`, and
  `MarkdownNotesRepository` with `init(folder:calendar:now:)`, `folder`, `entries`, `isAvailable`,
  `setFolder(_:)`, `load()`. Mutations arrive in Task 9, observing in Task 10.
  Also the test helper `TempFolder`, used by every later test file in this part.

**Entries above the first day heading are parsed but not listed:** they have no date, and inventing
one would move text. They stay in the file untouched, which is all §8 requires.

- [ ] **Step 1: Write the test helper**

`Tests/DnotesCoreTests/TempFolder.swift`:

```swift
import Foundation

/// A throwaway directory. Every backend test gets its own, so tests never see each
/// other's files and never see the owner's notes.
final class TempFolder: @unchecked Sendable {
    let url: URL

    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dnotes-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    @discardableResult
    func write(_ name: String, _ contents: String, modified: Date? = nil) -> URL {
        let file = path(name)
        try! Data(contents.utf8).write(to: file)
        if let modified {
            try! FileManager.default.setAttributes([.modificationDate: modified],
                                                   ofItemAtPath: file.path)
        }
        return file
    }

    func read(_ name: String) -> String {
        String(decoding: try! Data(contentsOf: path(name)), as: UTF8.self)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: path(name).path)
    }

    func makeDirectory(_ name: String) {
        try! FileManager.default.createDirectory(at: path(name), withIntermediateDirectories: true)
    }

    func modificationDate(_ name: String) -> Date {
        let attributes = try! FileManager.default.attributesOfItem(atPath: path(name).path)
        return attributes[.modificationDate] as! Date
    }

    func setReadOnly(_ readOnly: Bool) {
        try! FileManager.default.setAttributes([.posixPermissions: readOnly ? 0o500 : 0o755],
                                               ofItemAtPath: url.path)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/DnotesCoreTests/FileDiscoveryTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter FileDiscovery`
Expected: FAIL, `cannot find 'FileDiscovery' in scope`.

- [ ] **Step 4: Implement discovery and the backend's private entry vocabulary**

`Sources/DnotesCore/Markdown/FileDiscovery.swift`:

```swift
import Foundation

public struct MonthFile: Hashable, Sendable {
    public let month: MonthID
    public let url: URL
}

public enum FileDiscovery {
    /// Notes files in `folder`, ascending by month. Subdirectories are not traversed
    /// and only the exact `YYYY-MM.md` pattern counts (§4) — that pattern is what
    /// keeps cloud conflict copies from showing the same month twice.
    public static func monthFiles(in folder: URL) throws -> [MonthFile] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        )

        return contents
            .compactMap { url -> MonthFile? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory != true else { return nil }
                guard let month = MonthID(fileName: url.lastPathComponent) else { return nil }
                return MonthFile(month: month, url: url)
            }
            .sorted { $0.month < $1.month }
    }
}
```

`Sources/DnotesCore/Markdown/EntryLocation.swift`:

```swift
import Foundation

/// Where an entry sits in the markdown files. This is the backend's private
/// vocabulary: §4.1 identity ("file + line", recomputed on every read) plus the two
/// facts §4.4 needs to find the line again after the file changed underneath us.
/// It never crosses the storage seam.
struct EntryLocation: Hashable, Sendable {
    let month: MonthID
    let lineIndex: Int
    let rawLine: String
    /// N-th identical raw line within its day, 0-based.
    let duplicateOrdinal: Int
}
```

- [ ] **Step 5: Implement the backend's read path**

`Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`:

```swift
import Foundation

/// The §4 backend: one flat folder, one markdown file per month.
///
/// `@MainActor` with synchronous IO behind an async protocol. At the volumes §5.2
/// assumes, parsing a folder is microseconds, and staying on one actor keeps the
/// concurrency story trivial. A backend that genuinely needs to suspend already has
/// the `async` it needs.
@MainActor
public final class MarkdownNotesRepository: NotesRepository {
    public private(set) var folder: URL
    public private(set) var entries: [NoteEntry] = []
    public var onExternalChange: (@MainActor () -> Void)?

    let calendar: Calendar
    let now: () -> Date

    /// The seam's opaque ids resolved back to file positions. Rebuilt on every load,
    /// exactly as §4.1 prescribes.
    private var locations: [EntryID: EntryLocation] = [:]

    /// The mtime each month file had when we last read it. This doubles as the
    /// self-write filter in Task 10: our own writes update it, so they never look
    /// like an external change.
    var readMTimes: [MonthID: Date] = [:]

    public init(folder: URL, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.folder = folder
        self.calendar = calendar
        self.now = now
    }

    public var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Folder-specific, deliberately not on the protocol.
    public func setFolder(_ url: URL) async throws {
        let wasObserving = isObserving
        stopObserving()
        folder = url
        readMTimes.removeAll()
        locations.removeAll()
        entries = []
        try await load()
        if wasObserving { startObserving() }
    }

    public func load() async throws {
        try loadNow()
    }

    /// The synchronous core, so the write path can reload without awaiting itself.
    func loadNow() throws {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }
        try importLegacyNotesIfNeeded()

        var loaded: [NoteEntry] = []
        var found: [EntryID: EntryLocation] = [:]
        var mtimes: [MonthID: Date] = [:]

        for file in try FileDiscovery.monthFiles(in: folder) {
            let (text, mtime) = try read(file.url)
            mtimes[file.month] = mtime
            for scanned in Self.scan(Document.parse(text), month: file.month) {
                found[scanned.entry.id] = scanned.location
                loaded.append(scanned.entry)
            }
        }

        readMTimes = mtimes
        locations = found
        entries = loaded
    }

    static func scan(_ document: Document, month: MonthID)
        -> [(entry: NoteEntry, location: EntryLocation)] {
        var result: [(entry: NoteEntry, location: EntryLocation)] = []
        var day: CalendarDay?
        var seenInDay: [String: Int] = [:]

        for (index, line) in document.lines.enumerated() {
            switch line.kind {
            case .dayHeading(let heading):
                day = heading
                seenInDay.removeAll()          // ordinals are scoped to one day (§4.4)
            case .entry(let parsed):
                guard let day else { continue }  // no heading above it, so no date
                let ordinal = seenInDay[line.raw, default: 0]
                seenInDay[line.raw] = ordinal + 1
                let id = EntryID("\(month)/\(index)")
                result.append((
                    entry: NoteEntry(id: id, day: day, text: parsed.text,
                                     isDone: parsed.isDone, tags: parsed.tags),
                    location: EntryLocation(month: month, lineIndex: index,
                                            rawLine: line.raw, duplicateOrdinal: ordinal)
                ))
            case .other:
                break
            }
        }

        return result
    }

    /// Visible to the backend's own tests only — nothing above the seam may call it.
    func location(of id: EntryID) -> EntryLocation? { locations[id] }

    /// Notes are UTF-8. Invalid bytes are replaced rather than throwing: refusing to
    /// open the file would hide more text than a replacement character does.
    func read(_ url: URL) throws -> (text: String, mtime: Date) {
        let data = try Data(contentsOf: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (String(decoding: data, as: UTF8.self),
                attributes[.modificationDate] as? Date ?? .distantPast)
    }

    func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? .distantPast
    }

    // Filled in by Task 8.
    func importLegacyNotesIfNeeded() throws {}

    // Filled in by Task 10.
    var isObserving = false
    public func startObserving() {}
    public func stopObserving() {}
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter FileDiscovery`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DnotesCore/Markdown Tests/DnotesCoreTests/TempFolder.swift Tests/DnotesCoreTests/FileDiscoveryTests.swift
git commit -m "feat: markdown backend read path

Only exact YYYY-MM.md files are read and subdirectories are skipped, so
iCloud and Dropbox conflict copies cannot double a month. File positions
and duplicate ordinals stay in a private table keyed by the seam's opaque
EntryID."
```

---

### Task 8: Markdown backend — one-time `notes.md` import

**Files:**
- Create: `Sources/DnotesCore/Markdown/NotesImporter.swift`, `Sources/DnotesCore/Markdown/AtomicWriter.swift`
- Modify: `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift` (`importLegacyNotesIfNeeded`)
- Test: `Tests/DnotesCoreTests/ImportTests.swift`

**Interfaces:**
- Consumes: `Document`, `MonthID`, `FileDiscovery`.
- Produces: `NotesImporter.legacyFileName`, `NotesImporter.split(_:)`, and
  `AtomicWriter.write(_:to:) -> Date`, which Task 9 also uses.

**`notes.md` is neither deleted nor renamed** (§4). It simply stops matching the pattern.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/ImportTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter "Import|atomicWrite"`
Expected: FAIL, `cannot find 'AtomicWriter' in scope`.

- [ ] **Step 3: Implement the atomic writer**

`Sources/DnotesCore/Markdown/AtomicWriter.swift`:

```swift
import Foundation

public enum AtomicWriter {
    /// Writes through a temporary file next to the target and then replaces it, so a
    /// crash mid-write cannot leave a half-written notes file (§4.4). The temporary
    /// name is dot-prefixed, so it is hidden and cannot match `YYYY-MM.md`.
    @discardableResult
    public static func write(_ text: String, to url: URL) throws -> Date {
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        try Data(text.utf8).write(to: temporary)

        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }

        let attributes = try manager.attributesOfItem(atPath: url.path)
        return attributes[.modificationDate] as? Date ?? Date()
    }
}
```

- [ ] **Step 4: Implement the importer**

`Sources/DnotesCore/Markdown/NotesImporter.swift`:

```swift
import Foundation

/// The one-time migration from a flat `notes.md` to one file per month (§4).
public enum NotesImporter {
    public static let legacyFileName = "notes.md"

    /// Splits a legacy file into month files. Every line goes into the month of the
    /// day heading above it, byte for byte; lines above the first heading go to the
    /// top of the earliest month. A file with no day headings yields nothing — there
    /// is no month to file it under, and inventing one would move someone's text.
    public static func split(_ text: String) -> [MonthID: String] {
        let document = Document.parse(text)
        var preamble: [Line] = []
        var buckets: [MonthID: [Line]] = [:]
        var current: MonthID?

        for line in document.lines {
            if case .dayHeading(let day) = line.kind {
                current = day.monthID
            }
            guard let month = current else {
                preamble.append(line)
                continue
            }
            buckets[month, default: []].append(line)
        }

        guard let earliest = buckets.keys.min() else { return [:] }
        if !preamble.isEmpty {
            buckets[earliest] = preamble + (buckets[earliest] ?? [])
        }

        return buckets.mapValues { Document(lines: $0).serialize() }
    }
}
```

- [ ] **Step 5: Hook the importer into `loadNow()`**

Replace the placeholder in `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`:

```swift
    /// Runs at most once per folder: after it, month files exist and the guard below
    /// is false forever. `notes.md` is left exactly where it is — an app that
    /// promises never to lose text does not open by deleting someone's file (§4).
    func importLegacyNotesIfNeeded() throws {
        guard try FileDiscovery.monthFiles(in: folder).isEmpty else { return }
        let legacy = folder.appendingPathComponent(NotesImporter.legacyFileName)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }

        let text = try read(legacy).text
        for (month, contents) in NotesImporter.split(text) {
            do {
                try AtomicWriter.write(contents, to: folder.appendingPathComponent(month.fileName))
            } catch {
                throw NotesError.writeFailed(error.localizedDescription)
            }
        }
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter "Import|atomicWrite"`
Expected: PASS.

- [ ] **Step 7: Run the whole suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/DnotesCore/Markdown Tests/DnotesCoreTests/ImportTests.swift
git commit -m "feat: one-time notes.md import and atomic writes

The import is byte-preserving — rejoining the produced month files
reproduces notes.md exactly — and notes.md itself is left on disk."
```

---

### Task 9: Markdown backend — mutations, the mtime guard, duplicate resolution

The §4.4 rules live here. Getting them wrong means editing the wrong line, which is the one failure
mode §8 refuses to allow.

**Files:**
- Modify: `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`
- Test: `Tests/DnotesCoreTests/RepositoryMutationTests.swift`, `Tests/DnotesCoreTests/MTimeGuardTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `MarkdownNotesRepository`'s conformance to the four write methods of the protocol. Task
  12 drives them from `NotesModel` — through the protocol, never through this type.

**The rule, restated so it is not paraphrased into something weaker:**
1. search only within the same day the read came from — a match in an adjacent day never counts;
2. use the ordinal `N` among identical lines within that day, remembered at read time;
3. if the identical lines have become fewer, the `N`-th no longer exists, or the day is gone —
   cancel outright.

Ambiguity always resolves to refusal. A cancelled operation costs one repeated keystroke; a
corrupted neighbouring line costs silently lost text.

- [ ] **Step 1: Write the failing mutation tests**

`Tests/DnotesCoreTests/RepositoryMutationTests.swift`:

```swift
import Foundation
import Testing
@testable import DnotesCore

@Test @MainActor func markdownRepositoryConforms() async throws {
    // The same checks the in-memory repository passes, against real files. This is
    // what makes the seam a seam rather than a wish.
    let folders = TempFolderPool()
    try await assertRepositoryConformance {
        MarkdownNotesRepository(folder: folders.next().url)
    }
}

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
```

- [ ] **Step 2: Write the failing mtime-guard tests**

`Tests/DnotesCoreTests/MTimeGuardTests.swift`:

```swift
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

    changeBehindOurBack(folder, "2026-07.md",
                        to: "## 2026-07-29\n\n- new first\n- write the tests\n- other\n- write the tests\n")

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

    changeBehindOurBack(folder, "2026-07.md",
                        to: "## 2026-07-29\n\n- moved down\n- standup\n\n## 2026-07-30\n\n- standup\n")

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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter "RepositoryMutation|MTimeGuard"`
Expected: FAIL — `MarkdownNotesRepository` does not yet satisfy the protocol's write methods, so it
does not compile as a conformer.

- [ ] **Step 4: Implement the write path**

Append to `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`:

```swift
extension MarkdownNotesRepository {
    /// Appends to the given day, creating the day and the month file as needed.
    /// The file is re-read immediately before the write, so a change made elsewhere
    /// since the last load is picked up rather than overwritten.
    @discardableResult
    public func append(text: String, on day: CalendarDay) async throws -> NoteEntry {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }

        let url = folder.appendingPathComponent(day.monthID.fileName)
        var document = Document(lines: [])
        if FileManager.default.fileExists(atPath: url.path) {
            document = Document.parse(try read(url).text)
        }

        let index = document.appendEntry(text: text, to: day)
        readMTimes[day.monthID] = try writeAtomically(document, to: url)
        try loadNow()

        let id = EntryID("\(day.monthID)/\(index)")
        guard let created = entries.first(where: { $0.id == id }) else {
            throw NotesError.entryVanished
        }
        return created
    }

    public func setDone(_ done: Bool, for entry: NoteEntry) async throws {
        try mutate(entry) { document, index in document.setDone(done, atLine: index) }
    }

    public func edit(_ entry: NoteEntry, to newText: String) async throws {
        try mutate(entry) { document, index in document.replaceText(atLine: index, with: newText) }
    }

    public func delete(_ entry: NoteEntry) async throws {
        try mutate(entry) { document, index in document.removeLine(at: index) }
    }

    private func mutate(_ entry: NoteEntry, _ apply: (inout Document, Int) -> Void) throws {
        guard isAvailable else { throw NotesError.storeUnavailable(folder.path) }
        guard let where_ = location(of: entry.id) else { throw NotesError.entryVanished }

        let url = folder.appendingPathComponent(where_.month.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NotesError.entryVanished
        }

        let (text, mtime) = try read(url)
        var document = Document.parse(text)

        // The file changed since we read it: find the line by its text, not its number.
        let index = mtime == readMTimes[where_.month]
            ? where_.lineIndex
            : try locate(where_, on: entry.day, in: document)

        guard index < document.lines.count, document.lines[index].raw == where_.rawLine else {
            throw NotesError.entryVanished
        }

        apply(&document, index)
        readMTimes[where_.month] = try writeAtomically(document, to: url)
        try loadNow()
    }

    /// §4.4: search only within the entry's own day, pick the `duplicateOrdinal`-th
    /// identical line, and cancel rather than guess if it is not there any more.
    private func locate(_ location: EntryLocation,
                        on day: CalendarDay,
                        in document: Document) throws -> Int {
        guard let headingIndex = document.dayHeadingIndex(for: day) else {
            throw NotesError.entryVanished
        }
        let matches = document.dayLineRange(headingIndex: headingIndex)
            .filter { document.lines[$0].raw == location.rawLine }

        if matches.isEmpty { throw NotesError.entryVanished }
        guard location.duplicateOrdinal < matches.count else { throw NotesError.ambiguousMatch }
        return matches[location.duplicateOrdinal]
    }

    private func writeAtomically(_ document: Document, to url: URL) throws -> Date {
        do {
            return try AtomicWriter.write(document.serialize(), to: url)
        } catch {
            throw NotesError.writeFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter "RepositoryMutation|MTimeGuard"`
Expected: PASS, including `markdownRepositoryConforms` — the same checks the in-memory repository
passes in Task 6.

- [ ] **Step 6: Run the whole suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/DnotesCore/Markdown Tests/DnotesCoreTests/RepositoryMutationTests.swift Tests/DnotesCoreTests/MTimeGuardTests.swift
git commit -m "feat: markdown write path with the mtime guard

After an external change the target line is found by its text within its
own day and by its duplicate ordinal; anything the ordinal cannot resolve
cancels the operation and leaves the file untouched (design §4.4, §8).
Both backends now pass the same conformance checks."
```

---

### Task 10: Markdown backend — FSEvents watching with debounce

**Files:**
- Create: `Sources/DnotesCore/Markdown/FolderWatcher.swift`
- Modify: `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift` (`startObserving`, `stopObserving`)
- Test: `Tests/DnotesCoreTests/FolderWatcherTests.swift`

**Interfaces:**
- Consumes: `FileDiscovery`, `MarkdownNotesRepository.readMTimes`.
- Produces: `FolderWatcher` and a working `startObserving()` / `stopObserving()` /
  `onExternalChange` on the markdown backend.

**Self-write suppression falls out of the mtime bookkeeping already in place.** Every write updates
`readMTimes` to the mtime it just produced, so when the resulting FSEvent arrives the repository
compares the folder against a table that already matches and does nothing. No separate "ignore this
event" flag, no window during which a real external change could be swallowed.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/FolderWatcherTests.swift`:

```swift
import Foundation
import Testing
@testable import DnotesCore

/// FSEvents is asynchronous and coalescing; polling with a deadline is the honest
/// way to wait for it. Returns false on timeout so a failure reads as a failure.
@MainActor
private func waitUntil(_ timeout: Duration = .seconds(5),
                       _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

@Test @MainActor func picksUpAnExternalEdit() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    var notifications = 0
    repository.onExternalChange = { notifications += 1 }
    repository.startObserving()
    defer { repository.stopObserving() }

    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n- added in another editor\n")

    #expect(await waitUntil { repository.entries.count == 2 })
    #expect(repository.entries.last?.text == "added in another editor")
    #expect(notifications >= 1)
}

@Test @MainActor func picksUpANewMonthFile() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()
    repository.startObserving()
    defer { repository.stopObserving() }

    folder.write("2026-08.md", "## 2026-08-01\n\n- august\n")

    #expect(await waitUntil { repository.entries.count == 2 })
}

@Test @MainActor func ourOwnWriteDoesNotComeBackAsAChange() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    var notifications = 0
    repository.onExternalChange = { notifications += 1 }
    repository.startObserving()
    defer { repository.stopObserving() }

    try await repository.append(text: "ours", on: day29)

    // Give FSEvents more than the debounce to deliver an event we must ignore.
    try? await Task.sleep(for: .milliseconds(800))
    #expect(notifications == 0)
    #expect(repository.entries.count == 2)
}

@Test @MainActor func aBatchOfChangesCollapsesIntoOneReload() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    var notifications = 0
    repository.onExternalChange = { notifications += 1 }
    repository.startObserving()
    defer { repository.stopObserving() }

    // What a `git checkout` or a cloud sync looks like: several files at once.
    for month in 1...5 {
        folder.write(String(format: "2026-%02d.md", month),
                     "## 2026-\(String(format: "%02d", month))-01\n\n- entry\n")
    }

    #expect(await waitUntil { repository.entries.count == 6 })
    try? await Task.sleep(for: .milliseconds(600))
    // The 200 ms debounce is what keeps this from being five parses. FSEvents may
    // still split a burst across two deliveries; more than that means the debounce
    // is not working.
    #expect(notifications <= 2)
}

@Test @MainActor func stopObservingStopsNotifications() async throws {
    let folder = TempFolder()
    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n")
    let repository = MarkdownNotesRepository(folder: folder.url)
    try await repository.load()

    var notifications = 0
    repository.onExternalChange = { notifications += 1 }
    repository.startObserving()
    repository.stopObserving()

    folder.write("2026-07.md", "## 2026-07-29\n\n- one\n- two\n")

    try? await Task.sleep(for: .milliseconds(800))
    #expect(notifications == 0)
    #expect(repository.entries.count == 1)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter FolderWatcher`
Expected: FAIL — `picksUpAnExternalEdit` times out, because `startObserving()` is still the empty
placeholder from Task 7.

- [ ] **Step 3: Implement the watcher**

`Sources/DnotesCore/Markdown/FolderWatcher.swift`:

```swift
import Foundation

/// A dispatch-queue-backed FSEvents stream with a trailing debounce. No run loop is
/// involved, so this behaves the same in the app and in tests.
public final class FolderWatcher: @unchecked Sendable {
    private let folder: URL
    private let debounce: Int
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    public init(folder: URL,
                debounceMilliseconds: Int = 200,
                queue: DispatchQueue = .main,
                onChange: @escaping @Sendable () -> Void) {
        self.folder = folder
        self.debounce = debounceMilliseconds
        self.queue = queue
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }

        // Latency 0 — the debounce below is the one that should decide the cadence,
        // and it is the one we can test.
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folder.path as CFString] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// A `git checkout` or a cloud sync changes a batch of files at once; there is no
    /// reason to parse the folder once per event in the batch (§5.1).
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + .milliseconds(debounce), execute: item)
    }
}
```

- [ ] **Step 4: Wire the watcher into the backend**

In `Sources/DnotesCore/Markdown/MarkdownNotesRepository.swift`, replace the Task 7 placeholders
(`var isObserving`, `startObserving`, `stopObserving`) with:

```swift
    var isObserving = false
    private var watcher: FolderWatcher?

    public func startObserving() {
        guard watcher == nil else { return }
        isObserving = true
        let created = FolderWatcher(folder: folder, queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        created.start()
        watcher = created
    }

    public func stopObserving() {
        isObserving = false
        watcher?.stop()
        watcher = nil
    }

    private func folderChanged() {
        guard isAvailable, hasExternalChange() else { return }
        try? loadNow()
        onExternalChange?()
    }

    /// Our own writes have already updated `readMTimes`, so they look like no change
    /// at all — which is exactly the "do not let our write come back at us" rule of
    /// §5.1, with no extra state to get out of sync.
    private func hasExternalChange() -> Bool {
        guard let files = try? FileDiscovery.monthFiles(in: folder) else { return true }
        if files.count != readMTimes.count { return true }
        for file in files {
            guard let known = readMTimes[file.month],
                  let current = try? modificationDate(of: file.url),
                  current == known
            else { return true }
        }
        return false
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter FolderWatcher`
Expected: PASS. These are the slowest tests in the suite (a few seconds) because they wait on real
filesystem events. If `aBatchOfChangesCollapsesIntoOneReload` reports more than two notifications,
the debounce is not being applied — check that `schedule()` cancels the previous work item.

- [ ] **Step 6: Run the whole suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/DnotesCore/Markdown Tests/DnotesCoreTests/FolderWatcherTests.swift
git commit -m "feat: FSEvents folder watching with a 200ms debounce

Self-write suppression comes free from the mtime table the write path
already maintains: our own write leaves the table matching the disk, so
the resulting event finds nothing to do."
```
