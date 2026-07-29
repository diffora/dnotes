import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func makeModel(
    _ seeded: [(day: CalendarDay, text: String, isDone: Bool)] = [],
    today: CalendarDay = day29
) -> (NotesModel, InMemoryNotesRepository, PendingQueue) {
    let repository = InMemoryNotesRepository(entries: seeded)
    let pending = PendingQueue(defaults: makeTestDefaults())
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

@Test @MainActor func blankCapturesAreIgnored() async {
    let (model, repository, _) = makeModel()
    await model.load()

    await model.add("   \n ")

    #expect(repository.entries.isEmpty)
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

@Test @MainActor func theAllFilterBringsTheOldOnesBack() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "done yesterday", isDone: true),
        (day: day30, text: "still open", isDone: false),
    ], today: day30)
    await model.load()
    model.completionFilter = .all

    #expect(model.visibleEntries.map(\.text) == ["still open", "done yesterday"])
}

@Test @MainActor func theOpenOnlyFilterHidesEvenTodaysCompleted() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "done today", isDone: true),
        (day: day29, text: "still open", isDone: false),
    ], today: day29)
    await model.load()
    model.completionFilter = .openOnly

    #expect(model.visibleEntries.map(\.text) == ["still open"])
}

@Test @MainActor func openOnlyIsNotOverriddenBySearch() async {
    // The `.completedToday` default lets search reach hidden completed entries (§7).
    // An explicit "open only" must not: a completed hit would read as a broken filter.
    let (model, _, _) = makeModel([
        (day: day29, text: "done today", isDone: true),
    ], today: day29)
    await model.load()
    model.completionFilter = .openOnly
    model.searchText = "done"

    #expect(model.visibleEntries.isEmpty)
}

@Test @MainActor func theOpenOnlyFilterAlsoNarrowsTheTagChips() async {
    let (model, _, _) = makeModel([
        (day: day29, text: "a #oss", isDone: true),
        (day: day29, text: "b #oss", isDone: false),
    ], today: day29)
    await model.load()
    model.completionFilter = .openOnly

    #expect(model.tagCounts == [TagCount(tag: "oss", count: 1)])
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

    // "b" and not "a": the tag `infra` contains an "a", which would match too.
    model.searchText = "b"
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
    // "Today" is fixed at day30, so an entry captured while the store was gone must
    // still land on day30 even though it is drained later.
    let (model, repository, pending) = makeModel(today: day30)
    await model.load()
    repository.isAvailable = false
    await model.add("captured while offline")

    repository.isAvailable = true
    await model.drainPending()

    #expect(repository.entries.map(\.text) == ["captured while offline"])
    #expect(repository.entries.map(\.day) == [day30])
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
