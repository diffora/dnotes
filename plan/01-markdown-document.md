# Tasks 2–5: `MarkdownDocument`

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 step 1, tested per §9.1. No UI, no filesystem: everything here is a pure value type,
which is why it is the densest tested layer in the project. The preservation invariant of §4.3 is
established in Task 3 and every later task depends on it holding.

**The design that makes §4.3 true:** `Line.raw` holds the original bytes of the line, and
`serialize()` is nothing but `raw + ending` concatenated. Parsing produces `kind` as *derived
metadata alongside* the raw bytes, never as a replacement for them. Edits rewrite `raw` explicitly.
It is therefore impossible for an untouched line to come out different from how it went in, and
tests confirm the property rather than chase it.

---

### Task 2: `CalendarDay` and `MonthID`

**Files:**
- Create: `Sources/DnotesCore/CalendarDay.swift`
- Test: `Tests/DnotesCoreTests/CalendarDayTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `CalendarDay` and `MonthID` as specified in [README.md](README.md#public-api-fixed-across-tasks). Every later task uses them.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/CalendarDayTests.swift`:

```swift
import Foundation
import Testing
@testable import DnotesCore

@Test func parsesAStrictISODay() {
    let day = CalendarDay(iso: "2026-07-29")
    #expect(day == CalendarDay(year: 2026, month: 7, day: 29))
    #expect(day?.description == "2026-07-29")
}

@Test(arguments: [
    "2026-7-29",       // unpadded month
    "2026-07-29 ",     // trailing space is the caller's job to trim
    "26-07-29",
    "2026/07/29",
    "2026-13-01",      // month out of range
    "2026-07-32",      // day out of range
    "not a date",
    "",
])
func rejectsAnythingButAStrictISODay(_ text: String) {
    #expect(CalendarDay(iso: text) == nil)
}

@Test func ordersChronologically() {
    #expect(CalendarDay(iso: "2026-07-29")! < CalendarDay(iso: "2026-08-01")!)
    #expect(CalendarDay(iso: "2025-12-31")! < CalendarDay(iso: "2026-01-01")!)
    #expect(!(CalendarDay(iso: "2026-07-29")! < CalendarDay(iso: "2026-07-29")!))
}

@Test func exposesItsMonth() {
    #expect(CalendarDay(iso: "2026-07-29")!.monthID == MonthID(year: 2026, month: 7))
    #expect(MonthID(year: 2026, month: 7).fileName == "2026-07.md")
    #expect(MonthID(year: 2026, month: 7).description == "2026-07")
}

@Test(arguments: [
    "2026-07.md",
    "2025-12.md",
])
func acceptsMonthFileNames(_ name: String) {
    #expect(MonthID(fileName: name) != nil)
}

@Test(arguments: [
    "notes.md",
    "README.md",
    "2026-07 2.md",                 // iCloud conflict copy
    "2026-07 (conflicted copy).md", // Dropbox conflict copy
    "2026-7.md",
    "2026-13.md",
    "2026-07.markdown",
    "2026-07.md.bak",
])
func rejectsEverythingElse(_ name: String) {
    #expect(MonthID(fileName: name) == nil)
}

@Test func todayUsesTheGivenCalendarAndInstant() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    // 2026-07-29 21:30 UTC is already 2026-07-30 00:30 in Kyiv (§5.1: no day-boundary offset).
    let instant = Date(timeIntervalSince1970: 1_785_101_400)
    #expect(CalendarDay.today(now: instant, calendar: calendar) == CalendarDay(iso: "2026-07-30"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter CalendarDay`
Expected: FAIL, `cannot find 'CalendarDay' in scope`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/CalendarDay.swift`:

```swift
import Foundation

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// One month, which is one file (§4).
public struct MonthID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// Strictly `YYYY-MM.md` — the pattern *is* the defence against cloud conflict
    /// copies (§4). Anything looser lets `2026-07 2.md` in and the month shows twice.
    public init?(fileName: String) {
        let chars = Array(fileName)
        guard chars.count == 10, fileName.hasSuffix(".md"), chars[4] == "-" else { return nil }
        let yearText = String(chars[0..<4])
        let monthText = String(chars[5..<7])
        guard yearText.allSatisfy(\.isASCIIDigit), monthText.allSatisfy(\.isASCIIDigit),
              let year = Int(yearText), let month = Int(monthText),
              (1...12).contains(month)
        else { return nil }
        self.init(year: year, month: month)
    }

    public var fileName: String { "\(description).md" }
    public var description: String { String(format: "%04d-%02d", year, month) }

    public static func < (lhs: MonthID, rhs: MonthID) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// One day heading (§4.1). A calendar date with no time and no time zone — the
