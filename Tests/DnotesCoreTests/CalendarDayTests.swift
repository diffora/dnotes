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
    let instant = Date(timeIntervalSince1970: 1_785_360_600)
    #expect(CalendarDay.today(now: instant, calendar: calendar) == CalendarDay(iso: "2026-07-30"))
}
