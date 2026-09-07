import Foundation

/// An injectable time source so rollover and date logic are testable (ADR-038).
///
/// `today()` returns the LOCAL `startOfDay` `Date` — the ONE canonical day
/// representation used across every `day` / `*On` field and by-day aggregation
/// (ADR-038). All day math flows through the clock's `calendar` so tests can
/// pin "today" deterministically and no time-of-day component ever leaks into a
/// day key.
public protocol Clock {
    /// The current instant.
    func now() -> Date

    /// The calendar used to derive day keys. Defaults to the current calendar
    /// in the live implementation; a test clock can pin a fixed time zone.
    var calendar: Calendar { get }

    /// The LOCAL start-of-day `Date` for `now()` — the canonical day key (ADR-038).
    func today() -> Date

    /// The canonical day key (local `startOfDay`) for an arbitrary instant.
    func startOfDay(for date: Date) -> Date
}

public extension Clock {
    func today() -> Date {
        startOfDay(for: now())
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

/// The production clock: wall-clock `now()` and the device's current calendar.
public struct LiveClock: Clock {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func now() -> Date {
        Date()
    }
}

/// A deterministic clock for tests: `now` is settable so a test can pin "today".
public final class TestClock: Clock {
    private var _now: Date
    public var calendar: Calendar

    public init(now: Date = Date(timeIntervalSince1970: 0), calendar: Calendar = .current) {
        self._now = now
        self.calendar = calendar
    }

    public func now() -> Date {
        _now
    }

    /// Pin the clock to a specific instant.
    public func setNow(_ date: Date) {
        _now = date
    }

    /// Advance the clock by a number of seconds.
    public func advance(by seconds: TimeInterval) {
        _now = _now.addingTimeInterval(seconds)
    }
}
