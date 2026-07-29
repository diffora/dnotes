# Tasks 11–12: `PendingQueue` and `NotesModel`

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 step 3, plus the two §8 entities that are easy to conflate under the single word "draft".
Both tasks run against `InMemoryNotesRepository`: if something here cannot be expressed against the
in-memory backend, it has reached through the storage seam.

---

### Task 11: `PendingQueue`

§8 defines two different things, and the plan keeps them apart because collapsing them loses text:

| | Panel draft | Pending queue |
| --- | --- | --- |
| What | one line, typed but **not** confirmed | entries confirmed with `⏎` that could not be written |
| Shape | exactly one slot | an array |
| Why that shape | there is only one panel | three captures with iCloud detached is three entries; one slot would lose two |
| Lives in | `UserDefaults` (Task 13, `SettingsStore`) | `UserDefaults` (this task) |

Each queued entry carries **its own creation day**. When the queue drains, the entry is appended to
that day, not to today — otherwise yesterday evening's capture drifts into today and the day stops
being an honest history.

**Files:**
- Create: `Sources/DnotesCore/PendingQueue.swift`
- Test: `Tests/DnotesCoreTests/PendingQueueTests.swift`

**Interfaces:**
- Consumes: `CalendarDay` (Task 2).
- Produces: `PendingEntry`, `PendingQueue` as in [README.md](README.md#model-layer-tasks-1112).

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/PendingQueueTests.swift`:

```swift
import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func makeDefaults() -> UserDefaults {
    let suite = "dnotes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test @MainActor func enqueuesInInsertionOrder() {
    let queue = PendingQueue(defaults: makeDefaults())
    queue.enqueue(text: "first", day: day29, createdAt: Date(timeIntervalSince1970: 1))
    queue.enqueue(text: "second", day: day29, createdAt: Date(timeIntervalSince1970: 2))
    queue.enqueue(text: "third", day: day30, createdAt: Date(timeIntervalSince1970: 3))

    #expect(queue.entries.map(\.text) == ["first", "second", "third"])
    #expect(queue.entries.map(\.day) == [day29, day29, day30])
    #expect(!queue.isEmpty)
}

@Test @MainActor func survivesARestart() {
    let defaults = makeDefaults()
    let first = PendingQueue(defaults: defaults)
    first.enqueue(text: "written with the folder gone", day: day29, createdAt: Date())

    // A new instance over the same defaults is what a relaunch looks like.
    let second = PendingQueue(defaults: defaults)
    #expect(second.entries.map(\.text) == ["written with the folder gone"])
}

@Test @MainActor func removesByIdentity() {
    let queue = PendingQueue(defaults: makeDefaults())
    queue.enqueue(text: "a", day: day29, createdAt: Date())
    queue.enqueue(text: "b", day: day29, createdAt: Date())
    let first = queue.entries[0]

    queue.remove(id: first.id)

    #expect(queue.entries.map(\.text) == ["b"])
}

@Test @MainActor func removingSomethingAlreadyGoneIsHarmless() {
    let queue = PendingQueue(defaults: makeDefaults())
    queue.remove(id: UUID())
    #expect(queue.isEmpty)
}

@Test @MainActor func identicalTextsAreSeparateEntries() {
    // Three captures of the same thought are three entries, not one.
    let queue = PendingQueue(defaults: makeDefaults())
    queue.enqueue(text: "same", day: day29, createdAt: Date())
    queue.enqueue(text: "same", day: day29, createdAt: Date())

    #expect(queue.entries.count == 2)
    #expect(queue.entries[0].id != queue.entries[1].id)
}

@Test @MainActor func corruptStoredDataIsIgnoredRatherThanCrashing() {
    let defaults = makeDefaults()
    defaults.set(Data("not json".utf8), forKey: "dnotes.pendingQueue")

    #expect(PendingQueue(defaults: defaults).isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter PendingQueue`
Expected: FAIL, `cannot find 'PendingQueue' in scope`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/PendingQueue.swift`:

```swift
import Foundation

/// An entry the user confirmed with `⏎` that could not be written yet (§8).
public struct PendingEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    /// The day it was captured on — where it goes when the queue drains, so an
    /// evening capture does not drift into the next morning.
    public let day: CalendarDay
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, day: CalendarDay, createdAt: Date) {
        self.id = id
        self.text = text
        self.day = day
        self.createdAt = createdAt
    }
}

