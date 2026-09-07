import XCTest
import SwiftUI
import SwiftData
@testable import Reconcile

/// T9 — Timer screen (ADR-014 / ADR-032 / ADR-033).
///
/// The Timer screen's load-bearing logic is the **today's-saved-sessions** read
/// (whole records attributed by `startedAt`'s calendar day) and the ADR-032
/// *intentional divergence* between that whole-record list and Summary's split
/// aggregation. These tests pin that read via the T6 service, the ADR-032/E3
/// "no summed today total" contract, and the live-elapsed formatting.
final class TimerScreenTests: XCTestCase {

    // MARK: Fixtures

    /// A gregorian calendar pinned to a fixed zone so day keys are deterministic
    /// (ADR-038), anchored so `now` sits mid-afternoon on a known local day.
    private func pinnedClock(now: TimeInterval = 1_700_000_000) -> TestClock {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return TestClock(now: Date(timeIntervalSince1970: now), calendar: cal)
    }

    private func inMemoryContext() -> ModelContext {
        ModelContext(PersistenceController.makeInMemoryContainer())
    }

    private func service(_ clock: Clock, _ context: ModelContext) -> FocusSessionService {
        FocusSessionService(context: context, clock: clock)
    }

    // MARK: - Today's saved sessions: whole records, newest-first (ADR-032)

    func testTodaysSessionsReturnsStoppedSessionsNewestFirst() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // First session: 10:00 for 5 min.
        let first = try svc.start()
        first.startedAt = clock.today().addingTimeInterval(10 * 3600)
        first.stop(at: first.startedAt.addingTimeInterval(300))
        try context.save()

        // Second session: 14:00 for 20 min (newer startedAt).
        let second = try svc.start()
        second.startedAt = clock.today().addingTimeInterval(14 * 3600)
        second.stop(at: second.startedAt.addingTimeInterval(1200))
        try context.save()

