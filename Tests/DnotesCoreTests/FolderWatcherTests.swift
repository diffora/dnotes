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
