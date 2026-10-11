import CoreGraphics
import Foundation

/// How long the user has been away from the keyboard and mouse.
enum SystemIdle {
    /// Seconds since the last keyboard, mouse or trackpad input. Needs no permissions.
    static func seconds() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
