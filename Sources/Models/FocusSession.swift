import Foundation
import SwiftData

/// A focus timer session (ADR-002).
///
/// INV-5: session duration is ALWAYS derived from timestamps
/// (`endedAt - startedAt`). `accumulatedSeconds` is a CACHE that is written ONLY
/// on stop; while a session is running (`endedAt == nil`) the cache is ignored,
/// and the live duration is computed against the current clock instant. A
/// timestamp-derived duration is never negative (INV-5): if `endedAt < startedAt`
/// the duration clamps to zero rather than going negative.
@Model
public final class FocusSession {
    /// Stable identity (independent of SwiftData's `PersistentIdentifier`).
    public var id: UUID
    /// When the session started.
    public var startedAt: Date
    /// When the session ended, or `nil` while running (INV-5).
    public var endedAt: Date?
    /// Cached whole-second duration, written ONLY on stop (INV-5).
    ///
    /// While running this holds `0` and is ignored — the live duration is always
    /// recomputed from timestamps.
    public var accumulatedSeconds: Int

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        accumulatedSeconds: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.accumulatedSeconds = accumulatedSeconds
    }
}

public extension FocusSession {
    /// Whether the session is still running (`endedAt == nil`).
    var isRunning: Bool {
        endedAt == nil
    }

    /// The non-negative duration in whole seconds, ALWAYS derived from timestamps
    /// (INV-5).
    ///
    /// - While running (`endedAt == nil`): measured from `startedAt` to `now`.
    /// - When stopped: measured from `startedAt` to `endedAt`.
    /// The `accumulatedSeconds` cache is NOT read here — timestamps are the source
    /// of truth. A reversed interval clamps to `0` (INV-5: never negative).
    ///
    /// - Parameter now: the current instant (`clock.now()`), used only while running.
    func duration(now: Date) -> Int {
        let end = endedAt ?? now
        let seconds = end.timeIntervalSince(startedAt)
        guard seconds > 0 else { return 0 }
        return Int(seconds)
    }

    /// Stop the session at `date`, writing the `accumulatedSeconds` cache from the
    /// timestamp-derived duration (INV-5). No-op if already stopped.
    ///
    /// - Parameter date: the stop instant (`clock.now()`).
    func stop(at date: Date) {
        guard endedAt == nil else { return }
        endedAt = date
        // Cache is written ONLY here, from the timestamp-derived (non-negative) duration.
        accumulatedSeconds = duration(now: date)
    }
}