/// Confirmed entries waiting for a store that will accept them. An array, not a
/// slot: three captures in a row with the folder detached is three entries, and a
/// single cell would lose two of them (§8).
@MainActor
public final class PendingQueue {
    public private(set) var entries: [PendingEntry] = []

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "dnotes.pendingQueue") {
        self.defaults = defaults
        self.key = key
        entries = Self.decode(defaults.data(forKey: key))
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func enqueue(text: String, day: CalendarDay, createdAt: Date) {
        entries.append(PendingEntry(text: text, day: day, createdAt: createdAt))
        persist()
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }

    /// Unreadable stored data is dropped rather than thrown: refusing to launch over
    /// a corrupt queue would be a worse failure than losing what is already unreadable.
    private static func decode(_ data: Data?) -> [PendingEntry] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PendingEntry].self, from: data)) ?? []
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter PendingQueue`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DnotesCore/PendingQueue.swift Tests/DnotesCoreTests/PendingQueueTests.swift
git commit -m "feat: pending queue for confirmed entries that could not be written

Each queued entry keeps its own capture day so draining appends it to that
day rather than to today (design §8)."
```

---

### Task 12: `NotesModel`

**Files:**
- Create: `Sources/DnotesCore/NotesModel.swift`
- Test: `Tests/DnotesCoreTests/NotesModelTests.swift`

**Interfaces:**
- Consumes: the storage seam (Task 6), `PendingQueue` (Task 11), `TagScanner` (Task 4).
- Produces: `TagCount` and `NotesModel` as in [README.md](README.md#model-layer-tasks-1112). Every
  view in Tasks 13–20 reads this and nothing below it.

**Filter semantics, decided here so views do not each invent their own:**
- **Completed visibility (§7):** an entry completed on *today's* day heading stays visible; a
  completed entry on an earlier day is hidden unless `showsCompleted` is on.
- **Search (§7):** substring, case- and diacritic-insensitive, over the entry text.
- **Composition:** search and tag filter compose (both must match).
- **Order:** days descending; within a day, the store's order (ascending).
- **Tag counts:** computed after the completed-visibility and search filters but *before* the tag
  filter — otherwise selecting a tag would zero every other chip and there would be no way back.
- **Top tags (§6):** the three most frequent over entries from the last 30 days, ties broken
  alphabetically so the `⌘1`–`⌘3` bindings do not shuffle between launches.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/NotesModelTests.swift`:

```swift
import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func makeModel(
    _ seeded: [(day: CalendarDay, text: String, isDone: Bool)] = [],
    today: CalendarDay = day29
) -> (NotesModel, InMemoryNotesRepository, PendingQueue) {
    let repository = InMemoryNotesRepository(entries: seeded)
    let suite = "dnotes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let pending = PendingQueue(defaults: defaults)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = today.startOfDay(in: calendar)!.addingTimeInterval(12 * 3600)
    let model = NotesModel(repository: repository, pending: pending,
                           calendar: calendar, now: { now })
    return (model, repository, pending)
}

@Test @MainActor func loadsEntriesReverseChronologically() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "morning", isDone: false),
        (day: day29, text: "afternoon", isDone: false),
        (day: day30, text: "next day", isDone: false),
    ], today: day30)
    await model.load()

    // Days descending, file order within a day.
    #expect(model.visibleEntries.map(\.text) == ["next day", "morning", "afternoon"])
}

@Test @MainActor func addsToToday() async {
    let (model, repository, _) = makeModel(today: day30)
    await model.load()

    await model.add("captured now")

    #expect(repository.entries.map(\.day) == [day30])
    #expect(model.visibleEntries.map(\.text) == ["captured now"])
    #expect(model.lastError == nil)
}

@Test @MainActor func togglingAnEntryWritesThrough() async {
    let (model, repository, _) = makeModel([(day: day29, text: "task", isDone: false)])
    await model.load()

    await model.toggle(model.visibleEntries[0])

    #expect(repository.entries.map(\.isDone) == [true])
}

@Test @MainActor func editingAndDeletingWriteThrough() async {
    let (model, repository, _) = makeModel([(day: day29, text: "old", isDone: false)])
    await model.load()

    await model.edit(model.visibleEntries[0], to: "new")
    #expect(repository.entries.map(\.text) == ["new"])

    await model.delete(model.visibleEntries[0])
    #expect(repository.entries.isEmpty)
}

