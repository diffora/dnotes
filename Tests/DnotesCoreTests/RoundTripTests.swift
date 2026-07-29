import Testing
@testable import DnotesCore

/// Every ugly shape a real notes file can take. §4.3 says all of them survive
/// `parse -> serialize` bit for bit, including the ones we do not understand.
let roundTripCorpus: [String] = [
    "",
    "\n",
    "\n\n\n",
    "no trailing newline",
    "## 2026-07-29\n\n- one\n- [x] two\n",
    "## 2026-07-29\r\n\r\n- one\r\n- [x] two\r\n",
    "## 2026-07-29\n- mixed\r\n- endings\n",
    "## 2026-07-29\n\n- last line has no newline",
    "preamble\n\n## 2026-07-29\n\n- a\n\n> a quote we do not parse\n\n    indented code\n\n## 2026-08-01\n\n- b\n",
    "## 2026-07-29\n-   three spaces\n-\ttab\n",
    "## not a day\n### 2026-07-29\n#### deeper\n",
    "- an entry before any day heading\n",
    "## 2026-07-29\n\n- [ ] unchecked\n- [X] capital X\n- [x]\n- \n",
    "## 2026-07-29\n\n- accented é and #étiquette\n- emoji 🎯 stays\n",
    "| table | we | ignore |\n| --- | --- | --- |\n",
    "---\ntitle: front matter\n---\n\n## 2026-07-29\n\n- a\n",
]

@Test(arguments: roundTripCorpus)
func serializeParseIsByteExact(_ text: String) {
    #expect(Document.parse(text).serialize() == text)
}

@Test(arguments: roundTripCorpus)
func parsingIsIdempotent(_ text: String) {
    let once = Document.parse(text)
    let twice = Document.parse(once.serialize())
    #expect(once == twice)
}

@Test func unparsedLinesAreKeptAsLinesNotDropped() {
    let text = "## 2026-07-29\n\n> quote\n- entry\n"
    let document = Document.parse(text)
    #expect(document.lines.count == 4)
    #expect(document.lines[2].kind == .other)
    #expect(document.lines[2].raw == "> quote")
}
