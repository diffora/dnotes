import Foundation
import Testing
@testable import DnotesCore

@MainActor
func makeTestDefaults() -> UserDefaults {
    let suite = "dnotes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test @MainActor func enqueuesInInsertionOrder() {
    let queue = PendingQueue(defaults: makeTestDefaults())
    queue.enqueue(text: "first", day: day29, createdAt: Date(timeIntervalSince1970: 1))
    queue.enqueue(text: "second", day: day29, createdAt: Date(timeIntervalSince1970: 2))
    queue.enqueue(text: "third", day: day30, createdAt: Date(timeIntervalSince1970: 3))

    #expect(queue.entries.map(\.text) == ["first", "second", "third"])
    #expect(queue.entries.map(\.day) == [day29, day29, day30])
    #expect(!queue.isEmpty)
}

@Test @MainActor func survivesARestart() {
    let defaults = makeTestDefaults()
    let first = PendingQueue(defaults: defaults)
    first.enqueue(text: "written with the folder gone", day: day29, createdAt: Date())

    // A new instance over the same defaults is what a relaunch looks like.
    let second = PendingQueue(defaults: defaults)
    #expect(second.entries.map(\.text) == ["written with the folder gone"])
}

@Test @MainActor func removesByIdentity() {
    let queue = PendingQueue(defaults: makeTestDefaults())
    queue.enqueue(text: "a", day: day29, createdAt: Date())
    queue.enqueue(text: "b", day: day29, createdAt: Date())
    let first = queue.entries[0]

    queue.remove(id: first.id)

    #expect(queue.entries.map(\.text) == ["b"])
}

@Test @MainActor func removingSomethingAlreadyGoneIsHarmless() {
    let queue = PendingQueue(defaults: makeTestDefaults())
    queue.remove(id: UUID())
    #expect(queue.isEmpty)
}

@Test @MainActor func identicalTextsAreSeparateEntries() {
    // Three captures of the same thought are three entries, not one.
    let queue = PendingQueue(defaults: makeTestDefaults())
    queue.enqueue(text: "same", day: day29, createdAt: Date())
    queue.enqueue(text: "same", day: day29, createdAt: Date())

    #expect(queue.entries.count == 2)
    #expect(queue.entries[0].id != queue.entries[1].id)
}

@Test @MainActor func corruptStoredDataIsIgnoredRatherThanCrashing() {
    let defaults = makeTestDefaults()
    defaults.set(Data("not json".utf8), forKey: "dnotes.pendingQueue")

    #expect(PendingQueue(defaults: defaults).isEmpty)
}
