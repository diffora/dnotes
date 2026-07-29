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
