import XCTest
import SwiftData
@testable import Reconcile

/// T10 — Summary read-model (ADR-006/-007/-017/-023/-030/-031/-032).
///
/// The Summary screen's numbers must be read-model-consistent with Today's, so these
/// tests assert the SummaryService aggregations against the SAME peer-service queries
/// (MITService / FocusSessionService / DailyFeeling) the rest of the app uses. Covers
/// every T10 acceptance gate: read-model consistency, focus midnight-split with
/// KPI == Σ chart bars (in-range portion only), average-mood-excludes-missing, the
/// per-MIT delete-gap timeline, the open/rolling KPI shared with Today, and the empty
/// state.
final class SummaryServiceTests: XCTestCase {

    // MARK: Fixtures

    /// A gregorian calendar pinned to a fixed zone so day keys are deterministic (ADR-038),
    /// anchored so `now` lands at a clean LOCAL midnight for exact day-boundary math.
    private func pinnedClock(now: TimeInterval = 1_700_010_000) -> TestClock {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let clock = TestClock(now: Date(timeIntervalSince1970: now), calendar: cal)
        // Snap the clock to local midnight so `today()` and offsets are whole days.
        clock.setNow(clock.today())
        return clock
    }

    private func inMemoryContext() -> ModelContext {
        ModelContext(PersistenceController.makeInMemoryContainer())
    }

    private func day(_ clock: TestClock, offset: Int) -> Date {
        clock.calendar.date(byAdding: .day, value: offset, to: clock.today())!
    }

    // MARK: - Empty state (ADR-033)

    func testBrandNewUserHasNoData() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        XCTAssertTrue(try svc.hasNoData(in: ctx))

        // Charts still render an axis: every range yields at least today's (zero) bar.
        let completed = try svc.completedByDay(range: .week, in: ctx)
        XCTAssertFalse(completed.isEmpty)
        XCTAssertTrue(completed.allSatisfy { $0.value == 0 })

