import Foundation
import Testing
import WorklogCore

@Suite
struct TimeFormattingTests {
    @Test
    func menuBarWorkDurationUsesZeroHourBelowOneHour() {
        #expect(TimeFormatting().menuBarWorkDuration(45 * 60) == "0:45")
    }

    @Test
    func menuBarWorkDurationUsesColonFormatAtOneHour() {
        #expect(TimeFormatting().menuBarWorkDuration((1 * 3_600) + (20 * 60)) == "1:20")
    }

    @Test
    func menuBarWorkDurationPadsMinutes() {
        #expect(TimeFormatting().menuBarWorkDuration((2 * 3_600) + (5 * 60)) == "2:05")
    }
}