/// zone is applied once, at `today(now:calendar:)`, and never stored.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strictly `YYYY-MM-DD`. The day is range-checked but not validated against the
    /// month's length: a hand-written `## 2026-02-31` is odd, not a reason to drop
    /// the heading and swallow the entries under it.
    public init?(iso: String) {
        let chars = Array(iso)
        guard chars.count == 10, chars[4] == "-", chars[7] == "-" else { return nil }
        let yearText = String(chars[0..<4])
        let monthText = String(chars[5..<7])
        let dayText = String(chars[8..<10])
        guard yearText.allSatisfy(\.isASCIIDigit), monthText.allSatisfy(\.isASCIIDigit),
              dayText.allSatisfy(\.isASCIIDigit),
              let year = Int(yearText), let month = Int(monthText), let day = Int(dayText),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// "Today" is the system calendar date in the current time zone, with no
    /// day-boundary offset (§5.1).
    public static func today(now: Date = Date(), calendar: Calendar = .current) -> CalendarDay {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDay(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Midnight of this day, for date arithmetic such as the 30-day tag window (§6).
    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public var monthID: MonthID { MonthID(year: year, month: month) }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter CalendarDay`
Expected: PASS, 7 test functions (the parameterised ones count once per argument).

- [ ] **Step 5: Commit**

```bash
git add Sources/DnotesCore/CalendarDay.swift Tests/DnotesCoreTests/CalendarDayTests.swift
git commit -m "feat: CalendarDay and MonthID value types

MonthID's strict YYYY-MM.md pattern is what keeps cloud conflict copies
out of the note set (design §4)."
```

---

### Task 3: `Document.parse` / `serialize` — the round-trip invariant

The most important task in the plan. §4.3 is established here.

**Files:**
- Create: `Sources/DnotesCore/Document.swift`, `Sources/DnotesCore/MarkdownParser.swift`
- Test: `Tests/DnotesCoreTests/RoundTripTests.swift`, `Tests/DnotesCoreTests/ParsingTests.swift`

**Interfaces:**
- Consumes: `CalendarDay` (Task 2).
- Produces: `LineEnding`, `Entry`, `LineKind`, `Line`, `Document`, `Document.parse`,
  `Document.serialize`, `Document.dominantEnding`, and the internal `EntryLineParser` /
  `LineClassifier` / `LineSplitter` used by Task 5. Note `Entry.tags` is populated in Task 4 and is
  an empty array until then.

- [ ] **Step 1: Write the failing round-trip tests**

`Tests/DnotesCoreTests/RoundTripTests.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing parsing tests**

`Tests/DnotesCoreTests/ParsingTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter "RoundTrip|Parsing"`
Expected: FAIL, `cannot find 'Document' in scope`.

- [ ] **Step 4: Implement the types**

`Sources/DnotesCore/Document.swift`:

```swift
import Foundation

public enum LineEnding: String, Sendable, Equatable, Codable {
    case lf = "\n"
    case crlf = "\r\n"
}

/// One captured line. `text` is everything after the marker, byte for byte.
public struct Entry: Equatable, Sendable {
    public var text: String
    public var isDone: Bool
    public var tags: [String]

    public init(text: String, isDone: Bool, tags: [String]) {
        self.text = text
        self.isDone = isDone
        self.tags = tags
    }
}

public enum LineKind: Equatable, Sendable {
    case dayHeading(CalendarDay)
    case entry(Entry)
    /// Anything we did not understand — preserved untouched (§4.1, §4.3).
    case other
}

/// A source line. `raw` holds the original bytes without the terminator and is
/// the only thing `serialize()` emits; `kind` is derived metadata beside it.
public struct Line: Equatable, Sendable {
    public var raw: String
    public var ending: LineEnding?
    public var kind: LineKind

    public init(raw: String, ending: LineEnding?, kind: LineKind) {
        self.raw = raw
        self.ending = ending
        self.kind = kind
    }

    var isBlank: Bool { raw.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct Document: Equatable, Sendable {
    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public func serialize() -> String {
        var out = ""
        out.reserveCapacity(lines.reduce(0) { $0 + $1.raw.utf8.count + 2 })
        for line in lines {
            out += line.raw
            if let ending = line.ending { out += ending.rawValue }
        }
        return out
    }

    /// The style new lines are written in (§4.3): whichever the file already uses
    /// more of, `LF` for a new or single-line file.
    public var dominantEnding: LineEnding {
        var crlf = 0
        var lf = 0
        for line in lines {
            switch line.ending {
            case .crlf: crlf += 1
            case .lf: lf += 1
            case nil: break
            }
        }
        return crlf > lf ? .crlf : .lf
    }
}
```

- [ ] **Step 5: Implement the parser**

`Sources/DnotesCore/MarkdownParser.swift`:

```swift
import Foundation

enum LineSplitter {
    /// Splits on `LF` and `CRLF`, remembering which terminator each line had, so a
    /// mixed-ending file survives a round trip. A lone `CR` is not treated as a
    /// terminator — it stays inside the line's text.
    static func split(_ text: String) -> [(raw: String, ending: LineEnding?)] {
        var result: [(raw: String, ending: LineEnding?)] = []
        var current = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            // Swift treats CRLF as one Character, so it has to be matched as one —
            // comparing against "\r" and then peeking at "\n" never fires.
            if character == "\r\n" {
                result.append((current, .crlf))
                current = ""
                index = text.index(after: index)
                continue
            }
            if character == "\n" {
                result.append((current, .lf))
                current = ""
                index = text.index(after: index)
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }

        // A non-empty tail means the file does not end with a newline.
        if !current.isEmpty { result.append((current, nil)) }
        return result
    }
}

/// The three fixed parts of an entry line. Splitting it this way is what lets a
/// toggle touch the prefix and nothing else (§4.2).
struct EntryLineParts: Equatable, Sendable {
    var prefix: String   // indent + "-" + the whitespace after it
    var isDone: Bool
    var text: String     // after the optional checkbox and its whitespace
}

enum EntryLineParser {
    static func parse(_ raw: String) -> EntryLineParts? {
        var index = raw.startIndex
        while index < raw.endIndex, raw[index] == " " || raw[index] == "\t" {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex, raw[index] == "-" else { return nil }
        index = raw.index(after: index)

        var gapEnd = index
        while gapEnd < raw.endIndex, raw[gapEnd] == " " || raw[gapEnd] == "\t" {
            gapEnd = raw.index(after: gapEnd)
        }
        // `-foo` is a word, not a bullet.
        guard gapEnd > index else { return nil }

        let prefix = String(raw[raw.startIndex..<gapEnd])
        var rest = raw[gapEnd...]
        var isDone = false

        if rest.hasPrefix("[ ]") || rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
            isDone = !rest.hasPrefix("[ ]")
            rest = rest.dropFirst(3)
            while let first = rest.first, first == " " || first == "\t" {
                rest = rest.dropFirst()
            }
        }

        return EntryLineParts(prefix: prefix, isDone: isDone, text: String(rest))
    }

    /// The inverse of `parse`, and the only place an entry line is written.
    /// Reopening writes the plain `- ` form: `- [ ]` exists for compatibility with
    /// other tools (§4.1), it is not what dnotes produces.
    static func render(_ parts: EntryLineParts) -> String {
        parts.prefix + (parts.isDone ? "[x] " : "") + parts.text
    }
}

enum LineClassifier {
    static func classify(_ raw: String) -> LineKind {
        if let day = dayHeading(raw) { return .dayHeading(day) }
        if let parts = EntryLineParser.parse(raw), !parts.text.isEmpty {
            return .entry(Entry(text: parts.text, isDone: parts.isDone, tags: []))
        }
        return .other
    }

    private static func dayHeading(_ raw: String) -> CalendarDay? {
        guard raw.hasPrefix("## ") else { return nil }
        let rest = raw.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return CalendarDay(iso: rest)
    }
}

extension Document {
    public static func parse(_ text: String) -> Document {
        Document(lines: LineSplitter.split(text).map {
            Line(raw: $0.raw, ending: $0.ending, kind: LineClassifier.classify($0.raw))
        })
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter "RoundTrip|Parsing"`
Expected: PASS. If any corpus entry fails, **fix the parser, never the corpus** — a corpus entry
that has to be deleted to go green is a §4.3 violation looking for a place to happen.

- [ ] **Step 7: Commit**

```bash
git add Sources/DnotesCore/Document.swift Sources/DnotesCore/MarkdownParser.swift Tests/DnotesCoreTests/RoundTripTests.swift Tests/DnotesCoreTests/ParsingTests.swift
git commit -m "feat: markdown parse and serialize with a byte-exact round trip

Line.raw holds the original bytes and serialize() concatenates raw+ending,
so the §4.3 preservation invariant holds by construction rather than by
care. Tags are added in the next commit."
```

---

### Task 4: Tag scanner

**Files:**
- Create: `Sources/DnotesCore/TagScanner.swift`
- Modify: `Sources/DnotesCore/MarkdownParser.swift` (`LineClassifier.classify`, populate `Entry.tags`)
- Test: `Tests/DnotesCoreTests/TagScannerTests.swift`

**Interfaces:**
- Consumes: `Entry` (Task 3).
- Produces: `TagScanner.tags(in:) -> [String]`, returning tags in order of appearance with
  duplicates removed, and a populated `Entry.tags`.

**Case sensitivity:** tags keep the case they were written in, so `#OSS` and `#oss` are two tags.
The spec does not say otherwise, and folding case would need a display form and a match form. If
two spellings of one tag turn up in daily use, fold in `TagScanner` and nowhere else.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/TagScannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter TagScanner`
Expected: FAIL, `cannot find 'TagScanner' in scope`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/TagScanner.swift`:

```swift
import Foundation

/// Tags are `#word` substrings of the entry text (§4.1). There is no tag field
/// anywhere — this scanner is the only definition of what a tag is.
public enum TagScanner {
    /// Characters that may precede a `#` and still let it open a tag. Whitespace and
    /// line start also qualify. The stricter rule "no tag after any non-whitespace"
    /// would cost `(#infra)`, which is ordinary writing.
    private static let openers: Set<Character> = ["(", "[", "{", "«", "\""]

    /// Tags in order of first appearance, without duplicates.
    public static func tags(in text: String) -> [String] {
        var found: [String] = []
        var seen: Set<String> = []
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "#", canOpenTag(after: previous) else {
                previous = character
                index = text.index(after: index)
                continue
            }

            let bodyStart = text.index(after: index)
            var bodyEnd = bodyStart
            while bodyEnd < text.endIndex, isBodyCharacter(text[bodyEnd]) {
                bodyEnd = text.index(after: bodyEnd)
            }

            if bodyEnd > bodyStart {
                let tag = String(text[bodyStart..<bodyEnd])
                if seen.insert(tag).inserted { found.append(tag) }
                previous = text[text.index(before: bodyEnd)]
                index = bodyEnd
            } else {
                previous = character
                index = bodyStart
            }
        }

        return found
    }

    private static func canOpenTag(after previous: Character?) -> Bool {
        guard let previous else { return true }   // start of the text
        if previous.isWhitespace { return true }
        return openers.contains(previous)
    }

    private static func isBodyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
```

- [ ] **Step 4: Populate `Entry.tags` in the classifier**

In `Sources/DnotesCore/MarkdownParser.swift`, change the entry branch of `LineClassifier.classify`:

```swift
        if let parts = EntryLineParser.parse(raw), !parts.text.isEmpty {
            return .entry(Entry(
                text: parts.text,
                isDone: parts.isDone,
                tags: TagScanner.tags(in: parts.text)
            ))
        }
```

- [ ] **Step 5: Run the whole suite**

Run: `./scripts/test.sh`
Expected: PASS, including the Task 3 round-trip tests — tags are derived metadata and cannot change
what gets serialized.

- [ ] **Step 6: Commit**

```bash
git add Sources/DnotesCore/TagScanner.swift Sources/DnotesCore/MarkdownParser.swift Tests/DnotesCoreTests/TagScannerTests.swift
git commit -m "feat: tag scanner

Opening characters ( [ { « \" still open a tag so (#infra) keeps working,
while a hash after a letter, digit or slash does not — which is what keeps
URL anchors out (design §4.1)."
```

---

### Task 5: Document edits — day insertion, append, toggle, edit, delete

**Files:**
- Create: `Sources/DnotesCore/DocumentEdits.swift`
- Test: `Tests/DnotesCoreTests/DocumentEditsTests.swift`

**Interfaces:**
- Consumes: `Document`, `Line`, `EntryLineParser`, `LineClassifier` (Task 3); `CalendarDay` (Task 2).
- Produces: `Document.dayHeadingIndex(for:)`, `dayLineRange(headingIndex:)`, `insertDay(_:)`,
  `appendEntry(text:to:)`, `setDone(_:atLine:)`, `replaceText(atLine:with:)`, `removeLine(at:)`.
  Task 8 drives all of them from the repository.

**Where a new entry goes:** after the last entry line of its day. Not at the end of the day's
section — a day can end with unparsed lines or blanks, and stepping over them would drag them along
on every capture.

**Where a new day goes:** in date order, above the blank lines that separate it from the next day
(§4.1: "a new day is inserted in its place by order, not appended at the end").

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/DocumentEditsTests.swift`:

```swift
import Testing
@testable import DnotesCore

private let july29 = CalendarDay(iso: "2026-07-29")!
private let july30 = CalendarDay(iso: "2026-07-30")!
private let july28 = CalendarDay(iso: "2026-07-28")!

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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter DocumentEdits`
Expected: FAIL, `value of type 'Document' has no member 'insertDay'`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/DocumentEdits.swift`:

```swift
import Foundation

extension Document {
    public func dayHeadingIndex(for day: CalendarDay) -> Int? {
        lines.firstIndex { line in
            guard case .dayHeading(let heading) = line.kind else { return false }
            return heading == day
        }
    }

    /// The lines under a day heading, heading excluded, up to the next heading.
    public func dayLineRange(headingIndex: Int) -> Range<Int> {
        var end = headingIndex + 1
        while end < lines.count {
            if case .dayHeading = lines[end].kind { break }
            end += 1
        }
        return (headingIndex + 1)..<end
    }

    private func firstDayIndex(after day: CalendarDay) -> Int? {
        lines.firstIndex { line in
            guard case .dayHeading(let heading) = line.kind else { return false }
            return heading > day
        }
    }

    private mutating func terminateLastLine(with ending: LineEnding) {
        guard let last = lines.indices.last, lines[last].ending == nil else { return }
        lines[last].ending = ending
    }

    /// Inserts the day in date order, or returns the index of the existing heading.
    @discardableResult
    public mutating func insertDay(_ day: CalendarDay) -> Int {
        if let existing = dayHeadingIndex(for: day) { return existing }

        let ending = dominantEnding
        let heading = Line(raw: "## \(day)", ending: ending, kind: .dayHeading(day))
        let blank = Line(raw: "", ending: ending, kind: .other)

        if let successor = firstDayIndex(after: day) {
            // Directly above the next heading, so the blank lines that already
            // separated the previous day from it now separate it from the new one,
            // and the new day brings its own blank for the heading below.
            lines.insert(contentsOf: [heading, blank], at: successor)
            return successor
        }

        terminateLastLine(with: ending)
        if let last = lines.last, !last.isBlank {
            lines.append(Line(raw: "", ending: ending, kind: .other))
        }
        lines.append(contentsOf: [heading, blank])
        return lines.count - 2
    }

    /// Appends an entry after the last entry of its day, creating the day if needed.
    @discardableResult
    public mutating func appendEntry(text: String, to day: CalendarDay) -> Int {
        let headingIndex = insertDay(day)
        let ending = dominantEnding
        let range = dayLineRange(headingIndex: headingIndex)

        let lastEntry = range.last { index in
            if case .entry = lines[index].kind { return true }
            return false
        }

        var insertAt: Int
        if let lastEntry {
            insertAt = lastEntry + 1
        } else {
            insertAt = range.lowerBound
            if insertAt < range.upperBound, lines[insertAt].isBlank { insertAt += 1 }
        }

        terminateLastLine(with: ending)
        let raw = "- " + text
        lines.insert(Line(raw: raw, ending: ending, kind: LineClassifier.classify(raw)), at: insertAt)
        return insertAt
    }

    /// Completing or reopening touches the prefix and nothing else (§4.2).
    public mutating func setDone(_ done: Bool, atLine index: Int) {
        guard var parts = EntryLineParser.parse(lines[index].raw) else { return }
        parts.isDone = done
        rewrite(index, with: parts)
    }

    public mutating func replaceText(atLine index: Int, with newText: String) {
        guard var parts = EntryLineParser.parse(lines[index].raw) else { return }
        parts.text = newText
        rewrite(index, with: parts)
    }

    public mutating func removeLine(at index: Int) {
        lines.remove(at: index)
    }

    private mutating func rewrite(_ index: Int, with parts: EntryLineParts) {
        let raw = EntryLineParser.render(parts)
        lines[index].raw = raw
        lines[index].kind = LineClassifier.classify(raw)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter DocumentEdits`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `./scripts/test.sh`
Expected: PASS. Watch the round-trip tests in particular — an edit helper that quietly rebuilt a
line from structure would break them.

- [ ] **Step 6: Commit**

```bash
git add Sources/DnotesCore/DocumentEdits.swift Tests/DnotesCoreTests/DocumentEditsTests.swift
git commit -m "feat: document edits — day insertion, append, toggle, edit, delete

New days land in date order above the separator of the following day; new
entries land after the last entry of their day rather than at the end of
its section, so trailing unparsed lines are never dragged along."
```
