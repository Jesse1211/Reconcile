import Foundation
import SwiftData

/// The stopwatch service for standalone focus sessions (ADR-014).
///
/// A count-up stopwatch with three lifecycle actions — **start**, **stop**, and
/// **discard** — over the persisted `FocusSession` model. Multiple independent
/// sessions per day are allowed (ADR-014); each is its own record.
///
/// ## Timestamp source of truth (INV-5 / ADR-014)
/// Elapsed time is ALWAYS derived from `startedAt` (and `endedAt` once stopped),
/// never from the `accumulatedSeconds` cache. Because `startedAt` survives an app
/// kill (it is persisted), resuming after a kill recomputes elapsed as
/// `now − startedAt` — the live display is a single undivided running number, even
/// across midnight (ADR-032: the running figure is NOT day-split). `stop` writes
/// the `accumulatedSeconds` cache from `endedAt − startedAt`; `discard` never saves.
///
/// ## Aggregation vs. live display (ADR-032)
/// The midnight split lives at query time, NOT at storage: a stored session is ONE
/// record. Per-day aggregation for the Summary read-model is provided by
/// ``FocusSessionService/dailyTotals(in:calendar:)`` and the pure splitter
/// ``FocusSessionService/perDayPortions(startedAt:endedAt:calendar:)``. A running
/// (un-stopped) session is EXCLUDED from every per-day total — only stopped/saved
/// sessions count toward an aggregate.
///
/// The service holds no mutable state of its own; it operates on the injected
/// `ModelContext` and `Clock`, keeping day math testable (ADR-038).
public struct FocusSessionService {
    private let context: ModelContext
    private let clock: Clock

    /// Create a service bound to a persistence context and a clock.
    ///
    /// - Parameters:
    ///   - context: the SwiftData context sessions are read from / written to.
    ///   - clock: the injectable time source (ADR-038); its `now()` stamps
    ///     `startedAt` / `endedAt`, and its `calendar` drives the per-day split.
    public init(context: ModelContext, clock: Clock) {
        self.context = context
        self.clock = clock
    }

    // MARK: - Lifecycle: start / stop / discard

    /// Start a new running stopwatch session, stamping `startedAt` from the clock.
    ///
    /// Inserts a fresh `FocusSession` (`endedAt == nil`, `accumulatedSeconds == 0`)
    /// and saves it so `startedAt` survives an app kill (INV-5: elapsed is
    /// recomputed from it on resume). Multiple independent sessions per day are
    /// allowed (ADR-014) — this never coalesces with, or stops, any other session.
    ///
    /// - Returns: the newly started, running session.
    /// - Throws: any error raised by the context save.
    @discardableResult
    public func start() throws -> FocusSession {
        let session = FocusSession(startedAt: clock.now())
        context.insert(session)
        try context.save()
        return session
    }

    /// Stop a running session, SAVING it (ADR-014).
    ///
    /// Stamps `endedAt` from the clock and writes the `accumulatedSeconds` cache
    /// from the timestamp-derived duration (`endedAt − startedAt`, INV-5). A
    /// no-op on an already-stopped session (idempotent, matching
    /// ``FocusSession/stop(at:)``). The saved record is what per-day aggregation
    /// later counts.
    ///
    /// - Parameter session: the session to stop.
    /// - Throws: any error raised by the context save.
    public func stop(_ session: FocusSession) throws {
        session.stop(at: clock.now())
        try context.save()
    }

    /// Discard a session WITHOUT saving it (ADR-014).
    ///
    /// Deletes the record from the store; the elapsed time is never persisted as a
    /// saved session and never contributes to any per-day total. Safe to call on a
    /// running or a stopped session.
    ///
    /// - Parameter session: the session to discard.
    /// - Throws: any error raised by the context save.
    public func discard(_ session: FocusSession) throws {
        context.delete(session)
        try context.save()
    }

    // MARK: - Live display (ADR-014 / ADR-032)