// MARK: - completed visibility (§7)

@Test @MainActor func anEntryCompletedTodayStaysVisible() async {
    let (model, _, _) = makeModel([(day: day29, text: "done today", isDone: true)], today: day29)
    await model.load()

    #expect(model.visibleEntries.map(\.text) == ["done today"])
}

@Test @MainActor func anEntryCompletedOnAnEarlierDayIsHidden() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "done yesterday", isDone: true),
        (day: day30, text: "still open", isDone: false),
    ], today: day30)
    await model.load()

    #expect(model.visibleEntries.map(\.text) == ["still open"])
}

@Test @MainActor func showsCompletedBringsTheOldOnesBack() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "done yesterday", isDone: true),
        (day: day30, text: "still open", isDone: false),
    ], today: day30)
    await model.load()
    model.showsCompleted = true

    #expect(model.visibleEntries.map(\.text) == ["still open", "done yesterday"])
}

// MARK: - search and tags

@Test @MainActor func searchIsCaseAndDiacriticInsensitive() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "Émile Zola", isDone: false),
        (day: day29, text: "Nothing to see", isDone: false),
        (day: day29, text: "CAFÉ notes", isDone: false),
    ])
    await model.load()

    model.searchText = "émile"
    #expect(model.visibleEntries.map(\.text) == ["Émile Zola"])

    model.searchText = "cafe"
    #expect(model.visibleEntries.map(\.text) == ["CAFÉ notes"])
}

@Test @MainActor func aHiddenCompletedEntryIsStillFindableBySearch() async {
    // §7: from the next day it is hidden and reachable via the toggle or search.
    let (model, _, _) = makeModel([
        (day: day29, text: "done yesterday", isDone: true),
    ], today: day30)
    await model.load()

    model.searchText = "yesterday"
    #expect(model.visibleEntries.map(\.text) == ["done yesterday"])
}

@Test @MainActor func tagFilterAndSearchCompose() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "ship the parser #oss", isDone: false),
        (day: day29, text: "ship the metrics #infra", isDone: false),
        (day: day29, text: "read about #oss licensing", isDone: false),
    ])
    await model.load()

    model.selectedTag = "oss"
    #expect(model.visibleEntries.count == 2)

    model.searchText = "ship"
    #expect(model.visibleEntries.map(\.text) == ["ship the parser #oss"])
}

@Test @MainActor func tagCountsIgnoreTheTagFilterButNotTheSearch() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "a #oss", isDone: false),
        (day: day29, text: "b #oss", isDone: false),
        (day: day29, text: "c #infra", isDone: false),
    ])
    await model.load()

    model.selectedTag = "oss"
    #expect(model.tagCounts == [TagCount(tag: "oss", count: 2), TagCount(tag: "infra", count: 1)])

    model.searchText = "a"
    #expect(model.tagCounts == [TagCount(tag: "oss", count: 1)])
}

@Test @MainActor func topTagsAreTheThreeMostFrequentOfTheLastThirtyDays() async {
    let old = CalendarDay(iso: "2026-05-01")!   // well outside the 30-day window
    let (model, _, _) = makeModel([
        (day: day29, text: "1 #infra", isDone: false),
        (day: day29, text: "2 #infra", isDone: false),
        (day: day29, text: "3 #infra", isDone: false),
        (day: day29, text: "4 #oss", isDone: false),
        (day: day29, text: "5 #oss", isDone: false),
        (day: day29, text: "6 #plan", isDone: false),
        (day: day29, text: "7 #rare", isDone: false),
        (day: old, text: "8 #ancient", isDone: false),
        (day: old, text: "9 #ancient", isDone: false),
        (day: old, text: "10 #ancient", isDone: false),
        (day: old, text: "11 #ancient", isDone: false),
    ], today: day29)
    await model.load()

    #expect(model.topTags == ["infra", "oss", "plan"])
}

@Test @MainActor func topTagsBreakTiesAlphabeticallySoTheyDoNotShuffle() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "a #zebra", isDone: false),
        (day: day29, text: "b #alpha", isDone: false),
        (day: day29, text: "c #middle", isDone: false),
    ])
    await model.load()

    #expect(model.topTags == ["alpha", "middle", "zebra"])
}

