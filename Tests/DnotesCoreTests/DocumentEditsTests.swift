import Testing
@testable import DnotesCore

private let july29 = CalendarDay(iso: "2026-07-29")!
private let july30 = CalendarDay(iso: "2026-07-30")!

private func edited(_ text: String, _ body: (inout Document) -> Void) -> String {
    var document = Document.parse(text)
    body(&document)
    return document.serialize()
}

// MARK: - inserting a day

@Test func insertsADayIntoAnEmptyDocument() {
    #expect(edited("") { _ = $0.insertDay(july29) } == "## 2026-07-29\n\n")
}

@Test func insertsADayBeforeALaterOne() {
    let before = "## 2026-07-30\n\n- later\n"
    #expect(edited(before) { _ = $0.insertDay(july29) }
            == "## 2026-07-29\n\n## 2026-07-30\n\n- later\n")
}

@Test func insertsADayBetweenTwoOthers() {
    let before = "## 2026-07-28\n\n- early\n\n## 2026-07-30\n\n- late\n"
    #expect(edited(before) { _ = $0.insertDay(july29) }
            == "## 2026-07-28\n\n- early\n\n## 2026-07-29\n\n## 2026-07-30\n\n- late\n")
}

@Test func insertsADayAtTheEndWithASeparatingBlankLine() {
    let before = "## 2026-07-28\n\n- early\n"
    #expect(edited(before) { _ = $0.insertDay(july30) }
            == "## 2026-07-28\n\n- early\n\n## 2026-07-30\n\n")
}

@Test func insertingAnExistingDayIsANoOp() {
    let before = "## 2026-07-29\n\n- a\n"
    #expect(edited(before) { _ = $0.insertDay(july29) } == before)
    #expect(edited(before) { _ = $0.insertDay(july29); _ = $0.insertDay(july29) } == before)
}

@Test func insertDayReturnsTheHeadingIndex() {
    var document = Document.parse("## 2026-07-28\n\n- early\n")
    let index = document.insertDay(july30)
    #expect(document.lines[index].kind == .dayHeading(july30))
}

// MARK: - appending an entry

@Test func appendsAfterTheLastEntryOfTheDay() {
    let before = "## 2026-07-29\n\n- one\n- two\n"
    #expect(edited(before) { _ = $0.appendEntry(text: "three", to: july29) }
            == "## 2026-07-29\n\n- one\n- two\n- three\n")
}

@Test func appendsIntoAnEmptyDayAfterItsBlankLine() {
    let before = "## 2026-07-29\n\n"
    #expect(edited(before) { _ = $0.appendEntry(text: "first", to: july29) }
            == "## 2026-07-29\n\n- first\n")
}

@Test func appendsIntoANewDayOfAnExistingDocument() {
    let before = "## 2026-07-28\n\n- early\n"
    #expect(edited(before) { _ = $0.appendEntry(text: "fresh", to: july30) }
            == "## 2026-07-28\n\n- early\n\n## 2026-07-30\n\n- fresh\n")
}

@Test func doesNotStepOverTrailingUnparsedLinesOfTheDay() {
    // The quote belongs to the day but is not an entry; the new entry goes above it.
    let before = "## 2026-07-29\n\n- one\n\n> a note to self\n"
    #expect(edited(before) { _ = $0.appendEntry(text: "two", to: july29) }
            == "## 2026-07-29\n\n- one\n- two\n\n> a note to self\n")
}

@Test func appendingTerminatesAPreviouslyUnterminatedLastLine() {
    let before = "## 2026-07-29\n\n- one"
    #expect(edited(before) { _ = $0.appendEntry(text: "two", to: july29) }
            == "## 2026-07-29\n\n- one\n- two\n")
}

@Test func appendReturnsTheIndexOfTheNewEntry() {
    var document = Document.parse("## 2026-07-29\n\n- one\n")
    let index = document.appendEntry(text: "two", to: july29)
    guard case .entry(let entry) = document.lines[index].kind else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.text == "two")
}

// MARK: - line endings on insertion (§4.3)

@Test func aCRLFFileGetsCRLF() {
    let before = "## 2026-07-29\r\n\r\n- one\r\n"
    let after = edited(before) { _ = $0.appendEntry(text: "two", to: july29) }
    #expect(after == "## 2026-07-29\r\n\r\n- one\r\n- two\r\n")
    #expect(!after.contains("\n\n"))   // no mixed endings crept in
}

@Test func anLFFileGetsLF() {
    let before = "## 2026-07-29\n\n- one\n"
    let after = edited(before) { _ = $0.appendEntry(text: "two", to: july29) }
    #expect(!after.contains("\r"))
}

@Test func aNewFileGetsLF() {
    #expect(!edited("") { _ = $0.appendEntry(text: "one", to: july29) }.contains("\r"))
}

// MARK: - completing, editing, deleting

@Test func completingChangesOnlyThePrefixOfItsOwnLine() {
    let before = "## 2026-07-29\n\n- one\n- two\n- three\n"
    #expect(edited(before) { $0.setDone(true, atLine: 3) }
            == "## 2026-07-29\n\n- one\n- [x] two\n- three\n")
}

@Test func completingAnUncheckedBoxKeepsTheTextByteForByte() {
    #expect(edited("- [ ] Émile #infra\n") { $0.setDone(true, atLine: 0) }
            == "- [x] Émile #infra\n")
}

@Test func reopeningWritesThePlainForm() {
    #expect(edited("- [x] done\n") { $0.setDone(false, atLine: 0) } == "- done\n")
}

@Test func completingIsIdempotent() {
    let once = edited("- one\n") { $0.setDone(true, atLine: 0) }
    let twice = edited(once) { $0.setDone(true, atLine: 0) }
    #expect(once == twice)
}

@Test func editingReplacesTheTextAndKeepsTheState() {
    #expect(edited("- [x] old text\n") { $0.replaceText(atLine: 0, with: "new text #oss") }
            == "- [x] new text #oss\n")
}

@Test func editingRefreshesTheParsedTags() {
    var document = Document.parse("- old\n")
    document.replaceText(atLine: 0, with: "new #oss")
    guard case .entry(let entry) = document.lines[0].kind else {
        Issue.record("expected an entry"); return
    }
    #expect(entry.tags == ["oss"])
}

@Test func deletingRemovesExactlyOneLine() {
    #expect(edited("## 2026-07-29\n\n- one\n- two\n") { $0.removeLine(at: 3) }
            == "## 2026-07-29\n\n- one\n")
}

@Test func editsLeaveNeighbouringLinesUntouched() {
    let before = "## 2026-07-29\n\n- one\n> quote\n- two\n"
    var document = Document.parse(before)
    document.setDone(true, atLine: 2)
    #expect(document.lines[3].raw == "> quote")
    #expect(document.lines[4].raw == "- two")
}
