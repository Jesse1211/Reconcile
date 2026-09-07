import XCTest
import SwiftData
@testable import Reconcile

/// T6 — FocusSession stopwatch service (ADR-014 / ADR-032 / INV-5).
///
/// Covers: start/stop/discard, timestamp-derived elapsed surviving an app kill,
/// multiple independent sessions per day, the live undivided (never day-split)
/// running figure, and the query-time per-day midnight split that T10 consumes —
/// including multi-midnight spans and the running-session exclusion.
final class FocusSessionServiceTests: XCTestCase {

    // MARK: Fixtures

    /// A gregorian calendar pinned to a fixed zone so day keys are deterministic
    /// (ADR-038). Anchored at a LOCAL midnight so day-boundary math is exact.
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

    private func fetchAll(_ context: ModelContext) throws -> [FocusSession] {
        try context.fetch(FetchDescriptor<FocusSession>())
    }

    // MARK: - Start / stop / discard

    func testStartInsertsRunningSession() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let session = try svc.start()

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.startedAt, clock.now())
        XCTAssertEqual(session.accumulatedSeconds, 0, "cache ignored while running (INV-5)")
        XCTAssertEqual(try fetchAll(context).count, 1)
    }

    func testStopSavesSessionAndWritesCacheFromTimestamps() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let session = try svc.start()
        clock.advance(by: 300)
        try svc.stop(session)

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.endedAt, clock.now())
        // Cache written from endedAt − startedAt (ADR-014 E5 / INV-5).
        XCTAssertEqual(session.accumulatedSeconds, 300)

        // The saved record survives a re-fetch from a fresh context handle.
        let refetched = try fetchAll(context)
        XCTAssertEqual(refetched.count, 1)
        XCTAssertEqual(refetched.first?.accumulatedSeconds, 300)
        XCTAssertNotNil(refetched.first?.endedAt)
    }

    func testDiscardDoesNotSaveTheSession() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let session = try svc.start()
        clock.advance(by: 120)
        try svc.discard(session)

        // Discard removes the record entirely — nothing saved, nothing to aggregate.
        XCTAssertEqual(try fetchAll(context).count, 0)
        XCTAssertTrue(try svc.dailyTotals().isEmpty)
    }

    func testStopIsIdempotentThroughService() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let session = try svc.start()
        clock.advance(by: 60)
        try svc.stop(session)
        let end = session.endedAt
        clock.advance(by: 999)
        try svc.stop(session) // no-op on an already-stopped session

        XCTAssertEqual(session.endedAt, end)
        XCTAssertEqual(session.accumulatedSeconds, 60)
    }

    // MARK: - Multiple independent sessions per day (ADR-014)

    func testMultipleIndependentSessionsPerDay() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        // Three separate sessions on the same day, each started + stopped.
        let s1 = try svc.start(); clock.advance(by: 100); try svc.stop(s1)
        clock.advance(by: 50)
        let s2 = try svc.start(); clock.advance(by: 200); try svc.stop(s2)
        clock.advance(by: 50)
        let s3 = try svc.start(); clock.advance(by: 300); try svc.stop(s3)

        XCTAssertEqual(try fetchAll(context).count, 3, "each session is its own record")

        // All fall on the same calendar day → their totals sum on that one day.
        let totals = try svc.dailyTotals()
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.values.first, 600)
    }

    // MARK: - Timestamp elapsed survives app kill (INV-5 / ADR-014)

    func testLiveElapsedRecomputedFromStartedAtAcrossSimulatedKill() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        try svc.start()
        // Simulate the app being killed and relaunched much later: the clock
        // advances while "backgrounded"; elapsed is recomputed from startedAt,
        // NOT frozen at the moment of backgrounding.
        clock.advance(by: 3_600)

        XCTAssertEqual(try svc.liveElapsedSeconds(), 3_600)
    }

    func testLiveElapsedIsUndividedAcrossMidnight() throws {
        // Start 30 minutes before local midnight; run past it (no stop).
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)
        let midnight = clock.calendar.startOfDay(
            for: clock.now().addingTimeInterval(86_400)
        )
        clock.setNow(midnight.addingTimeInterval(-1_800)) // 30 min before midnight

        try svc.start()
        clock.setNow(midnight.addingTimeInterval(1_800)) // 30 min after midnight

        // Live display = now − startedAt, a single undivided number (ADR-032):
        // NOT split into pre/post-midnight portions.
        XCTAssertEqual(try svc.liveElapsedSeconds(), 3_600)
    }

    func testLiveElapsedIsNilWhenNothingRunning() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)
        XCTAssertNil(try svc.liveElapsedSeconds())

        let s = try svc.start(); clock.advance(by: 10); try svc.stop(s)
        XCTAssertNil(try svc.liveElapsedSeconds(), "a stopped session is not running")
    }

    // MARK: - Running session excluded from per-day totals (ADR-032)

    func testRunningSessionExcludedFromDayTotalsUntilStopped() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let running = try svc.start()
        clock.advance(by: 500)

        // A running session contributes NOTHING to any day total (ADR-032).
        XCTAssertTrue(try svc.dailyTotals().isEmpty)

        // Once stopped, it counts.
        try svc.stop(running)
        let totals = try svc.dailyTotals()
        XCTAssertEqual(totals.values.reduce(0, +), 500)
    }

    // MARK: - Midnight split: one stored record, split at query time (ADR-032)

    func testMidnightSpanStoredAsOneRecordSplitAtQueryTime() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let day1 = clock.calendar.startOfDay(for: clock.now())
        let day2 = clock.calendar.date(byAdding: .day, value: 1, to: day1)!
        // Start 40 min before midnight, stop 20 min after: 3600 s total.
        clock.setNow(day2.addingTimeInterval(-2_400))
        let session = try svc.start()
        clock.setNow(day2.addingTimeInterval(1_200))
        try svc.stop(session)

        // Stored as ONE record (never split at storage).
        XCTAssertEqual(try fetchAll(context).count, 1)
        XCTAssertEqual(session.duration(now: clock.now()), 3_600)

        // Per-day aggregation splits it: day1 gets its 2400 s portion, day2 its 1200 s.
        let totals = try svc.dailyTotals()
        XCTAssertEqual(totals[day1], 2_400)
        XCTAssertEqual(totals[day2], 1_200)
        // Portions sum to the total duration.
        XCTAssertEqual(totals.values.reduce(0, +), 3_600)
    }

    // MARK: - Multi-midnight split (ADR-032)

    func testMultiMidnightSpanSplitsAtEachBoundary() throws {
        let clock = pinnedClock()
        let day0 = clock.calendar.startOfDay(for: clock.now())
        // A session running for a bit over 2 days: from noon on day0 to noon on day2.
        let start = day0.addingTimeInterval(43_200)               // day0 12:00
        let end = clock.calendar.date(byAdding: .day, value: 2, to: day0)!
            .addingTimeInterval(43_200)                           // day2 12:00

        let portions = FocusSessionService.perDayPortions(
            startedAt: start, endedAt: end, calendar: clock.calendar
        )
        let day1 = clock.calendar.date(byAdding: .day, value: 1, to: day0)!
        let day2 = clock.calendar.date(byAdding: .day, value: 2, to: day0)!

        // Three overlapped days: half of day0, all of day1, half of day2.
        XCTAssertEqual(portions.count, 3)
        XCTAssertEqual(portions[day0], 43_200)
        XCTAssertEqual(portions[day1], 86_400)
        XCTAssertEqual(portions[day2], 43_200)
        // Portions sum to the full 2-day interval.
        XCTAssertEqual(portions.values.reduce(0, +), Int(end.timeIntervalSince(start)))
    }

    func testSameDayIntervalYieldsSinglePortion() throws {
        let clock = pinnedClock()
        let day0 = clock.calendar.startOfDay(for: clock.now())
        let start = day0.addingTimeInterval(3_600)
        let end = day0.addingTimeInterval(7_200)
        let portions = FocusSessionService.perDayPortions(
            startedAt: start, endedAt: end, calendar: clock.calendar
        )
        XCTAssertEqual(portions, [day0: 3_600])
    }

    func testReversedIntervalYieldsNoPortions() throws {
        let clock = pinnedClock()
        let now = clock.now()
        XCTAssertTrue(
            FocusSessionService.perDayPortions(
                startedAt: now, endedAt: now.addingTimeInterval(-10),
                calendar: clock.calendar
            ).isEmpty
        )
        XCTAssertTrue(
            FocusSessionService.perDayPortions(
                startedAt: now, endedAt: now, calendar: clock.calendar
            ).isEmpty
        )
    }

    // MARK: - Portions sum to total even off whole-second boundaries (INV-5)

    func testPortionsSumToFlooredTotalWithFractionalStart() throws {
        let clock = pinnedClock()
        let day0 = clock.calendar.startOfDay(for: clock.now())
        let day1 = clock.calendar.date(byAdding: .day, value: 1, to: day0)!
        // Start at a fractional second before midnight; end a fractional bit after.
        let start = day1.addingTimeInterval(-100.6)
        let end = day1.addingTimeInterval(100.7)
        let portions = FocusSessionService.perDayPortions(
            startedAt: start, endedAt: end, calendar: clock.calendar
        )
        // Per-day portions must sum to the interval's floored whole-second total,
        // matching FocusSession.duration (a single Int(total) floor).
        let total = Int(end.timeIntervalSince(start))
        XCTAssertEqual(portions.values.reduce(0, +), total)
        XCTAssertEqual(portions.keys.sorted(), [day0, day1])
    }

    // MARK: - dailyTotals joins by canonical day key (ADR-038)

    func testDailyTotalsKeyedByCanonicalDayKey() throws {
        let clock = pinnedClock()
        let context = inMemoryContext()
        let svc = service(clock, context)

        let s = try svc.start(); clock.advance(by: 90); try svc.stop(s)
        let totals = try svc.dailyTotals()
        let key = try XCTUnwrap(totals.keys.first)
        // Every key is a local start-of-day with no time-of-day component (ADR-038).
        XCTAssertEqual(key, clock.calendar.startOfDay(for: key))
    }
}