        let list = try svc.todaysSessions()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.id, second.id, "newest startedAt leads (descending)")
        XCTAssertEqual(list.last?.id, first.id)
    }

    func testTodaysSessionsExcludesRunningSession() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // A saved session today.
        let saved = try svc.start()
        clock.advance(by: 600)
        try svc.stop(saved)

        // A currently-running session (endedAt == nil) — not yet a saved record.
        _ = try svc.start()

        let list = try svc.todaysSessions()
        XCTAssertEqual(list.count, 1, "running session is the live stopwatch, not a saved record")
        XCTAssertEqual(list.first?.id, saved.id)
    }

    func testTodaysSessionsExcludesYesterdaysSessions() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // Yesterday's saved session (startedAt on the previous calendar day).
        let yesterday = FocusSession(startedAt: clock.today().addingTimeInterval(-3600))
        yesterday.stop(at: clock.today().addingTimeInterval(-3000))
        context.insert(yesterday)
        try context.save()

        // Today's saved session.
        let today = try svc.start()
        clock.advance(by: 300)
        try svc.stop(today)

        let list = try svc.todaysSessions()
        XCTAssertEqual(list.map(\.id), [today.id], "only startedAt-today sessions appear")
    }

    // MARK: - ADR-032 whole-record vs split divergence (intentional)

    /// A midnight-spanning session appears WHOLE in T9's `startedAt`-day list, yet is
    /// split across two days in Summary's per-day aggregation — consistent-by-design.
    func testMidnightSpanningSessionWholeInTimerListButSplitInSummary() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // Session started 23:30 today, ended 00:30 the next calendar day (1h total).
        let day1 = clock.today()
        let startedAt = day1.addingTimeInterval(23 * 3600 + 30 * 60) // 23:30 day1
        let endedAt = startedAt.addingTimeInterval(3600)             // 00:30 day2
        let session = FocusSession(startedAt: startedAt)
        session.stop(at: endedAt)
        context.insert(session)
        try context.save()

        // T9: WHOLE record, attributed to day1 by startedAt; whole duration = 3600s.
        let timerList = try svc.savedSessions(on: day1)
        XCTAssertEqual(timerList.map(\.id), [session.id], "whole record on startedAt's day")
        XCTAssertEqual(timerList.first?.duration(now: clock.now()), 3600,
                       "Timer shows the WHOLE undivided duration (never day-split, ADR-032)")

        // It does NOT appear on day2's Timer list (whole-record attribution).
        let day2 = clock.calendar.date(byAdding: .day, value: 1, to: day1)!
        XCTAssertTrue(try svc.savedSessions(on: day2).isEmpty,
                      "the whole record is attributed to day1 only, not day2")

        // Summary: SPLIT into day1 + day2 portions summing to the total (ADR-032).
        let totals = try svc.dailyTotals()
        XCTAssertEqual(totals[day1], 1800, "day1 gets the 23:30→24:00 portion")
        XCTAssertEqual(totals[day2], 1800, "day2 gets the 24:00→00:30 portion")
        XCTAssertEqual((totals[day1] ?? 0) + (totals[day2] ?? 0), 3600,
                       "split portions sum to the whole (consistent-by-design)")
    }

    // MARK: - ADR-032 / E3: NO summed "today total" surfaces on the Timer

    /// The Timer screen exposes NO per-day focus sum. The service read the screen uses
    /// (`todaysSessions`) returns whole RECORDS, never a summed figure; the screen's
    /// only formatter (`formatElapsed`) is a single-figure formatter. This structural
    /// contract is what keeps the whole-record-vs-split divergence off the Timer.
    func testTimerReadReturnsRecordsNotASummedTotal() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // Two saved sessions today (5 min + 20 min); the Timer must NOT sum them.
        let a = try svc.start(); clock.advance(by: 300); try svc.stop(a)
        let b = try svc.start(); clock.advance(by: 1200); try svc.stop(b)

        let list = try svc.todaysSessions()
        // The screen renders these as individual rows; there is no "today total" API
        // on the read model — the sum (1500s) lives only on Summary (ADR-017).
        XCTAssertEqual(list.count, 2)
        let perRecord = list.map { $0.duration(now: clock.now()) }.sorted()
        XCTAssertEqual(perRecord, [300, 1200], "individual whole-record durations, never pre-summed")
    }

    // MARK: - Live elapsed formatting (single undivided figure, ADR-014)

    func testFormatElapsedShowsMinutesSecondsUnderAnHour() {
        XCTAssertEqual(TimerScreen.formatElapsed(0), "0:00")
        XCTAssertEqual(TimerScreen.formatElapsed(65), "1:05")
        XCTAssertEqual(TimerScreen.formatElapsed(599), "9:59")
    }

    func testFormatElapsedShowsHoursWhenPresentAcrossMidnight() {
        // A >24h running session shows continuous elapsed, NOT day-split (ADR-032).
        XCTAssertEqual(TimerScreen.formatElapsed(3661), "1:01:01")
        XCTAssertEqual(TimerScreen.formatElapsed(25 * 3600 + 62), "25:01:02")
    }

    func testFormatElapsedClampsNegativeToZero() {
        XCTAssertEqual(TimerScreen.formatElapsed(-10), "0:00", "never negative (INV-5)")
    }

    // MARK: - Empty state exists in both themes (ADR-033 / ADR-022)

    /// The Timer screen resolves its tokens for BOTH themes at `screenRole = .timer`
    /// so its empty/populated states render themed under Ledger and Day Arc (ADR-022).
    /// (The empty-state COPY lives in the screen; here we assert the token vocabulary
    /// the screen reads is total in both themes at the timer role.)
    func testTimerRoleTokensResolveInBothThemes() {
        for theme in Theme.allCases {
            let tokens = theme.tokens(for: .timer)
            XCTAssertEqual(tokens.screenRole, .timer)
            XCTAssertEqual(tokens.theme, theme)
            // Reading the roles the screen uses must not trap.
            _ = tokens.colors.textPrimary
            _ = tokens.colors.textSecondary
            _ = tokens.colors.textMuted
            _ = tokens.colors.surface
            _ = tokens.colors.surfaceRaised
            _ = tokens.colors.accent
            _ = tokens.colors.accentCarried
            _ = tokens.typography.display
            _ = tokens.typography.title
            _ = tokens.typography.body
            _ = tokens.typography.mono
            _ = tokens.typography.eyebrow
        }
    }
}