    /// The live elapsed seconds for the currently-running session, as a single
    /// undivided number `now − startedAt` (ADR-014), or `nil` if none is running.
    ///
    /// Never day-split: even a session that has been running across midnight (or
    /// for more than 24h) reports its continuous total elapsed here (ADR-032 —
    /// the day split is an AGGREGATION concern only, never the live figure).
    /// Derived from `startedAt` so it is correct after an app kill/resume (INV-5).
    ///
    /// - Throws: any error raised by the context fetch.
    public func liveElapsedSeconds() throws -> Int? {
        guard let running = try runningSession() else { return nil }
        return running.duration(now: clock.now())
    }

    /// The single currently-running session, if any (ADR-014). There is at most
    /// one running session at a time in the intended UX, but this simply returns
    /// the earliest-started running record if several exist.
    ///
    /// - Throws: any error raised by the context fetch.
    public func runningSession() throws -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Today's saved sessions (ADR-032 / E3) — consumed by T9 (Timer screen)

    /// The list of today's SAVED (stopped) focus sessions as **WHOLE, unsplit
    /// records**, attributed to a single calendar day by `startedAt`'s day (ADR-032).
    ///
    /// This is the read the Timer screen (T9) shows beneath the live stopwatch. Per
    /// ADR-032's *intentional divergence*: the Timer list attributes each session to
    /// ONE day — the calendar day of its `startedAt` — and shows the record WHOLE
    /// (never split at midnight), whereas the Summary aggregation
    /// (``dailyTotals()``) splits a midnight-spanning session per day. The two views
    /// are consistent-by-design (whole-record vs split), and because the Timer shows
    /// **no summed "today total"** (ADR-032/E3) the divergence never surfaces here as
    /// a contradiction.
    ///
    /// Only STOPPED sessions are returned — a currently-running session is the live
    /// stopwatch, not yet a saved record (ADR-014). Results are newest-first
    /// (`startedAt` descending) so the most recent session leads the list.
    ///
    /// The "today" key is the canonical LOCAL `startOfDay` from the injected clock
    /// (ADR-038), so the attribution join lines up with every other by-day field.
    ///
    /// - Returns: today's stopped sessions, whole records, newest-first.
    /// - Throws: any error raised by the context fetch.
    public func todaysSessions() throws -> [FocusSession] {
        try savedSessions(on: clock.today())
    }

    /// The SAVED (stopped) sessions whose `startedAt` falls on `day`'s calendar day,
    /// as WHOLE records, newest-first (ADR-032 whole-record attribution).
    ///
    /// Split out from ``todaysSessions()`` so a caller (or test) can ask for any
    /// day's saved-session list; `day` is normalised to its canonical `startOfDay`
    /// (ADR-038) before the `[startOfDay, nextMidnight)` `startedAt` window is applied.
    ///
    /// - Parameter day: any instant on the target day; normalised to `startOfDay`.
    /// - Returns: that day's stopped sessions, whole records, newest-first.
    /// - Throws: any error raised by the context fetch.
    public func savedSessions(on day: Date) throws -> [FocusSession] {
        let dayStart = clock.startOfDay(for: day)
        let nextDay = clock.calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        // Whole-record attribution (ADR-032): a session belongs to the calendar day
        // of its `startedAt`, regardless of where `endedAt` lands (even across
        // midnight). Only stopped sessions are saved records.
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate {
                $0.endedAt != nil
                    && $0.startedAt >= dayStart
                    && $0.startedAt < nextDay
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Per-day aggregation (ADR-032) — consumed by T10

    /// Per-day focus totals (whole seconds) over ALL stored, STOPPED sessions,
    /// with each session split at every calendar-day boundary it crosses (ADR-032).
    ///
    /// This is the read-model aggregation the Summary screen (T10) consumes. Each
    /// stored `FocusSession` is one record; here a session's interval is divided at
    /// each local-midnight boundary and each day receives exactly its in-range
    /// portion (portions sum to the session's total duration). A currently-running
    /// (un-stopped) session is EXCLUDED entirely — only saved/stopped sessions
    /// count toward a per-day total (ADR-032).
    ///
    /// Day keys are the canonical LOCAL `startOfDay` `Date` (ADR-038), taken from
    /// the injected clock's calendar so aggregation joins line up with every other
    /// by-day field in the app.
    ///
    /// - Returns: a map from canonical day key → total focus seconds attributed to
    ///   that day. Days with no focus are absent (no zero entries).
    /// - Throws: any error raised by the context fetch.
    public func dailyTotals() throws -> [Date: Int] {
        // Only STOPPED sessions contribute (ADR-032: running sessions excluded).
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt != nil }
        )
        let stopped = try context.fetch(descriptor)
        return FocusSessionService.dailyTotals(of: stopped, calendar: clock.calendar)
    }