// MARK: - the §8 error paths

@Test @MainActor func aFailedCaptureGoesToThePendingQueueAndIsNotLost() async {
    let (model, repository, pending) = makeModel(today: day30)
    await model.load()
    repository.nextWriteError = .writeFailed("no space")

    await model.add("must not be lost")

    #expect(repository.entries.isEmpty)
    #expect(pending.entries.map(\.text) == ["must not be lost"])
    #expect(model.pendingCount == 1)
    #expect(model.lastError != nil)
}

@Test @MainActor func threeFailedCapturesAreThreeQueuedEntries() async {
    let (model, repository, pending) = makeModel()
    await model.load()
    repository.isAvailable = false

    await model.add("one")
    await model.add("two")
    await model.add("three")

    #expect(pending.entries.map(\.text) == ["one", "two", "three"])
    #expect(model.storeAvailable == false)
}

@Test @MainActor func drainingAppendsEachEntryToItsOwnDay() async {
    let (model, repository, pending) = makeModel(today: day30)
    await model.load()
    repository.isAvailable = false
    await model.add("captured yesterday")

    // A day passes and the store comes back.
    let (later, _, _) = makeModel(today: day01)
    _ = later
    repository.isAvailable = true
    await model.drainPending()

    #expect(repository.entries.map(\.text) == ["captured yesterday"])
    #expect(repository.entries.map(\.day) == [day30])   // its own day, not today
    #expect(pending.isEmpty)
}

@Test @MainActor func drainingStopsAtTheFirstFailureAndKeepsTheRest() async {
    let (model, repository, pending) = makeModel()
    await model.load()
    repository.isAvailable = false
    await model.add("one")
    await model.add("two")

    repository.isAvailable = true
    repository.nextWriteError = .writeFailed("still failing")
    await model.drainPending()

    #expect(repository.entries.isEmpty)
    #expect(pending.entries.map(\.text) == ["one", "two"])

    await model.drainPending()
    #expect(repository.entries.map(\.text) == ["one", "two"])
    #expect(pending.isEmpty)
}

@Test @MainActor func loadDrainsWhatIsWaiting() async {
    let (model, repository, pending) = makeModel()
    await model.load()
    repository.isAvailable = false
    await model.add("queued")
    repository.isAvailable = true

    await model.load()

    #expect(repository.entries.map(\.text) == ["queued"])
    #expect(pending.isEmpty)
}

