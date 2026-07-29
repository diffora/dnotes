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
