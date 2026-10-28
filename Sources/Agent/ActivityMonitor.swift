import CoreGraphics
import Foundation

/// How long since you last touched the keyboard.
///
/// Uses `CGEventSourceSecondsSinceLastEventType`, a system-wide idle counter:
/// **this is not an event tap**. It cannot read keystroke content and needs no
/// Accessibility permission.
enum ActivityMonitor {
    private static func seconds(_ type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    static func keyboardIdleSeconds() -> Double {
        min(seconds(.keyDown), seconds(.flagsChanged))
    }
}
