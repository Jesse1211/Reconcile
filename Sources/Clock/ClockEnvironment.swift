import SwiftUI

/// Exposes the injectable `Clock` (ADR-038) via the SwiftUI environment so later tasks
/// (rollover, date logic) read time through it and tests can inject a `TestClock`.
private struct ClockKey: EnvironmentKey {
    static let defaultValue: Clock = LiveClock()
}

public extension EnvironmentValues {
    var clock: Clock {
        get { self[ClockKey.self] }
        set { self[ClockKey.self] = newValue }
    }
}
