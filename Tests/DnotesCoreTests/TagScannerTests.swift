import Testing
@testable import DnotesCore

@Test(arguments: [
    ("#oss at the start", ["oss"]),
    ("in the #middle of it", ["middle"]),
    ("at the end #infra", ["infra"]),
    ("two #oss and #infra tags", ["oss", "infra"]),
    ("an accented #étiquette works", ["étiquette"]),
    ("#infra-api and #infra_api", ["infra-api", "infra_api"]),
    ("digits #v2 count", ["v2"]),
    ("no tags here", []),
    ("bare # is not a tag", []),
    ("#", []),
])
func findsTags(_ text: String, _ expected: [String]) {
    #expect(TagScanner.tags(in: text) == expected)
}

@Test(arguments: [
    ("(#infra) parenthesised", ["infra"]),
    ("[#infra] bracketed", ["infra"]),
    ("{#infra} braced", ["infra"]),
    ("«#infra» quoted", ["infra"]),
    ("\"#infra\" quoted", ["infra"]),
])
func openingCharactersStillOpenATag(_ text: String, _ expected: [String]) {
    #expect(TagScanner.tags(in: text) == expected)
}

@Test(arguments: [
    "https://example.com/page#anchor",
    "word#notatag",
    "v2#notatag",
])
func aHashAfterALetterDigitOrSlashIsNotATag(_ text: String) {
    #expect(TagScanner.tags(in: text).isEmpty)
}

@Test(arguments: [
    ("#infra, and more", ["infra"]),
    ("#infra. end", ["infra"]),
    ("#infra)", ["infra"]),
    ("#infra: note", ["infra"]),
])
func punctuationEndsTheTagBody(_ text: String, _ expected: [String]) {
    #expect(TagScanner.tags(in: text) == expected)
}

@Test func repeatedTagsAreReportedOnce() {
    #expect(TagScanner.tags(in: "#oss and again #oss") == ["oss"])
}

@Test func caseIsPreservedAndNotFolded() {
    #expect(TagScanner.tags(in: "#OSS and #oss") == ["OSS", "oss"])
}

// MARK: - spans

@Test func spansCoverTheHashAsWellAsTheBody() {
    let text = "bugs for hotfix #hotfixes - 7.4-hf2"
    let spans = TagScanner.spans(in: text)
    #expect(spans.count == 1)
    #expect(String(text[spans[0].range]) == "#hotfixes")
    #expect(spans[0].tag == "hotfixes")
}

@Test func spansKeepDuplicatesThatTagsFolds() {
    let text = "#oss and again #oss"
    #expect(TagScanner.spans(in: text).map(\.tag) == ["oss", "oss"])
    #expect(TagScanner.tags(in: text) == ["oss"])
}

@Test func spansLandOnTheRightCharactersWithSeveralTags() {
    let text = "#a middle #b end #c"
    let spans = TagScanner.spans(in: text)
    #expect(spans.map { String(text[$0.range]) } == ["#a", "#b", "#c"])
}

@Test func spansSkipWhatIsNotATag() {
    #expect(TagScanner.spans(in: "https://example.com/page#anchor").isEmpty)
    #expect(TagScanner.spans(in: "bare # is not a tag").isEmpty)
}

@Test func spansHandleNonASCIIWidth() {
    // A range over a string with multi-byte characters before the tag has to still
    // point at the tag — this is what breaks when ranges are built from byte offsets.
    let text = "привет мир #daily"
    let spans = TagScanner.spans(in: text)
    #expect(spans.count == 1)
    #expect(String(text[spans[0].range]) == "#daily")
}

// MARK: - stripping, for the trailing-chip layout

@Test(arguments: [
    ("bugs for hotfix #hotfixes - 7.4-hf2", "bugs for hotfix - 7.4-hf2"),
    ("#minotoring presenation", "presenation"),
    ("review SPI #review", "review SPI"),
    ("two #oss and #infra tags", "two and tags"),
    ("no tags here", "no tags here"),
    ("(#infra) parenthesised", "() parenthesised"),
])
func strippingRemovesTagsAndClosesTheGap(_ text: String, _ expected: String) {
    #expect(TagScanner.stripping(text) == expected)
}

/// The case that would otherwise render a blank row. The scanner reports it honestly and
/// leaves the decision to the view, which falls back to the inline layout.
@Test(arguments: ["#daily", "#daily #oss", "  #daily  "])
func aLineOfNothingButTagsStripsToNothing(_ text: String) {
    #expect(TagScanner.stripping(text).isEmpty)
}

@Test func strippingLeavesDeliberateSpacingInTheRemainingText() {
    // The double space here is the author's, not a hole left by a removal.
    #expect(TagScanner.stripping("code:  indented #oss") == "code:  indented")
}

@Test func strippingDoesNotTouchAHashThatIsNotATag() {
    #expect(TagScanner.stripping("https://example.com/page#anchor")
            == "https://example.com/page#anchor")
    #expect(TagScanner.stripping("bare # stays") == "bare # stays")
}

@Test func parsedEntriesCarryTheirTags() {
    guard case .entry(let entry) = Document.parse("- ship it #oss #infra\n").lines[0].kind else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.tags == ["oss", "infra"])
    // The tag stays part of the line's text — there are no hidden fields (§6).
    #expect(entry.text == "ship it #oss #infra")
}
