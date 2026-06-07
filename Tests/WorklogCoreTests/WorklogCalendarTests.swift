import Foundation
import Testing
import WorklogCore

@Suite
struct WorklogCalendarTests {
    @Test
    func dayBeforeFourAMBelongsToPreviousWorklogDay() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-02T03:30:00Z")
        let expectedStart = try date("2026-06-01T04:00:00Z")
        let expectedEnd = try date("2026-06-02T04:00:00Z")
        let interval = WorklogCalendar().dayInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test
    func dayAfterFourAMBelongsToCurrentWorklogDay() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-02T14:00:00Z")
        let expectedStart = try date("2026-06-02T04:00:00Z")
        let expectedEnd = try date("2026-06-03T04:00:00Z")
        let interval = WorklogCalendar().dayInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test
    func monthBeforeFourAMBelongsToPreviousWorklogMonth() throws {
        let calendar = utcCalendar()
        let sampleDate = try date("2026-06-01T03:30:00Z")
        let expectedStart = try date("2026-05-01T04:00:00Z")
        let expectedEnd = try date("2026-06-01T04:00:00Z")
        let interval = WorklogCalendar().monthInterval(containing: sampleDate, calendar: calendar)

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()

        return try #require(formatter.date(from: value))
    }
}
