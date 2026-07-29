import Testing
@testable import DnotesCore

private func kinds(_ text: String) -> [LineKind] {
    Document.parse(text).lines.map(\.kind)
}

@Test func recognisesADayHeading() {
    #expect(kinds("## 2026-07-29\n") == [.dayHeading(CalendarDay(iso: "2026-07-29")!)])
}

@Test(arguments: [
    "### 2026-07-29",       // wrong level
    "#  2026-07-29",        // one hash
    "## 2026-07-29 Monday", // trailing text
    "## 2026-7-29",         // unpadded
    "##2026-07-29",         // no space
])
func rejectsNonHeadings(_ line: String) {
    #expect(kinds(line + "\n") == [.other])
}

@Test func recognisesTheThreeEntryForms() {
    let text = "- plain\n- [ ] unchecked\n- [x] checked\n"
    let entries = Document.parse(text).lines.compactMap { line -> Entry? in
        guard case .entry(let entry) = line.kind else { return nil }
        return entry
    }
    #expect(entries.map(\.text) == ["plain", "unchecked", "checked"])
    #expect(entries.map(\.isDone) == [false, false, true])
}

@Test func acceptsCapitalXForCompatibility() {
    guard case .entry(let entry) = kinds("- [X] done\n")[0] else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.isDone)
    #expect(entry.text == "done")
}

@Test func toleratesWhitespaceAfterTheDash() {
    guard case .entry(let entry) = kinds("-   spaced\n")[0] else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.text == "spaced")
}

@Test(arguments: [
    "-no space after dash",
    "* asterisk bullet",
    "- ",           // an entry with no text is nothing to show
    "- [x]",
    "  plain text",
])
func rejectsNonEntries(_ line: String) {
    #expect(kinds(line + "\n") == [.other])
}

@Test func keepsIndentedEntriesButDoesNotNestThem() {
    // Nesting is a non-goal (§3): the indent is preserved in `raw` and ignored otherwise.
    guard case .entry(let entry) = kinds("  - indented\n")[0] else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.text == "indented")
}

@Test func dominantEndingFollowsTheMajority() {
    #expect(Document.parse("a\nb\nc\r\n").dominantEnding == .lf)
    #expect(Document.parse("a\r\nb\r\nc\n").dominantEnding == .crlf)
    #expect(Document.parse("").dominantEnding == .lf)
    #expect(Document.parse("no newline at all").dominantEnding == .lf)
}
