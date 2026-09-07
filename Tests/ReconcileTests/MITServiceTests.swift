import XCTest
import SwiftData
@testable import Reconcile

/// T4 service tests: create / edit / complete / rollover / soft-delete + daily-stat.
///
/// Covers the T4 acceptance gate: no-cap create (ADR-003), rollover-before-lock
/// ordering (ADR-005/D2), same-day un-complete bookkeeping (ADR-004/D1), cross-day
/// lock (INV-3/ADR-004), daily stat by `completedOn` (ADR-006), soft-delete stops
/// rollover (ADR-029), cross-midnight undo into today (ADR-030), and read-model
/// consistency (ADR-006/-017).
final class MITServiceTests: XCTestCase {

    // MARK: Fixtures

    /// A gregorian calendar pinned to a fixed zone so day keys are deterministic (ADR-038).
    private func pinnedClock(now: TimeInterval = 1_700_000_000) -> TestClock {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return TestClock(now: Date(timeIntervalSince1970: now), calendar: cal)
    }

    private func inMemoryContext() -> ModelContext {
        ModelContext(PersistenceController.makeInMemoryContainer())
    }

    /// A REAL on-disk SwiftData store in a unique temp dir, for the REAL_STACK_GATE.
    /// Returns the context plus a teardown that deletes the store file.
    ///
    /// Blind spots (declared): only Clock-SIMULATED day boundaries are exercised —
    /// real wall-clock midnight and OS-level date changes are NOT tested here;
    /// backward clock changes are out of scope (ADR-005 does not correct them).
    private func onDiskContext() throws -> (ModelContext, () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("t4-realstack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Reconcile.store")
        let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
        let container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        let teardown: () -> Void = { _ = try? FileManager.default.removeItem(at: dir) }
        return (ModelContext(container), teardown)
    }

    /// Advance a TestClock by whole local days (keeps day keys clean across DST-free zone).
    private func advanceDays(_ clock: TestClock, _ days: Int) {
        clock.advance(by: Double(days) * 86_400)
    }

    // MARK: Happy path — create → complete → count == 1

    func testCreateThenCompleteYieldsDailyCountOne() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Ship T4", in: ctx)
        try ctx.save()
        XCTAssertEqual(mit.appearsOn, clock.today())
        XCTAssertEqual(mit.createdOn, clock.today())

        try service.complete(mit)
        try ctx.save()

