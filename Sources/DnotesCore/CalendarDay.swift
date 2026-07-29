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
