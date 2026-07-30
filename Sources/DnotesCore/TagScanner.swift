import Foundation

/// Tags are `#word` substrings of the entry text (§4.1). There is no tag field
/// anywhere — this scanner is the only definition of what a tag is.
public enum TagScanner {
    /// Characters that may precede a `#` and still let it open a tag. Whitespace and
    /// line start also qualify. The stricter rule "no tag after any non-whitespace"
    /// would cost `(#infra)`, which is ordinary writing.
    static let openers: Set<Character> = ["(", "[", "{", "«", "\""]

    /// One `#word` occurrence: the tag, and where it sits in the text.
    ///
    /// The range covers the `#` as well as the body, because what reads as a tag on
    /// screen is the whole thing — colouring `infra` and leaving its `#` in body ink
    /// would look like a typo.
    public struct Span: Equatable, Sendable {
        public let range: Range<String.Index>
        public let tag: String

        public init(range: Range<String.Index>, tag: String) {
            self.range = range
            self.tag = tag
        }
    }

    /// Every occurrence, in order, duplicates included — a line that names a tag
    /// twice has two of them to colour.
    ///
    /// This is the scanner proper; `tags(in:)` is the de-duplicated view of it. Both
    /// answers come from one walk of the string so the two can never disagree about
    /// what a tag is.
    public static func spans(in text: String) -> [Span] {
        var found: [Span] = []
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
                found.append(Span(range: index..<bodyEnd, tag: String(text[bodyStart..<bodyEnd])))
                previous = text[text.index(before: bodyEnd)]
                index = bodyEnd
            } else {
                previous = character
                index = bodyStart
            }
        }

        return found
    }

    /// The line with its tags taken out, for the layout that shows them as chips at the
    /// end of the row instead of inline.
    ///
    /// Removing a tag leaves the spaces that surrounded it, so the gap is closed and the
    /// ends are trimmed — otherwise `#minotoring presenation` would render as
    /// ` presenation`, indented by one space out of step with every other row.
    ///
    /// Returns an empty string for a line that is nothing but tags. That case cannot be
    /// papered over here — the caller has to decide what an otherwise blank row shows,
    /// and it does (`EntryRowView` falls back to the inline layout).
    public static func stripping(_ text: String) -> String {
        var out = ""
        var last = text.startIndex
        for span in spans(in: text) {
            out += text[last..<span.range.lowerBound]
            last = span.range.upperBound

            // The tag stood between two spaces, so removing it left both: drop one. Done
            // here, at the seam, rather than by collapsing double spaces afterwards —
            // that would also reformat spacing the author typed on purpose elsewhere in
            // the line, which is not this function's business.
            if out.last == " ", last < text.endIndex, text[last] == " " {
                out.removeLast()
            }
        }
        out += text[last...]
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Tags in order of first appearance, without duplicates.
    public static func tags(in text: String) -> [String] {
        var found: [String] = []
        var seen: Set<String> = []
        for span in spans(in: text) where seen.insert(span.tag).inserted {
            found.append(span.tag)
        }
        return found
    }

    static func canOpenTag(after previous: Character?) -> Bool {
        guard let previous else { return true }   // start of the text
        if previous.isWhitespace { return true }
        return openers.contains(previous)
    }

    static func isBodyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
