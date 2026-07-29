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
