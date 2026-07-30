# dnotes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app that captures a line of text into plain markdown files in under two seconds from any application, and shows those lines back as one keyboard-driven reverse-chronological list.

**Architecture:** Five units with one responsibility each, per design §5. `MarkdownDocument` is a pure value type that parses markdown into lines and serializes back byte for byte. `NotesRepository` is a **protocol** — the storage seam — and `MarkdownNotesRepository` is its file-backed implementation, the only code in the project that touches the filesystem. `NotesModel` (`@Observable`) holds UI state and talks to the protocol, never to the implementation. `HotKeyManager` wraps Carbon `RegisterEventHotKey`. `CapturePanel` is a non-activating `NSPanel`. Views read the model and never reach for the repository.

**Tech Stack:** Swift 6.2, SwiftPM (no Xcode project), SwiftUI + AppKit, Carbon.HIToolbox for the global hotkey, FSEvents for folder watching, swift-testing for tests. No third-party dependencies.

**Spec:** [2026-07-29-dnotes-design.md](../2026-07-29-dnotes-design.md). Section references (§4.3, §6, …) throughout the plan point at it. **Read the spec section a task cites before writing code for that task.**

---

## The storage seam

The design's §5 describes one repository that reads and writes markdown files. This plan splits that
into a protocol and an implementation, so the backend can be replaced without touching the model or
any view:

```
NotesModel ──▶ any NotesRepository  ◀── MarkdownNotesRepository   (files, §4)
                                    ◀── InMemoryNotesRepository   (tests)
                                    ◀── …a database or a remote backend later
```

Three rules keep the seam real rather than decorative:

1. **Nothing above the protocol knows what a file is.** An entry is a `NoteEntry` carrying an
   opaque `EntryID`. The markdown implementation's own vocabulary — month file, line index, raw
   line text, the duplicate ordinal of §4.4 — lives in a private table inside that implementation
   and never appears in a signature the model can see. If a `month` or `lineIndex` ever shows up in
   `NotesModel` or a view, the seam has already leaked.
2. **The protocol is `async throws`.** The file implementation never actually suspends, and paying
   that cost up front is the difference between a seam a network or database backend can slot into
   and one that would have to be redesigned first.
3. **A second implementation exists from the start.** `InMemoryNotesRepository` is written in the
   same task as the protocol and is what `NotesModel`'s tests run against. A protocol with one
   conformer is a guess; a protocol with two is a seam that has been shown to work.

What deliberately stays *outside* the protocol: choosing a folder, importing `notes.md`, and the
folder-unavailable banner's "choose folder" button. Those are markdown-specific, so the app layer
talks to `MarkdownNotesRepository` directly for them, in exactly one place
([04-app-shell.md](04-app-shell.md)). A backend swap changes that one place and nothing else.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Swift tools version 6.2**, `platforms: [.macOS(.v14)]`. macOS 14 is the floor because
  `@Observable` and `MenuBarExtra` need it.