    /// Pure per-day aggregation over a supplied set of sessions (ADR-032).
    ///
    /// Split out from ``dailyTotals()`` so callers (and tests) can aggregate an
    /// in-memory collection without a context. Running sessions (`endedAt == nil`)
    /// are skipped; every stopped session is split per calendar day and its
    /// portions are summed into the result.
    ///
    /// - Parameters:
    ///   - sessions: the sessions to aggregate; running ones are ignored.
    ///   - calendar: the calendar whose `startOfDay` defines each day boundary
    ///     (ADR-038).
    /// - Returns: a map from canonical day key → total focus seconds for that day.
    public static func dailyTotals(
        of sessions: [FocusSession],
        calendar: Calendar
    ) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for session in sessions {
            guard let endedAt = session.endedAt else { continue } // running excluded
            let portions = perDayPortions(
                startedAt: session.startedAt,
                endedAt: endedAt,
                calendar: calendar
            )
            for (day, seconds) in portions {
                totals[day, default: 0] += seconds
            }
        }
        return totals
    }

    /// Split a single `[startedAt, endedAt]` interval into its per-calendar-day
    /// portions (ADR-032), the core read-model operation T10 builds on.
    ///
    /// The interval is divided at EACH local-midnight boundary it crosses; every
    /// day the interval overlaps receives exactly the number of whole seconds of
    /// the interval that fall within that day, keyed by the day's canonical
    /// `startOfDay` `Date` (ADR-038). Multi-midnight spans (e.g. a >24h session)
    /// yield one entry per overlapped day. The portions sum to the interval's total
    /// whole-second duration.
    ///
    /// A reversed interval (`endedAt <= startedAt`) yields no portions (INV-5:
    /// never negative). A same-day interval yields a single entry.
    ///
    /// - Parameters:
    ///   - startedAt: interval start.
    ///   - endedAt: interval end.
    ///   - calendar: the calendar whose `startOfDay` defines each boundary.
    /// - Returns: a map from canonical day key → whole seconds in that day.
    public static func perDayPortions(
        startedAt: Date,
        endedAt: Date,
        calendar: Calendar
    ) -> [Date: Int] {
        guard endedAt > startedAt else { return [:] }

        // Attribute whole seconds using a CUMULATIVE floor measured from
        // `startedAt`, so per-day portions always sum to the interval's total
        // `Int(endedAt − startedAt)` even when boundaries do not align to whole
        // seconds from the start (INV-5 / ADR-032: portions sum to the total).
        var portions: [Date: Int] = [:]
        var cursor = startedAt
        var elapsedFloorSoFar = 0

        while cursor < endedAt {
            let dayKey = calendar.startOfDay(for: cursor)
            // Start of the NEXT day; the current day's portion ends at the earlier
            // of that boundary and the interval's end.
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayKey)
                ?? dayKey.addingTimeInterval(86_400)
            let segmentEnd = min(nextDay, endedAt)

            // Cumulative floored elapsed up to this segment's end, minus what
            // earlier segments already claimed, gives this day's whole-second share.
            let cumulativeElapsed = Int(segmentEnd.timeIntervalSince(startedAt))
            let seconds = cumulativeElapsed - elapsedFloorSoFar
            if seconds > 0 {
                portions[dayKey, default: 0] += seconds
                elapsedFloorSoFar = cumulativeElapsed
            }

            // Guard against a non-advancing cursor (e.g. a pathological calendar);
            // always move forward to the next boundary to terminate.
            cursor = segmentEnd > cursor ? segmentEnd : nextDay
        }

        return portions
    }
}