        let kpis = try svc.kpis(range: .all, in: ctx)
        XCTAssertEqual(kpis.totalCompleted, 0)
        XCTAssertEqual(kpis.totalFocusSeconds, 0)
        XCTAssertEqual(kpis.openRollingCount, 0)
        XCTAssertNil(kpis.averageMood)
    }

    // MARK: - Read-model consistency (ADR-006/-007/-017)

    /// The Summary chart day-count == MITService's daily count == the KPI component,
    /// all from the SAME `completedOn` query Today uses.
    func testCompletedCountReadModelConsistency() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let mit = MITService(clock: clock)
        let svc = SummaryService(clock: clock)

        // Two MITs completed TODAY.
        let a = mit.create(text: "A", in: ctx)
        let b = mit.create(text: "B", in: ctx)
        try mit.complete(a)
        try mit.complete(b)
        try ctx.save()

        let today = clock.today()
        let serviceCount = try mit.completedCount(on: today, in: ctx)

        let chart = try svc.completedByDay(range: .week, in: ctx)
        let chartToday = chart.first { $0.day == today }?.value

        let kpis = try svc.kpis(range: .week, in: ctx)

        XCTAssertEqual(serviceCount, 2)
        XCTAssertEqual(chartToday, 2, "chart day-count must equal the service query")
        // KPI total == Σ chart bars for the range == service count for the single active day.
        XCTAssertEqual(kpis.totalCompleted, chart.reduce(0) { $0 + $1.value })
        XCTAssertEqual(kpis.totalCompleted, 2)
    }

    /// A MIT completed on day3 counts toward day3, not its created day1 (ADR-006).
    func testCompletedCountsTowardCompletedOnDay() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // Created two days ago, completed today (simulate by stamping fields directly
        // through the service on a clock that has advanced).
        let earlyClock = pinnedClock()
        earlyClock.setNow(day(clock, offset: -2))
        let earlyMit = MITService(clock: earlyClock)
        let m = earlyMit.create(text: "rolled", in: ctx)
        try ctx.save()
        XCTAssertEqual(m.createdOn, day(clock, offset: -2))

        // App-open on today: rollover advances the open past-due MIT into today, making
        // it completable (ADR-005/D2); then complete it today.
        let mit = MITService(clock: clock)
        try mit.rollover(in: ctx)
        try mit.complete(m)
        try ctx.save()

        let chart = try svc.completedByDay(range: .week, in: ctx)
        XCTAssertEqual(chart.first { $0.day == clock.today() }?.value, 1)
        XCTAssertEqual(chart.first { $0.day == day(clock, offset: -2) }?.value, 0,
                       "the created day carries no completion (ADR-006)")
    }

    // MARK: - Open/rolling KPI shared with Today (ADR-017/F8)

    func testOpenRollingKPIEqualsTodayListLength() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let mit = MITService(clock: clock)
        let svc = SummaryService(clock: clock)

        // Two completed + two focus sessions on one day, plus a set of open/rolled MITs.
        let c1 = mit.create(text: "c1", in: ctx); try mit.complete(c1)
        let c2 = mit.create(text: "c2", in: ctx); try mit.complete(c2)
        _ = mit.create(text: "open1", in: ctx)
        _ = mit.create(text: "open2", in: ctx)
        let deleted = mit.create(text: "gone", in: ctx)
        mit.softDelete(deleted) // excluded from open/rolling
        try ctx.save()

        try mit.rollover(in: ctx)
        let todayList = try mit.todaysOpenMITs(in: ctx)
        let kpis = try svc.kpis(range: .all, in: ctx)

        XCTAssertEqual(kpis.openRollingCount, todayList.count,
                       "the open/rolling KPI and Today's list derive from ONE query")
        XCTAssertEqual(kpis.openRollingCount, 2, "two open, deleted excluded")
    }

    // MARK: - Focus midnight-split + KPI == Σ chart bars (ADR-017/-032)

    func testFocusMidnightSplitPerDayAndKPIEqualsBars() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // A session spanning midnight: starts 30 min before today's midnight, ends 30
        // min after — 1800s to yesterday, 1800s to today.
        let midnight = clock.today()
        let session = FocusSession(
            startedAt: midnight.addingTimeInterval(-1800),
            endedAt: midnight.addingTimeInterval(1800)
        )
        session.accumulatedSeconds = 3600
        ctx.insert(session)

        // A running (un-stopped) session — must be excluded from every total.
        let running = FocusSession(startedAt: midnight.addingTimeInterval(600))
        ctx.insert(running)
        try ctx.save()

        // Week range includes both yesterday and today → both portions visible.
        let weekChart = try svc.focusSecondsByDay(range: .week, in: ctx)
        XCTAssertEqual(weekChart.first { $0.day == clock.today() }?.value, 1800)
        XCTAssertEqual(weekChart.first { $0.day == day(clock, offset: -1) }?.value, 1800)
        let weekKPI = try svc.kpis(range: .week, in: ctx)
        XCTAssertEqual(weekKPI.totalFocusSeconds, weekChart.reduce(0) { $0 + $1.value })
        XCTAssertEqual(weekKPI.totalFocusSeconds, 3600, "both in-range portions, running excluded")
    }

    /// A session spanning the RANGE boundary is counted only for its in-range portion,
    /// and KPI == Σ visible chart bars (ADR-017/-032).
    func testRangeBoundarySpanningSessionCountsInRangePortionOnly() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // .week window starts at today-6. Put a session spanning the start boundary:
        // starts 30 min before that boundary's midnight (day -7 portion, OUT of range),
        // ends 30 min after (day -6 portion, IN range).
        let boundary = day(clock, offset: -6) // window.start for .week
        let session = FocusSession(
            startedAt: boundary.addingTimeInterval(-1800),
            endedAt: boundary.addingTimeInterval(1800)
        )
        session.accumulatedSeconds = 3600
        ctx.insert(session)
        try ctx.save()

        let chart = try svc.focusSecondsByDay(range: .week, in: ctx)
        let kpis = try svc.kpis(range: .week, in: ctx)

        // Only the in-range (day -6) portion is visible and counted.
        XCTAssertEqual(chart.first { $0.day == boundary }?.value, 1800)
        XCTAssertEqual(kpis.totalFocusSeconds, chart.reduce(0) { $0 + $1.value })
        XCTAssertEqual(kpis.totalFocusSeconds, 1800,
                       "the out-of-range portion is excluded from both chart and KPI")
    }

    func testMultiMidnightSplitSumsToTotal() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // A >24h session across 3 calendar days, all in the week range.
        let start = day(clock, offset: -2).addingTimeInterval(3600) // 01:00 on day -2
        let end = clock.today().addingTimeInterval(3600)            // 01:00 today
        let session = FocusSession(startedAt: start, endedAt: end)
        session.accumulatedSeconds = session.duration(now: end)
        ctx.insert(session)
        try ctx.save()

        let chart = try svc.focusSecondsByDay(range: .week, in: ctx)
        let sumBars = chart.reduce(0) { $0 + $1.value }
        XCTAssertEqual(sumBars, Int(end.timeIntervalSince(start)),
                       "per-day portions sum to the total duration (ADR-032)")
        // Three days receive a portion.
        XCTAssertEqual(chart.filter { $0.value > 0 }.count, 3)
    }

    // MARK: - Average mood excludes missing days (ADR-031)

    func testAverageMoodExcludesMissingDaysAndTrendShowsGaps() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // Feelings on 3 of 5 days: today (4), day-1 (2), day-3 (0); day-2 and day-4 none.
        _ = try DailyFeeling.upsert(day: clock.today(), mood: 4, stress: 1, whyText: nil, in: ctx)
        _ = try DailyFeeling.upsert(day: day(clock, offset: -1), mood: 2, stress: 3, whyText: nil, in: ctx)
        _ = try DailyFeeling.upsert(day: day(clock, offset: -3), mood: 0, stress: 5, whyText: nil, in: ctx)
        try ctx.save()

        let avg = try svc.averageMood(range: .week, in: ctx)
        XCTAssertEqual(avg!, (4.0 + 2.0 + 0.0) / 3.0, accuracy: 1e-9,
                       "mean over ONLY days with an entry (ADR-031)")

        let trend = try svc.moodTrend(range: .week, in: ctx)
        // Days without a feeling render nil (a gap), not 0.
        XCTAssertNil(trend.first { $0.day == day(clock, offset: -2) }?.mood)
        XCTAssertNil(trend.first { $0.day == day(clock, offset: -4) }?.mood)
        XCTAssertEqual(trend.first { $0.day == clock.today() }?.mood, 4)
        XCTAssertEqual(trend.first { $0.day == day(clock, offset: -1) }?.stress, 3)

        // KPI mirrors the exclusion.
        XCTAssertEqual(try svc.kpis(range: .week, in: ctx).averageMood!, 2.0, accuracy: 1e-9)
    }

    // MARK: - Per-MIT timeline delete-gap (ADR-007/-030)

    func testTimelineRendersDeleteGapAndPreservesOrigin() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        // Created day -4, currently soft-deleted at day -2.
        let earlyClock = pinnedClock(); earlyClock.setNow(day(clock, offset: -4))
        let earlyMit = MITService(clock: earlyClock)
        let m = earlyMit.create(text: "long liver", in: ctx)
        try ctx.save()

        // Soft-delete at day -2.
        let delClock = pinnedClock(); delClock.setNow(day(clock, offset: -2).addingTimeInterval(3600))
        MITService(clock: delClock).softDelete(m)
        try ctx.save()

        let rows = try svc.timeline(range: .month, in: ctx)
        let row = try XCTUnwrap(rows.first { $0.id == m.id })

        XCTAssertEqual(row.createdOn, day(clock, offset: -4), "origin preserved (ADR-030)")
        XCTAssertTrue(row.isDeleted)
        // A live segment then a muted GAP segment (not one continuous rolling bar).
        XCTAssertEqual(row.segments.count, 2)
        XCTAssertFalse(row.segments[0].isGap)
        XCTAssertTrue(row.segments[1].isGap, "the deleted stretch is a GAP (ADR-007)")
        XCTAssertEqual(row.segments[1].start, day(clock, offset: -2))
    }

    func testTimelineOpenMITSpansToToday() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        let earlyClock = pinnedClock(); earlyClock.setNow(day(clock, offset: -3))
        let m = MITService(clock: earlyClock).create(text: "still open", in: ctx)
        try ctx.save()

        let rows = try svc.timeline(range: .week, in: ctx)
        let row = try XCTUnwrap(rows.first { $0.id == m.id })
        XCTAssertEqual(row.createdOn, day(clock, offset: -3))
        XCTAssertEqual(row.endOn, clock.today())
        XCTAssertEqual(row.daysRolled, 3)
        XCTAssertEqual(row.segments.count, 1)
        XCTAssertFalse(row.segments[0].isGap)
    }

    // MARK: - Range switcher changes the aggregation window (ADR-017)

    func testRangeSwitcherChangesWindow() throws {
        let clock = pinnedClock()
        let ctx = inMemoryContext()
        let svc = SummaryService(clock: clock)

        XCTAssertEqual(try svc.completedByDay(range: .week, in: ctx).count, 7)
        XCTAssertEqual(try svc.completedByDay(range: .month, in: ctx).count, 30)

        // A completion 10 days ago is OUT of the week window but IN the month window.
        let earlyClock = pinnedClock(); earlyClock.setNow(day(clock, offset: -10))
        let em = earlyClock.today()
        let m = MITService(clock: earlyClock).create(text: "old", in: ctx)
        try m.markCompleted(on: em)
        try ctx.save()

        XCTAssertEqual(try svc.kpis(range: .week, in: ctx).totalCompleted, 0)
        XCTAssertEqual(try svc.kpis(range: .month, in: ctx).totalCompleted, 1)
        XCTAssertEqual(try svc.kpis(range: .all, in: ctx).totalCompleted, 1)
    }
}
