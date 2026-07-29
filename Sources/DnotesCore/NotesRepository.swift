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
