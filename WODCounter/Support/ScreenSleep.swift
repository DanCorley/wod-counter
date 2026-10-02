import UIKit

/// Keeps the device awake while a workout is in progress.
///
/// `UIApplication.isIdleTimerDisabled` is global, persistent application state
/// rather than a view property — left set, the screen never sleeps again for
/// the rest of the app's lifetime, which reads to the user as a battery bug
/// with no visible cause. Ownership is therefore reference counted here: every
/// `hold()` must be balanced by a `release()`, and overlapping owners cannot
/// clobber one another.
///
/// iOS restores normal behaviour on its own when the app leaves the foreground,
/// so a suspended app cannot pin the screen awake.
@MainActor
enum ScreenSleep {
    private static var holds = 0

    /// Whether anything currently wants the screen kept awake.
    static var isHeld: Bool { holds > 0 }

    static func hold() {
        holds += 1
        apply()
    }

    static func release() {
        guard holds > 0 else { return }
        holds -= 1
        apply()
    }

    /// Drops every outstanding hold. Backstop for a session that disappears
    /// without balancing its own.
    static func releaseAll() {
        holds = 0
        apply()
    }

    private static func apply() {
        UIApplication.shared.isIdleTimerDisabled = holds > 0
    }
}
