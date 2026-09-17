import SwiftUI

/// Formatting helpers for the stopwatch, retained as `TimerScreen` for source/test
/// stability after the Timer screen was folded into Today's lower pager (it is now
/// ``TimerPaneView``, the second page under the shared quote card). The interactive UI
/// lives in ``TimerPaneView``; only the pure formatter remains here.
///
/// `formatElapsed` renders whole seconds as `H:MM:SS` (hours shown only when non-zero) —
/// a single undivided elapsed figure. This is a per-session / live-stopwatch figure ONLY;
/// the app never sums these into a "today total" (ADR-032/E3).
enum TimerScreen {
    /// Format whole seconds as `H:MM:SS` (hours shown only when non-zero).
    static func formatElapsed(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
