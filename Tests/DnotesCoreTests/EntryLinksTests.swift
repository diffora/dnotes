import Foundation
import Testing
@testable import DnotesCore

private let jira = "https://jira.example.com/browse/{key}"

private func urls(_ text: String, template: String = "") -> [String] {
    EntryLinks.spans(in: text, issueURLTemplate: template).map(\.url.absoluteString)
}

private func linked(_ text: String, template: String = "") -> [String] {
    EntryLinks.spans(in: text, issueURLTemplate: template).map { String(text[$0.range]) }
}

@Test func findsAPlainURL() {
    #expect(urls("see https://example.com/page for details") == ["https://example.com/page"])
    #expect(linked("see https://example.com/page for details") == ["https://example.com/page"])
}

@Test func findsSeveralURLsInOrder() {
    let text = "https://a.example.com and https://b.example.com"
    #expect(urls(text) == ["https://a.example.com", "https://b.example.com"])
}

@Test func aURLWithAnAnchorIsOneLinkAndNotATag() {
    // The same string TagScanner refuses to read as a tag (§4.1).
    let text = "https://example.com/page#anchor"
    #expect(urls(text) == ["https://example.com/page#anchor"])
    #expect(TagScanner.tags(in: text).isEmpty)
}

@Test func textWithoutReferencesHasNoLinks() {
    #expect(urls("open source editor plugin #oss").isEmpty)
}

// MARK: - issue keys

@Test func findsAnIssueKeyWhenATemplateIsGiven() {
    let text = "single node metrics — ABC-1234 #infra"
    #expect(linked(text, template: jira) == ["ABC-1234"])
    #expect(urls(text, template: jira) == ["https://jira.example.com/browse/ABC-1234"])
}

@Test func issueKeysStayPlainTextWithoutATemplate() {
    // Better plain than pointed at a guessed host.
    #expect(urls("ABC-1234 needs a look").isEmpty)
}

@Test func aTemplateWithoutThePlaceholderIsIgnored() {
    #expect(urls("ABC-1234", template: "https://jira.example.com/browse/").isEmpty)
}

@Test(arguments: [
    "well-known problem",      // lowercase, not a key
    "the 2026-07-29 heading",  // a date
    "A-1",                     // one letter is too loose to be a key
    "sha-1 hashing",
])
func ordinaryHyphenatedTextIsNotAnIssueKey(_ text: String) {
    #expect(urls(text, template: jira).isEmpty)
}

@Test func anIssueKeyInsideAURLIsNotLinkedTwice() {
    let text = "https://jira.example.com/browse/ABC-1234"
    let spans = EntryLinks.spans(in: text, issueURLTemplate: jira)
    #expect(spans.count == 1)
    #expect(spans[0].url.absoluteString == text)
}

@Test func urlsAndIssueKeysComeBackInReadingOrder() {
    let text = "ABC-1 then https://example.com then ABC-2"
    #expect(linked(text, template: jira) == ["ABC-1", "https://example.com", "ABC-2"])
}
