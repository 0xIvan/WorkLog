import Foundation

public struct TimeFormatting {
    public init() {}

    public func compactDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    public func menuBarWorkDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60

        return "\(hours):\(String(format: "%02d", minutes))"
    }

    public func decimalHours(_ duration: TimeInterval) -> Double {
        duration / 3_600
    }
}