@Test @MainActor func anExternalChangeRefreshesTheModel() async {
    let (model, repository, _) = makeModel()
    await model.load()

    try? await repository.append(text: "added behind our back", on: day29)
    repository.onExternalChange?()

    #expect(model.entries.map(\.text) == ["added behind our back"])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter NotesModel`
Expected: FAIL, `cannot find 'NotesModel' in scope`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/NotesModel.swift`:

```swift
import Foundation
import Observation

public struct TagCount: Hashable, Sendable {
    public let tag: String
    public let count: Int

    public init(tag: String, count: Int) {
        self.tag = tag
        self.count = count
    }
}

/// UI state. Knows the storage seam and nothing below it — no folders, no files, no
/// line numbers. Every view reads this.
@MainActor
@Observable
public final class NotesModel {
    public var searchText: String = ""
    public var selectedTag: String?
    public var showsCompleted: Bool = false

    public private(set) var entries: [NoteEntry] = []
    public private(set) var storeAvailable: Bool = true
    public private(set) var lastError: String?

    private let repository: any NotesRepository
    private let pending: PendingQueue
    private let calendar: Calendar
    private let now: () -> Date

    public init(repository: any NotesRepository,
                pending: PendingQueue,
                calendar: Calendar = .current,
                now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.pending = pending
        self.calendar = calendar
        self.now = now
        repository.onExternalChange = { [weak self] in self?.refresh() }
    }

    public var today: CalendarDay { CalendarDay.today(now: now(), calendar: calendar) }
    public var pendingCount: Int { pending.entries.count }

    // MARK: - reading

    public func load() async {
        do {
            try await repository.load()
            lastError = nil
        } catch {
            record(error)
        }
        refresh()
        await drainPending()
    }

    private func refresh() {
        entries = repository.entries
        storeAvailable = repository.isAvailable
    }

    /// Days descending, the store's own order within a day (§7).
    public var visibleEntries: [NoteEntry] {
        let filtered = entries.filter(matchesTag)
        var byDay: [CalendarDay: [NoteEntry]] = [:]
        for entry in filtered { byDay[entry.day, default: []].append(entry) }
        return byDay.keys.sorted(by: >).flatMap { byDay[$0] ?? [] }
    }

    /// Counted before the tag filter is applied, or selecting a tag would zero every
    /// other chip and leave no way back.
    public var tagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        for entry in entries where matchesVisibility(entry) && matchesSearch(entry) {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.tag) < ($0.count, $1.tag) }
    }

    /// The three most frequent tags of the last 30 days (§6), ties broken
    /// alphabetically so the ⌘1–⌘3 bindings do not shuffle between launches.
    public var topTags: [String] {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now()) else { return [] }
        let cutoffDay = CalendarDay.today(now: cutoff, calendar: calendar)

        var counts: [String: Int] = [:]
        for entry in entries where entry.day >= cutoffDay {
            for tag in entry.tags { counts[tag, default: 0] += 1 }
        }
        return counts
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(3)
            .map(\.key)
    }

    // MARK: - writing

    public func add(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let day = today
        do {
            try await repository.append(text: trimmed, on: day)
            lastError = nil
        } catch {
            // Confirmed with ⏎, so it is never dropped — it waits instead (§8).
            pending.enqueue(text: trimmed, day: day, createdAt: now())
            record(error)
        }
        refresh()
    }

    public func toggle(_ entry: NoteEntry) async {
        await write { try await self.repository.setDone(!entry.isDone, for: entry) }
    }

    public func edit(_ entry: NoteEntry, to newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.text else { return }
        await write { try await self.repository.edit(entry, to: trimmed) }
    }

    public func delete(_ entry: NoteEntry) async {
        await write { try await self.repository.delete(entry) }
    }

    /// Drains in insertion order, stopping at the first failure so the queue keeps
    /// its order and nothing is dropped on the way (§8).
    public func drainPending() async {
        guard !pending.isEmpty, repository.isAvailable else { return }
        for waiting in pending.entries {
            do {
                try await repository.append(text: waiting.text, on: waiting.day)
                pending.remove(id: waiting.id)
            } catch {
                record(error)
                break
            }
        }
        refresh()
    }

    // Takes no parameter: passing `any NotesRepository` into the closure trips Swift 6
    // strict concurrency ("sending self.repository risks causing data races").
    private func write(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastError = nil
        } catch {
            record(error)
        }
        refresh()
    }

    private func record(_ error: Error) {
        lastError = Self.message(for: error)
    }

    static func message(for error: Error) -> String {
        guard let error = error as? NotesError else { return error.localizedDescription }
        switch error {
        case .storeUnavailable(let where_):
            return "Notes folder is not available: \(where_)"
        case .entryVanished:
            return "That line is no longer there — nothing was changed."
        case .ambiguousMatch:
            return "The file changed and the line could not be identified — nothing was changed."
        case .writeFailed(let reason):
            return "Could not write: \(reason)"
        }
    }

    // MARK: - filters

    private func matchesTag(_ entry: NoteEntry) -> Bool {
        guard matchesVisibility(entry), matchesSearch(entry) else { return false }
        guard let selectedTag else { return true }
        return entry.tags.contains(selectedTag)
    }

    /// An entry completed today stays visible until the end of the day; from the next
    /// day it is hidden and reachable via the toggle or search (§7).
    private func matchesVisibility(_ entry: NoteEntry) -> Bool {
        guard entry.isDone else { return true }
        if showsCompleted { return true }
        if !searchText.isEmpty { return true }
        return entry.day == today
    }

    private func matchesSearch(_ entry: NoteEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return entry.text.range(of: searchText,
                                options: [.caseInsensitive, .diacriticInsensitive],
                                locale: .current) != nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter NotesModel`
Expected: PASS.

- [ ] **Step 5: Run the whole suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/DnotesCore/NotesModel.swift Tests/DnotesCoreTests/NotesModelTests.swift
git commit -m "feat: NotesModel — search, tag filter, completed visibility, pending drain

Runs entirely against the storage protocol: its tests use the in-memory
backend, which is what keeps views from growing a dependency on files."
```
