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
            return .entry(Entry(
                text: parts.text,
                isDone: parts.isDone,
                tags: TagScanner.tags(in: parts.text)
            ))
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
