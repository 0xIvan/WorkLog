import CoreGraphics
import Foundation

struct IdleMonitor {
    func secondsSinceLastInput() -> TimeInterval {
        let events: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .scrollWheel
        ]

        return events
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
