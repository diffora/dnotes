import Foundation
import Observation

/// Which completed entries the list shows (§7).
public enum CompletionFilter: String, CaseIterable, Codable, Sendable {
    /// The §7 default: open entries, plus the ones completed today, struck through.
    case completedToday
    /// Only what is still open. Asked for so a day's remaining work reads at a glance.
    case openOnly
    /// Everything, however old.
    case all

    public var title: String {
        switch self {
        case .openOnly: return "Open only"
        case .completedToday: return "Open + done today"
        case .all: return "Everything"
        }
    }
}

/// Where a row draws its tags. A layout preference, not a change to the note: the line
/// in the file is identical either way (§4.1).
public enum TagLayout: String, CaseIterable, Codable, Sendable {
    /// The tag stays where it was typed, coloured in place. What the row shows is exactly
    /// what the file holds, so editing changes nothing about the text's shape.
    case inline
    /// The default: tags move to chips at the end of the row and the text reads without
    /// them. The trade is visible on edit — the field opens on the *stored* line, tags and
    /// all, so the text changes shape under the cursor. It is also the layout a line of
    /// nothing but tags cannot be drawn in; `EntryRowView` falls back to `inline` there.
    case trailing

    public var title: String {
        switch self {
        case .inline: return "In the text"
        case .trailing: return "At the end of the row"
        }
    }
}

/// One reversible change, described by what it takes to put things back.
///
/// Steps name their target by day and text rather than by `EntryID`, because ids are
/// recomputed on every read (§4.1) and every write reloads: a step recorded before a
/// write cannot trust an id afterwards. With duplicate lines in a day the first match
/// wins, which is the honest limit of undoing by content.
enum UndoStep: Equatable, Sendable {
    /// Undo of a capture.
    case removeMatching(text: String, day: CalendarDay)
    /// Undo of a delete. Re-appends at the end of its day — the original position
    /// within the day is gone from the file along with the line, so it cannot be
    /// restored. Recovering the text matters; recovering its neighbours' order does not.
    case restore(text: String, day: CalendarDay)
    /// Undo of a completion or a reopen.
    case setDone(Bool, text: String, day: CalendarDay)
    /// Undo of an edit: find the new text, put the old text back.
    case replaceText(from: String, to: String, day: CalendarDay)
}

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
    public var completionFilter: CompletionFilter = .completedToday

    public private(set) var entries: [NoteEntry] = []
    public private(set) var storeAvailable: Bool = true
    public private(set) var lastError: String?

    /// Bounded: an undo stack is a safety net for a slip, not a version history.
    private static let undoLimit = 50
    private var undoStack: [UndoStep] = []
    private var isUndoing = false

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
    public var canUndo: Bool { !undoStack.isEmpty }

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

    /// Every tag in the store, sorted, regardless of any filter.
    ///
    /// Unfiltered on purpose: this is what colours are assigned from, and a tag that is
    /// merely hidden by the current filter must not be treated as new — it would take a
    /// colour already given to something else the moment the filter changed.
    public var allTags: [String] {
        Set(entries.flatMap(\.tags)).sorted()
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
            record(.removeMatching(text: trimmed, day: day))
            lastError = nil
        } catch {
            // Confirmed with ⏎, so it is never dropped — it waits instead (§8).
            pending.enqueue(text: trimmed, day: day, createdAt: now())
            record(error)
        }
        refresh()
    }

    public func toggle(_ entry: NoteEntry) async {
        await write(undo: .setDone(entry.isDone, text: entry.text, day: entry.day)) {
            try await self.repository.setDone(!entry.isDone, for: entry)
        }
    }

    public func edit(_ entry: NoteEntry, to newText: String) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.text else { return }
        await write(undo: .replaceText(from: trimmed, to: entry.text, day: entry.day)) {
            try await self.repository.edit(entry, to: trimmed)
        }
    }

    public func delete(_ entry: NoteEntry) async {
        await write(undo: .restore(text: entry.text, day: entry.day)) {
            try await self.repository.delete(entry)
        }
    }

    /// Reverses the most recent change. There is no redo: the point is rescuing a slip,
    /// and a slip is rarely worth repeating.
    public func undo() async {
        guard let step = undoStack.popLast() else { return }
        isUndoing = true
        defer { isUndoing = false }

        switch step {
        case .removeMatching(let text, let day):
            guard let entry = entry(text: text, on: day) else { break }
            await delete(entry)
        case .restore(let text, let day):
            await append(text, on: day)
        case .setDone(let done, let text, let day):
            guard let entry = entry(text: text, on: day), entry.isDone != done else { break }
            await toggle(entry)
        case .replaceText(let from, let to, let day):
            guard let entry = entry(text: from, on: day) else { break }
            await edit(entry, to: to)
        }
    }

    /// Appends to a specific day rather than to today, which is what restoring a
    /// deleted line and draining the queue both need.
    private func append(_ text: String, on day: CalendarDay) async {
        do {
            try await repository.append(text: text, on: day)
            lastError = nil
        } catch {
            pending.enqueue(text: text, day: day, createdAt: now())
            record(error)
        }
        refresh()
    }

    private func entry(text: String, on day: CalendarDay) -> NoteEntry? {
        entries.first { $0.day == day && $0.text == text }
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

    private func write(undo step: UndoStep, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            record(step)
            lastError = nil
        } catch {
            record(error)
        }
        refresh()
    }

    /// Nothing recorded while undoing, or ⌘Z would toggle between two states forever.
    private func record(_ step: UndoStep) {
        guard !isUndoing else { return }
        undoStack.append(step)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
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
    /// day it is hidden and reachable via the filter or search (§7).
    ///
    /// Search deliberately un-hides completed entries in `.completedToday` — that is
    /// what §7 means by "reachable via search" — but *not* in `.openOnly`: someone who
    /// asked for open entries only would read a completed search hit as the filter
    /// being broken.
    private func matchesVisibility(_ entry: NoteEntry) -> Bool {
        guard entry.isDone else { return true }
        switch completionFilter {
        case .all:
            return true
        case .openOnly:
            return false
        case .completedToday:
            return !searchText.isEmpty || entry.day == today
        }
    }

    private func matchesSearch(_ entry: NoteEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return entry.text.range(of: searchText,
                                options: [.caseInsensitive, .diacriticInsensitive],
                                locale: .current) != nil
    }
}
