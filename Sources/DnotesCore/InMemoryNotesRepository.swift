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
            records.append(Record(id: mintID(), day: entry.day, text: entry.text,
                                  isDone: entry.isDone))
        }
    }

    public var entries: [NoteEntry] {
        records.enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map { NoteEntry(id: $0.element.id, day: $0.element.day, text: $0.element.text,
                             isDone: $0.element.isDone,
                             tags: TagScanner.tags(in: $0.element.text)) }
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
