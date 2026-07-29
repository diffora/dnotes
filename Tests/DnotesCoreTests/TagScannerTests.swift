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

@Test func parsedEntriesCarryTheirTags() {
    guard case .entry(let entry) = Document.parse("- ship it #oss #infra\n").lines[0].kind else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.tags == ["oss", "infra"])
    // The tag stays part of the line's text — there are no hidden fields (§6).
    #expect(entry.text == "ship it #oss #infra")
}
