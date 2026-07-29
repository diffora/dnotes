import Foundation

/// The one-time migration from a flat `notes.md` to one file per month (§4).
public enum NotesImporter {
    public static let legacyFileName = "notes.md"

    /// Splits a legacy file into month files. Every line goes into the month of the
    /// day heading above it, byte for byte; lines above the first heading go to the
    /// top of the earliest month. A file with no day headings yields nothing — there
    /// is no month to file it under, and inventing one would move someone's text.
    public static func split(_ text: String) -> [MonthID: String] {
        let document = Document.parse(text)
        var preamble: [Line] = []
        var buckets: [MonthID: [Line]] = [:]
        var current: MonthID?

        for line in document.lines {
            if case .dayHeading(let day) = line.kind {
                current = day.monthID
            }
            guard let month = current else {
                preamble.append(line)
                continue
            }
            buckets[month, default: []].append(line)
        }

        guard let earliest = buckets.keys.min() else { return [:] }
        if !preamble.isEmpty {
            buckets[earliest] = preamble + (buckets[earliest] ?? [])
        }

        return buckets.mapValues { Document(lines: $0).serialize() }
    }
}
