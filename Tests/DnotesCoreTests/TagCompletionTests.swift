import Testing
@testable import DnotesCore

private let available = [
    TagCount(tag: "deploy", count: 12),
    TagCount(tag: "oss", count: 7),
    TagCount(tag: "design", count: 3),
]

@Test @MainActor func staysClosedUntilAHashIsTyped() {
    let completion = TagCompletionModel()
    completion.update(text: "just a thought", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func opensOnAHashAndOffersEverything() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #", available: available)

    #expect(completion.isActive)
    #expect(completion.suggestions.map(\.tag) == ["deploy", "oss", "design"])
    #expect(completion.newTagName == nil)   // nothing typed yet, nothing to create
}

@Test @MainActor func narrowsAsThePrefixGrows() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #de", available: available)

    #expect(completion.suggestions.map(\.tag) == ["deploy", "design"])
}

@Test @MainActor func offersToCreateATagThatDoesNotExist() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #brandnew", available: available)

    #expect(completion.suggestions.isEmpty)
    #expect(completion.newTagName == "brandnew")
}

@Test @MainActor func closesWhenTheTagIsFinishedWithASpace() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #oss and more", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func onlyTheTagBeingTypedCounts() {
    let completion = TagCompletionModel()
    completion.update(text: "#oss then #de", available: available)
    #expect(completion.suggestions.map(\.tag) == ["deploy", "design"])
}

@Test @MainActor func aUrlAnchorDoesNotOpenCompletion() {
    let completion = TagCompletionModel()
    completion.update(text: "see https://example.com/page#anchor", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func selectionMovesAndClamps() {
    let completion = TagCompletionModel()
    // Two matches plus the "create #de" item, because `de` is a prefix of existing
    // tags but is not itself one yet.
    completion.update(text: "#de", available: available)
    #expect(completion.suggestions.count == 2)
    #expect(completion.newTagName == "de")

    #expect(completion.selectedIndex == 0)
    completion.moveSelection(by: 1)
    #expect(completion.selectedIndex == 1)
    completion.moveSelection(by: 5)
    #expect(completion.selectedIndex == 2)   // clamped to the create item, not wrapped
    completion.moveSelection(by: -9)
    #expect(completion.selectedIndex == 0)
}

@Test @MainActor func completingReplacesThePartialTag() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #de", available: available)

    #expect(completion.complete(in: "ship it #de") == "ship it #deploy ")
}

@Test @MainActor func completingANewTagKeepsWhatWasTyped() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #brandnew", available: available)

    #expect(completion.complete(in: "ship it #brandnew") == "ship it #brandnew ")
}

@Test @MainActor func appendingATagAddsItAtTheEnd() {
    #expect(TagCompletionModel.appending("oss", to: "ship the parser") == "ship the parser #oss")
    #expect(TagCompletionModel.appending("oss", to: "ship the parser ") == "ship the parser #oss")
    #expect(TagCompletionModel.appending("oss", to: "") == "#oss")
}

@Test @MainActor func appendingATagAlreadyPresentChangesNothing() {
    #expect(TagCompletionModel.appending("oss", to: "already #oss here") == "already #oss here")
}
