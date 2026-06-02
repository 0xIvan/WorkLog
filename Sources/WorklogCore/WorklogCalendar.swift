import Foundation

public struct WorklogCalendar: Sendable {
    public static let shared = WorklogCalendar()

    public var dayCutoffHour: Int {
        4
    }

    public init() {}

    public func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let localCalendar = calendar

        let localStartOfDate = localCalendar.startOfDay(for: date)
        let cutoff = localCalendar.date(
            byAdding: .hour,
            value: dayCutoffHour,
            to: localStartOfDate
        ) ?? localStartOfDate

        let start: Date
        if date < cutoff {
            start = localCalendar.date(byAdding: .day, value: -1, to: cutoff) ?? cutoff
        } else {
            start = cutoff
        }

        let end = localCalendar.date(byAdding: .day, value: 1, to: start) ?? start

        return DateInterval(start: start, end: end)
    }

    public func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let localCalendar = calendar

        let currentDayStart = dayInterval(containing: date, calendar: localCalendar).start
        let calendarWeekStart = localCalendar.dateInterval(of: .weekOfYear, for: currentDayStart)?.start
            ?? localCalendar.startOfDay(for: currentDayStart)

        return localCalendar.date(
            byAdding: .hour,
            value: dayCutoffHour,
            to: calendarWeekStart
        ) ?? calendarWeekStart
    }
}