- **No third-party dependencies.** `Package.swift` has an empty `dependencies:` array and keeps it that way.
- **Tests run through `./scripts/test.sh`, not bare `swift test`.** The script detects the active
  toolchain and adapts, so it keeps working whichever one is installed. All tests are swift-testing
  (`import Testing`, `@Test`, `#expect`) — that is the project's choice, and it is also the only
  option under Command Line Tools.
  - With **full Xcode** (installed 2026-07-29, Xcode 26.6 / Swift 6.3.3) the script just runs
    `swift test`.
  - With **Command Line Tools only** it has to work around two things: SwiftPM does not add the
    framework search path for `Testing.framework` (that is Xcode's job), and CLT ships
    `_Testing_Foundation.framework` **without its `.swiftmodule`**, so importing `Testing` and
    `Foundation` in the same file fails. `XCTest` is not available at all in that configuration.
    Never bake the flags into `Package.swift` as `unsafeFlags`: the build then succeeds and zero
    tests run, silently.
- **Signing and notarization are still out of scope** (design §11) — but no longer for the reason
  the spec gave. Xcode is installed; what is missing is a Developer ID certificate
  (`security find-identity -v -p codesigning` → 0 identities), which needs the paid Apple Developer
  Program. `scripts/bundle.sh` ad-hoc signs, which is what an unsigned personal build wants.
- **The Swift tools version stays 6.2** even though the toolchain is 6.3.3: nothing here needs 6.3,
  and a lower floor keeps the package buildable from Command Line Tools.
- **The app is not sandboxed**, so folder access is a plain path — no security-scoped bookmarks.
- **The Dock icon is a setting** (`SettingsStore.showsDockIcon`, amended 2026-07-30, see
  design §7): off by default, so the app is a menu-bar accessory and stays out of
  `⌘Tab`. `LSUIElement` in `Info.plist` is only the launch default; `main.swift` applies
  the stored setting through `AppDelegate.applyActivationPolicy()`. The capture panel's
  non-activating behaviour comes from its style mask and is unaffected by the activation
  policy either way.
- **The app installs a main menu** (`MainMenu.swift`). Not decoration: macOS dispatches
  `⌘`-key equivalents through the main menu before offering them to windows, so
  without an Edit menu the capture field has no copy, paste, select-all or undo, and
  there is no `⌘Q`.
- **Storage format is fixed by §4** and is not open for reinterpretation:
  - one file per month, named `YYYY-MM.md`, in one flat folder;
  - files are discovered by that **exact** pattern; subdirectories are never traversed; `README.md`, `notes.md`, `2026-07 2.md`, `2026-07 (conflicted copy).md` are neither read nor written;
  - day heading is `## YYYY-MM-DD`; entries are `- text`, `- [ ] text`, `- [x] text`; anything else is an unparsed line.
- **The preservation invariant (§4.3) outranks every other consideration:** `serialize(parse(text)) == text` byte for byte, always. Unparsed lines, blank lines, CRLF, a missing trailing newline — all survive untouched. The plan achieves this structurally: `Line.raw` holds the original bytes and serialization concatenates `raw + ending`; parsing never reconstructs text from structure.
- **The app has no right to silently lose text** (§8). Where an operation is ambiguous it is cancelled, never guessed.
- **Line endings on insertion:** the file's dominant style (more `CRLF` than `LF` → `CRLF`, otherwise `LF`); a new file gets `LF` (§4.3).
- **Tag syntax (§4.1):** body is letters, including non-ASCII ones, digits, `-`, `_`. A `#` opens a tag only at line start, after whitespace, or after one of `(`, `[`, `{`, `«`, `"`.
- **Default notes folder:** `~/Projects/diffora/dnotes`. **Default hotkeys:** `⌥Space` capture, `⌥⇧Space` main window. **Capture panel width:** 560 pt. **FSEvents debounce:** 200 ms. **Frequent-tag window:** last 30 days, top 3.
- **Commit after every task**, with the commit command given in the task's last step.

---

## Decisions this plan makes that the spec left open

Flagged here rather than buried, because each is a place where a reviewer could reasonably want
something else. Each is one line of code to change.

1. **The package root is `~/Projects/diffora/dnotes` itself** — the same folder that holds the notes.
   `Package.swift`, `Sources/`, `Tests/` sit next to `notes.md` and `2026-07.md`. §4's strict
   `YYYY-MM.md` pattern and the no-subdirectory rule mean the parser ignores all of it. Confirmed by
   the owner.
2. **`dnotes/` becomes its own git repository** (Task 1), separate from the surrounding `diffora`
   repo, which stops tracking it.
3. **Storage is behind a protocol** (see [The storage seam](#the-storage-seam)) rather than the
   single concrete type §5 describes. Requested by the owner so the backend can be replaced.
4. **Reopening a completed entry writes the plain `- ` form**, not `- [ ] `. §4.1 lists `- [ ]` as
   compatibility with other tools; `- ` is dnotes' native form, so a toggle round-trip normalizes
   toward it. Text after the marker is preserved byte for byte either way (§4.2).
5. **"Completed today" means the entry's *day heading* is today** (§7). Completion time is not
   stored anywhere in the file format, so it cannot mean anything else without adding a field, which
   §2 forbids.
6. **Within a day, entries display in file order (ascending);** days themselves are
   reverse-chronological. Matching the file avoids a discrepancy between what the list shows and
   what an editor shows. One `.reversed()` in `NotesModel.visibleEntries` flips it if that turns out
   to be wrong in daily use.
7. **Tags keep the case they were written in**, so `#OSS` and `#oss` are two tags. Folding case
   would need a separate display form and match form; if two spellings of one tag turn up in real
   use, fold inside `TagScanner` and nowhere else.
8. **After any successful write the markdown implementation re-reads the whole folder.** At the
   volumes §5.2 assumes this is microseconds, and it removes an entire class of "in-memory state
   drifted from disk" bugs.
9. **`MarkdownNotesRepository` is `@MainActor` with synchronous file IO** behind the async protocol.
   Parsing tens of thousands of lines is fast enough not to block a frame. A backend that genuinely
   needs to suspend already has the `async` it needs.

---

## File Structure

```
dnotes/
  Package.swift
  .gitignore
  scripts/
    test.sh                      # the only supported way to run tests
    bundle.sh                    # builds dnotes.app from the SwiftPM binary
  Sources/
    DnotesCore/                  # library — no AppKit, no SwiftUI, fully testable
      CalendarDay.swift          # CalendarDay, MonthID value types
      Document.swift             # Line, Entry, LineKind, LineEnding, Document
      MarkdownParser.swift       # Document.parse
      TagScanner.swift           # tag extraction per §4.1
      DocumentEdits.swift        # insertDay, appendEntry, setDone, replaceText, removeLine
      NotesRepository.swift      # THE SEAM: protocol, NoteEntry, EntryID, NotesError
      InMemoryNotesRepository.swift  # second conformer: tests and previews
      Markdown/
        MarkdownNotesRepository.swift  # file-backed conformer
        EntryLocation.swift      # month + line + raw + duplicate ordinal (private vocabulary)
        FileDiscovery.swift      # YYYY-MM.md matching, folder listing
        AtomicWriter.swift       # temp file + replaceItemAt, returns new mtime
        NotesImporter.swift      # one-time notes.md -> YYYY-MM.md split
        FolderWatcher.swift      # FSEvents + 200 ms debounce
      PendingQueue.swift         # confirmed-but-unwritten entries, survives restart
      NotesModel.swift           # @Observable UI state, knows only the protocol
      TagCompletionModel.swift   # completion state for the capture field
      SettingsStore.swift        # folder path, hotkeys, panel draft (UserDefaults)
      HotKeyCombo.swift          # keyCode + modifiers, display string
    Dnotes/                      # executable — AppKit + SwiftUI
      DnotesApp.swift            # @main, MenuBarExtra, Window, Settings scenes
      Composition.swift          # the ONE place that names MarkdownNotesRepository
      HotKeyManager.swift        # Carbon RegisterEventHotKey
      CapturePanel.swift         # NSPanel .nonactivatingPanel
      CaptureView.swift          # the one text field
      MainWindowView.swift       # the list
      EntryRowView.swift         # one line in the list
      TagChipsView.swift         # tag filter chips
      SettingsView.swift         # folder picker, hotkey fields, conflict message
      FolderBannerView.swift     # "storage unavailable — choose folder"
  Tests/
    DnotesCoreTests/
      CalendarDayTests.swift
      RoundTripTests.swift       # §4.3, the densest file in the project
      ParsingTests.swift
      TagScannerTests.swift
      DocumentEditsTests.swift
      InMemoryRepositoryTests.swift
      FileDiscoveryTests.swift
      ImportTests.swift
      RepositoryMutationTests.swift
      MTimeGuardTests.swift
      FolderWatcherTests.swift
      PendingQueueTests.swift
      NotesModelTests.swift
      TempFolder.swift           # shared test helper
  spike/                         # Task 0, deleted at the end of Task 1
  2026-07-29-dnotes-design.md
  plan/
    README.md                    # this file
  notes.md                       # existing notes, imported on first launch
  2026-07.md                     # created by the import
```

---

## Tasks

Order follows design §10. Every task ends with a green `./scripts/test.sh` (or, for UI tasks, a
stated manual check) and a commit.

| # | Task | File | §10 |
| --- | --- | --- | --- |
| 0 | Capture panel spike, thrown away | [00-spike-and-foundation.md](00-spike-and-foundation.md) | 0 |
| 1 | Git repo, SwiftPM package, test harness | [00-spike-and-foundation.md](00-spike-and-foundation.md) | — |
| 2 | `CalendarDay` and `MonthID` | [01-markdown-document.md](01-markdown-document.md) | 1 |
| 3 | `Document.parse` / `serialize` — the round-trip invariant | [01-markdown-document.md](01-markdown-document.md) | 1 |
| 4 | Tag scanner | [01-markdown-document.md](01-markdown-document.md) | 1 |
| 5 | Document edits: day insertion, append, toggle, edit, delete | [01-markdown-document.md](01-markdown-document.md) | 1 |
| 6 | **The storage seam:** protocol, `NoteEntry`, in-memory conformer | [02-notes-repository.md](02-notes-repository.md) | 2 |
| 7 | Markdown backend: file discovery and load | [02-notes-repository.md](02-notes-repository.md) | 2 |
| 8 | Markdown backend: one-time `notes.md` import | [02-notes-repository.md](02-notes-repository.md) | 2 |
| 9 | Markdown backend: mutations, atomic write, mtime guard | [02-notes-repository.md](02-notes-repository.md) | 2 |
| 10 | Markdown backend: FSEvents watching with debounce | [02-notes-repository.md](02-notes-repository.md) | 2 |
| 11 | `PendingQueue` | [03-notes-model.md](03-notes-model.md) | 3 |
| 12 | `NotesModel`: search, tag filter, completed visibility | [03-notes-model.md](03-notes-model.md) | 3 |
| 13 | App skeleton: `MenuBarExtra`, composition root, `.app` bundle | [04-app-shell.md](04-app-shell.md) | 4 |
| 14 | `HotKeyManager` and hotkey conflict reporting | [04-app-shell.md](04-app-shell.md) | 5 |
| 15 | `CapturePanel` + `CaptureView` — end-to-end capture | [05-capture-panel.md](05-capture-panel.md) | 5 |
| 16 | Tag completion and `⌘1`–`⌘3` | [05-capture-panel.md](05-capture-panel.md) | 6 |
| 17 | Main window: list, days, keyboard navigation, toggle | [06-main-window.md](06-main-window.md) | 7 |
| 18 | Search and tag chips | [06-main-window.md](06-main-window.md) | 8 |
| 19 | Error handling: banner, panel draft, pending queue, badge | [07-errors-and-polish.md](07-errors-and-polish.md) | 9 |
| 20 | Visual polish and the §9.3 manual checklist | [07-errors-and-polish.md](07-errors-and-polish.md) | 10 |

---

## Public API, fixed across tasks

Later tasks depend on these exact names and types. An implementer who sees only their own task reads
this section to learn what its neighbours expose.

### Value types (Tasks 2–5)

```swift
// CalendarDay.swift
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int
    public init(year: Int, month: Int, day: Int)
    public init?(iso: String)                                   // strict "YYYY-MM-DD"
    public static func today(now: Date = Date(), calendar: Calendar = .current) -> CalendarDay
    public func startOfDay(in calendar: Calendar = .current) -> Date?
    public var description: String                              // "2026-07-29"
    public var monthID: MonthID
}
public struct MonthID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int, month: Int
    public init(year: Int, month: Int)
    public init?(fileName: String)                              // strict "YYYY-MM.md"
    public var fileName: String                                 // "2026-07.md"
    public var description: String                              // "2026-07"
}

// Document.swift
public enum LineEnding: String, Sendable { case lf = "\n", crlf = "\r\n" }
public struct Entry: Equatable, Sendable {
    public var text: String            // after the marker, byte for byte
    public var isDone: Bool
    public var tags: [String]
}
public enum LineKind: Equatable, Sendable {
    case dayHeading(CalendarDay)
    case entry(Entry)
    case other
}
public struct Line: Equatable, Sendable {
    public var raw: String             // WITHOUT the terminator; the source of truth
    public var ending: LineEnding?     // nil only for a final line with no trailing newline
    public var kind: LineKind
}
public struct Document: Equatable, Sendable {
    public var lines: [Line]
    public static func parse(_ text: String) -> Document
    public func serialize() -> String
    public var dominantEnding: LineEnding
}

// TagScanner.swift
public enum TagScanner { public static func tags(in text: String) -> [String] }

// DocumentEdits.swift
extension Document {
    public func dayHeadingIndex(for day: CalendarDay) -> Int?
    public func dayLineRange(headingIndex: Int) -> Range<Int>
    public mutating func insertDay(_ day: CalendarDay) -> Int          // heading line index
    public mutating func appendEntry(text: String, to day: CalendarDay) -> Int
    public mutating func setDone(_ done: Bool, atLine index: Int)
    public mutating func replaceText(atLine index: Int, with newText: String)
    public mutating func removeLine(at index: Int)
}
```

### The storage seam (Task 6)

```swift
// NotesRepository.swift

/// Opaque above the storage layer. Only the implementation that minted an id knows
/// what is inside it — for the markdown backend that is "file + line", recomputed on
/// every read (§4.1), never written into a file.
public struct EntryID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public var description: String { rawValue }
}

/// One entry as everything above storage sees it. No file, no line number, no tags
/// field in any backing store — `tags` is derived from `text` (§4.1).
public struct NoteEntry: Identifiable, Hashable, Sendable {
    public let id: EntryID
    public let day: CalendarDay
    public let text: String
    public let isDone: Bool
    public let tags: [String]
    public init(id: EntryID, day: CalendarDay, text: String, isDone: Bool, tags: [String])
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

@MainActor
public protocol NotesRepository: AnyObject {
    /// Ascending by day, then by the store's own insertion order within a day.
    var entries: [NoteEntry] { get }
    /// True when the store can be read and written right now.
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

// InMemoryNotesRepository.swift — second conformer, used by NotesModel's tests and previews.
@MainActor public final class InMemoryNotesRepository: NotesRepository {
    public init(entries: [(day: CalendarDay, text: String, isDone: Bool)] = [])
    /// Test hooks: make the next call fail, to drive the §8 error paths.
    public var isAvailable: Bool { get set }
    public var nextWriteError: NotesError?
}
```

### The markdown backend (Tasks 7–10)

Everything here is `internal` to the implementation except the type itself and the two
folder-specific members the app's composition root needs.

```swift
// Markdown/MarkdownNotesRepository.swift
@MainActor public final class MarkdownNotesRepository: NotesRepository {
    public init(folder: URL, calendar: Calendar = .current, now: @escaping () -> Date = { Date() })
    public private(set) var folder: URL
    /// Folder-specific, deliberately NOT on the protocol — see "The storage seam".
    public func setFolder(_ url: URL) async throws
}

// Markdown/EntryLocation.swift — the implementation's private vocabulary
struct EntryLocation: Hashable, Sendable {
    let month: MonthID
    let lineIndex: Int
    let rawLine: String
    let duplicateOrdinal: Int      // N-th identical raw line within its day (§4.4)
}

// Markdown/FileDiscovery.swift
public struct MonthFile: Hashable, Sendable { public let month: MonthID; public let url: URL }
public enum FileDiscovery { public static func monthFiles(in folder: URL) throws -> [MonthFile] }

// Markdown/AtomicWriter.swift
public enum AtomicWriter {
    @discardableResult public static func write(_ text: String, to url: URL) throws -> Date
}

// Markdown/NotesImporter.swift
public enum NotesImporter {
    public static let legacyFileName = "notes.md"
    public static func split(_ text: String) -> [MonthID: String]
}

// Markdown/FolderWatcher.swift
public final class FolderWatcher: @unchecked Sendable {
    public init(folder: URL, debounceMilliseconds: Int = 200,
                queue: DispatchQueue = .main, onChange: @escaping @Sendable () -> Void)
    public func start()
    public func stop()
}
```

### Model layer (Tasks 11–12)

```swift
// PendingQueue.swift
public struct PendingEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let day: CalendarDay
    public let createdAt: Date
}
@MainActor public final class PendingQueue {
    public init(defaults: UserDefaults, key: String = "dnotes.pendingQueue")
    public private(set) var entries: [PendingEntry]
    public func enqueue(text: String, day: CalendarDay, createdAt: Date)
    public func remove(id: UUID)
    public var isEmpty: Bool
}

// NotesModel.swift
public struct TagCount: Hashable, Sendable { public let tag: String; public let count: Int }
@MainActor @Observable public final class NotesModel {
    public init(repository: any NotesRepository, pending: PendingQueue,
                calendar: Calendar = .current, now: @escaping () -> Date = { Date() })
    public var searchText: String
    public var selectedTag: String?
    public var showsCompleted: Bool
    public private(set) var entries: [NoteEntry]
    public private(set) var storeAvailable: Bool
    public private(set) var lastError: String?
    public var visibleEntries: [NoteEntry] { get }               // reverse-chronological, filtered
    public var tagCounts: [TagCount] { get }
    public var topTags: [String] { get }                         // 3 most frequent, last 30 days
    public var pendingCount: Int { get }
    public func load() async
    public func add(_ text: String) async
    public func toggle(_ entry: NoteEntry) async
    public func edit(_ entry: NoteEntry, to newText: String) async
    public func delete(_ entry: NoteEntry) async
    public func drainPending() async
}
```