        XCTAssertEqual(mit.completedOn, clock.today())
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 1)
    }

    // MARK: No MIT cap (ADR-003)

    func testNoCapOnMITsPerDay() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        for i in 0..<5 {
            service.create(text: "MIT \(i)", in: ctx)
        }
        try ctx.save()

        try service.rollover(in: ctx)
        let today = try service.todaysOpenMITs(in: ctx)
        XCTAssertEqual(today.count, 5, "ADR-003: no upper cap; all 5 coexist today")
    }

    // MARK: Rollover (INV-2/ADR-005) — same record advances; completed does not

    func testOpenMITRollsForwardSameRecord() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Roll me", in: ctx)
        let originalId = mit.id
        let yesterday = mit.appearsOn
        try ctx.save()

        advanceDays(clock, 1)
        let rolled = try service.rollover(in: ctx)

        XCTAssertEqual(rolled.count, 1)
        XCTAssertEqual(rolled.first?.id, originalId, "same record advances, not a copy")
        XCTAssertEqual(mit.appearsOn, clock.today())
        XCTAssertNotEqual(mit.appearsOn, yesterday)

        // Exactly one record still — not a per-day copy.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MIT>()).count, 1)
    }

    func testCompletedMITDoesNotRoll() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Done", in: ctx)
        try service.complete(mit)
        let completionDay = mit.appearsOn
        try ctx.save()

        advanceDays(clock, 1)
        let rolled = try service.rollover(in: ctx)

        XCTAssertTrue(rolled.isEmpty, "INV-2: completed MITs are terminal, never roll")
        XCTAssertEqual(mit.appearsOn, completionDay)
    }

    // MARK: Rollover-before-lock ordering (ADR-005/D2)

    func testOpenPastDueMITAdvancedNotFrozen() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // appearsOn = day1
        let mit = service.create(text: "Two days stale", in: ctx)
        try ctx.save()

        // Clock -> day3 (two days later)
        advanceDays(clock, 2)
        try service.rollover(in: ctx)

        XCTAssertEqual(mit.appearsOn, clock.today(), "advanced to today (day3)")
        XCTAssertTrue(service.isMutable(mit), "must NOT be frozen by the cross-day lock")

        // Edit succeeds — the record is editable, not locked.
        XCTAssertNoThrow(try service.edit(mit, text: "Edited today"))
        XCTAssertEqual(mit.text, "Edited today")
    }

    // MARK: Same-day un-complete clears completedOn (ADR-004/D1)

    func testSameDayFlipCompletedToOpenClearsCompletedOnAndCount() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Flip", in: ctx)
        try service.complete(mit)
        try ctx.save()
        XCTAssertEqual(mit.completedOn, clock.today())
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 1)

        // Same-day flip completed -> open
        try service.reopen(mit)
        try ctx.save()
        XCTAssertEqual(mit.status, .open)
        XCTAssertNil(mit.completedOn, "ADR-004/D1: flip clears completedOn")
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 0,
                       "count decremented, never over-counts a re-opened MIT")
    }

    func testToggleCompletionRoundTrip() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Toggle", in: ctx)
        try service.toggleCompletion(mit)
        XCTAssertEqual(mit.status, .completed)
        try service.toggleCompletion(mit)
        XCTAssertEqual(mit.status, .open)
        XCTAssertNil(mit.completedOn)
    }

    // MARK: Multi-day roll — appears once, one record

    func testMultiDayRollAppearsOnceAsOneRecord() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        service.create(text: "Persistent", in: ctx)
        try ctx.save()

        for _ in 0..<3 {
            advanceDays(clock, 1)
            try service.rollover(in: ctx)
        }

        let today = try service.todaysOpenMITs(in: ctx)
        XCTAssertEqual(today.count, 1, "appears exactly once")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MIT>()).count, 1, "one record, not three")
        XCTAssertEqual(today.first?.appearsOn, clock.today())
    }

    // MARK: Cross-day lock (INV-3/ADR-004)

    func testCrossDayEditRejectedSameDayAllowed() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // A COMPLETED MIT stays terminal and does not roll — so next day it locks.
        let mit = service.create(text: "Yesterday", in: ctx)
        try service.complete(mit)
        try ctx.save()

        // Same-day flip is allowed.
        XCTAssertNoThrow(try service.reopen(mit))
        try service.complete(mit)

        // Next day: rollover leaves the completed one historical -> locked.
        advanceDays(clock, 1)
        try service.rollover(in: ctx)

        XCTAssertFalse(service.isMutable(mit))
        XCTAssertThrowsError(try service.edit(mit, text: "sneaky")) { error in
            guard case MITService.ServiceError.historicalRecordIsReadOnly = error else {
                return XCTFail("expected historicalRecordIsReadOnly, got \(error)")
            }
        }
        XCTAssertThrowsError(try service.reopen(mit), "status flip also locked cross-day")
        XCTAssertEqual(mit.text, "Yesterday", "rejected edit never mutates")
    }

    // MARK: Daily stat (ADR-006) — counts toward completedOn day, not created day

    func testCompletedCountsTowardCompletedOnDayNotCreatedDay() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // Created day1
        let mit = service.create(text: "Long haul", in: ctx)
        let day1 = clock.today()
        try ctx.save()

        // Roll to day3, then complete on day3
        advanceDays(clock, 2)
        try service.rollover(in: ctx)
        let day3 = clock.today()
        try service.complete(mit)
        try ctx.save()

        XCTAssertEqual(try service.completedCount(on: day3, in: ctx), 1, "counts on completedOn day")
        XCTAssertEqual(try service.completedCount(on: day1, in: ctx), 0, "not on created day")
        XCTAssertEqual(mit.completedOn, day3)
    }

    // MARK: Soft delete (INV-6/ADR-008)

    func testSoftDeleteLeavesListRetainedExcludedFromStatsUndoRestores() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Trash me", in: ctx)
        try service.complete(mit)
        try ctx.save()
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 1)

        service.softDelete(mit)
        try ctx.save()
        XCTAssertTrue(mit.isDeleted)
        XCTAssertNotNil(mit.deletedAt)
        // Retained in DB.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MIT>()).count, 1)
        // Excluded from stats.
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 0)

        // Undo restores (same day: completed MIT keeps its completedOn).
        service.undoDelete(mit)
        try ctx.save()
        XCTAssertFalse(mit.isDeleted)
        XCTAssertNil(mit.deletedAt)
        XCTAssertEqual(try service.completedCount(on: clock.today(), in: ctx), 1)
    }

    // MARK: Soft-delete stops rollover (ADR-029)

    func testSoftDeleteStopsRollover() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let mit = service.create(text: "Deleted open", in: ctx)
        let day1AppearsOn = mit.appearsOn
        service.softDelete(mit)
        try ctx.save()

        advanceDays(clock, 1)
        let rolled = try service.rollover(in: ctx)

        XCTAssertTrue(rolled.isEmpty, "ADR-029: soft-deleted MIT is gated out of rollover")
        XCTAssertEqual(mit.appearsOn, day1AppearsOn, "appearsOn did NOT advance")
        let today = try service.todaysOpenMITs(in: ctx)
        XCTAssertTrue(today.isEmpty, "absent from today's list")
    }

    // MARK: Cross-midnight undo restores into today (ADR-030)

    func testCrossMidnightUndoRestoresIntoTodayPreservingCreatedOn() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // Create + delete on day1 (open MIT)
        let mit = service.create(text: "Reborn today", in: ctx)
        let createdOnDay1 = mit.createdOn
        service.softDelete(mit)
        try ctx.save()

        // Clock -> day2, then undo
        advanceDays(clock, 1)
        let day2 = clock.today()
        service.undoDelete(mit)
        try ctx.save()

        XCTAssertEqual(mit.appearsOn, day2, "ADR-030: restored INTO today, not the locked prior day")
        XCTAssertEqual(mit.createdOn, createdOnDay1, "ADR-030: createdOn PRESERVED")
        XCTAssertFalse(mit.isDeleted)
        XCTAssertNil(mit.deletedAt)
        XCTAssertNotEqual(mit.appearsOn, mit.createdOn, "born day1, appears day2")

        // It re-enters today's list and is editable (not frozen into the locked day).
        XCTAssertTrue(service.isMutable(mit))
        let today = try service.todaysOpenMITs(in: ctx)
        XCTAssertEqual(today.map(\.id), [mit.id])
    }

    // MARK: Read-model consistency (ADR-006/-007/-017)

    func testHistoryCountEqualsTodayCompletedCount() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        let a = service.create(text: "A", in: ctx)
        let b = service.create(text: "B", in: ctx)
        service.create(text: "C-open", in: ctx)
        try service.complete(a)
        try service.complete(b)
        try ctx.save()

        let historyDailyCount = try service.completedCount(on: clock.today(), in: ctx)
        let todayCompletedCount = try service.completedMITs(on: clock.today(), in: ctx).count
        XCTAssertEqual(historyDailyCount, todayCompletedCount)
        XCTAssertEqual(historyDailyCount, 2)
    }

    func testOpenRollingCountMatchesTodayListLength() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // 2 completed + 2 open, all today.
        let c1 = service.create(text: "c1", in: ctx)
        let c2 = service.create(text: "c2", in: ctx)
        service.create(text: "o1", in: ctx)
        service.create(text: "o2", in: ctx)
        try service.complete(c1)
        try service.complete(c2)
        try ctx.save()

        try service.rollover(in: ctx)
        let todayList = try service.todaysOpenMITs(in: ctx)
        let kpi = try service.openRollingCount(in: ctx)
        XCTAssertEqual(todayList.count, kpi, "ADR-017: shared predicate")
        XCTAssertEqual(kpi, 2)
    }

    // MARK: REAL_STACK_GATE — rollover + daily-stat on a real on-disk store

    /// Exercises rollover and daily-stat across Clock-simulated day boundaries
    /// against a REAL on-disk SwiftData store (not in-memory), re-opening the
    /// context between "app opens" to prove persistence survives.
    ///
    /// Blind spots: real wall-clock midnight is not tested (only Clock-simulated);
    /// backward clock changes are out of scope (ADR-005).
    func testRealStackRolloverAndDailyStatAcrossDayBoundaries() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let (ctx, teardown) = try onDiskContext()
        defer { teardown() }

        // Day1: create an open MIT + a to-be-completed one, persist to disk.
        let roller = service.create(text: "rolls", in: ctx)
        let rollerId = roller.id
        let doneToday = service.create(text: "done day1", in: ctx)
        try service.complete(doneToday)
        try ctx.save()
        let day1 = clock.today()
        XCTAssertEqual(try service.completedCount(on: day1, in: ctx), 1)

        // --- App open on day2 (real store, fresh fetch) ---
        advanceDays(clock, 1)
        let day2 = clock.today()
        let rolled = try service.rollover(in: ctx)
        try ctx.save()
        XCTAssertEqual(rolled.map(\.id), [rollerId], "open MIT advanced on-disk")

        // Re-fetch from the SAME on-disk store: appearsOn persisted as day2.
        let refetched = try ctx.fetch(FetchDescriptor<MIT>(
            predicate: #Predicate { $0.id == rollerId }
        )).first
        XCTAssertEqual(refetched?.appearsOn, day2)

        // Complete the roller on day2; daily stat now attributes it to day2, not day1.
        try service.complete(roller)
        try ctx.save()
        XCTAssertEqual(try service.completedCount(on: day2, in: ctx), 1)
        XCTAssertEqual(try service.completedCount(on: day1, in: ctx), 1,
                       "day1's own completion is unchanged and still on disk")

        // The completed day1 MIT did NOT roll (still historical).
        let doneTodayId = doneToday.id
        let day1DoneRefetched = try ctx.fetch(FetchDescriptor<MIT>(
            predicate: #Predicate { $0.id == doneTodayId }
        )).first
        XCTAssertEqual(day1DoneRefetched?.appearsOn, day1)
    }

    func testOpenRollingCountIgnoresAppearsOnAndExcludesDeleted() throws {
        let clock = pinnedClock()
        let service = MITService(clock: clock)
        let ctx = inMemoryContext()

        // An open MIT left un-rolled (appearsOn in the past) still counts toward
        // open/rolling (ADR-017: regardless of appearsOn).
        let stale = service.create(text: "stale open", in: ctx)
        advanceDays(clock, 1)
        _ = stale // appearsOn is yesterday; we deliberately do NOT roll yet.

        let deleted = service.create(text: "deleted", in: ctx)
        service.softDelete(deleted)
        try ctx.save()

        // Before rollover: stale-open counts; deleted excluded.
        XCTAssertEqual(try service.openRollingCount(in: ctx), 1)
    }
}
