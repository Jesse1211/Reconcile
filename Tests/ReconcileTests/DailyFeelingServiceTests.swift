import XCTest
import SwiftData
@testable import Reconcile

/// T11 service tests: DailyFeeling capture/persistence.
///
/// Covers the T11 acceptance gate:
///   * One-per-day upsert (INV-7 / ADR-020) — two saves the same day → ONE row.
///   * Scale validation — 0 and 5 accepted, -1 and 6 rejected; nil `why` accepted.
///   * Cross-day lock (INV-8) — editing a feeling whose day has rolled is
///     rejected; a same-day edit succeeds.
///   * REAL_STACK_GATE — today's feeling upserts to a real on-disk store and
///     reloads with mood/stress/why intact.
final class DailyFeelingServiceTests: XCTestCase {

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

    // MARK: One-per-day (INV-7 / ADR-020)

    func testSaveTwiceSameDayYieldsOneRow() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        try service.saveToday(mood: 3, stress: 2, whyText: "first", in: context)
        try service.saveToday(mood: 5, stress: 1, whyText: "second", in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(all.count, 1, "INV-7: exactly one DailyFeeling per local day (upsert)")
        XCTAssertEqual(all.first?.mood, 5)
        XCTAssertEqual(all.first?.stress, 1)
        XCTAssertEqual(all.first?.whyText, "second")
        // The single row IS today's row.
        XCTAssertEqual(all.first?.day, clock.today())
    }

    func testSaveOnDistinctDaysCreatesDistinctRows() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        try service.saveToday(mood: 1, stress: 1, whyText: nil, in: context)
        clock.advance(by: 86_400) // roll to the next local day
        try service.saveToday(mood: 2, stress: 2, whyText: nil, in: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyFeeling>()).count, 2)
    }

    // MARK: Scale validation (mood/stress in 0...5 required; why optional)

    func testBoundaryScalesAcceptedAndNilWhyAllowed() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        let f = try service.saveToday(mood: 0, stress: 5, whyText: nil, in: context)
        try context.save()

        XCTAssertEqual(f.mood, 0)
        XCTAssertEqual(f.stress, 5)
        XCTAssertNil(f.whyText, "why is optional — a nil why is a valid save")
    }

    func testOutOfRangeScalesRejected() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        XCTAssertThrowsError(
            try service.saveToday(mood: -1, stress: 3, whyText: nil, in: context)
        ) { error in
            XCTAssertEqual(error as? DailyFeeling.InvariantError, .moodOutOfRange(-1))
        }
        XCTAssertThrowsError(
            try service.saveToday(mood: 3, stress: 6, whyText: nil, in: context)
        ) { error in
            XCTAssertEqual(error as? DailyFeeling.InvariantError, .stressOutOfRange(6))
        }

        // A rejected save leaves the store empty — nothing partial was inserted.
        XCTAssertTrue(try context.fetch(FetchDescriptor<DailyFeeling>()).isEmpty)
    }

    func testRejectedResaveLeavesExistingRowUntouched() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        try service.saveToday(mood: 3, stress: 3, whyText: "ok", in: context)
        try context.save()

        XCTAssertThrowsError(
            try service.saveToday(mood: 9, stress: 3, whyText: "bad", in: context)
        )
        let all = try context.fetch(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.mood, 3)
        XCTAssertEqual(all.first?.whyText, "ok")
    }

    // MARK: Fetch-or-create today

    func testTodaysFeelingIsNilBeforeAnySave() throws {
        let context = inMemoryContext()
        let service = DailyFeelingService(clock: pinnedClock())
        XCTAssertNil(try service.todaysFeeling(in: context))
    }

    func testFetchOrCreateTodayMaterializesThenReturnsSameRow() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        let created = try service.fetchOrCreateToday(in: context)
        try context.save()
        XCTAssertEqual(created.day, clock.today())

        // A second call returns the SAME row, not a new one (one-per-day).
        let again = try service.fetchOrCreateToday(in: context)
        XCTAssertEqual(again.id, created.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyFeeling>()).count, 1)

        // todaysFeeling now finds it.
        XCTAssertEqual(try service.todaysFeeling(in: context)?.id, created.id)
    }

    // MARK: Cross-day lock (INV-8)

    func testSameDayEditSucceeds() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        let day = clock.today()
        try service.saveToday(mood: 2, stress: 2, whyText: "am", in: context)
        try context.save()

        // Same day, explicit-day guarded save: succeeds.
        try service.save(day: day, mood: 4, stress: 1, whyText: "pm", in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.mood, 4)
        XCTAssertEqual(all.first?.whyText, "pm")
        XCTAssertTrue(service.isEditable(day: day))
    }

    func testCrossDaySaveIsRejected() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        // Record day1's feeling.
        let day1 = clock.today()
        try service.saveToday(mood: 3, stress: 3, whyText: "day1", in: context)
        try context.save()

        // Roll the clock to the next local day.
        clock.advance(by: 86_400)
        let today2 = clock.today()
        XCTAssertNotEqual(day1, today2)

        // INV-8: editing day1 (now historical) via the guarded save is REJECTED.
        XCTAssertThrowsError(
            try service.save(day: day1, mood: 0, stress: 0, whyText: "tamper", in: context)
        ) { error in
            XCTAssertEqual(
                error as? DailyFeelingService.ServiceError,
                .crossDayLocked(day: day1, today: today2)
            )
        }

        // day1's row is UNCHANGED — the lock left the store untouched.
        let day1Row = try DailyFeeling.fetch(day: day1, in: context)
        XCTAssertEqual(day1Row?.mood, 3)
        XCTAssertEqual(day1Row?.whyText, "day1")
        XCTAssertFalse(service.isEditable(day: day1), "a rolled day is read-only (INV-8)")
    }

    func testCrossDayEditOfFetchedEntryIsRejected() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        try service.saveToday(mood: 3, stress: 3, whyText: "day1", in: context)
        try context.save()
        let entry = try XCTUnwrap(try service.todaysFeeling(in: context))

        // Roll to the next day: the fetched entry is now historical.
        clock.advance(by: 86_400)
        XCTAssertThrowsError(
            try service.edit(entry, mood: 1, stress: 1, whyText: "tamper")
        ) { error in
            guard case DailyFeelingService.ServiceError.crossDayLocked = error else {
                return XCTFail("expected crossDayLocked, got \(error)")
            }
        }
        // The rejected edit did not mutate the row.
        XCTAssertEqual(entry.mood, 3)
        XCTAssertEqual(entry.whyText, "day1")
    }

    func testTimeOfDayDoesNotDefeatCrossDayLock() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let service = DailyFeelingService(clock: clock)

        // A "day" carrying a time-of-day component from a rolled day is still
        // normalized to its startOfDay and rejected (ADR-038 + INV-8).
        let day1 = clock.today()
        try service.saveToday(mood: 3, stress: 3, whyText: "day1", in: context)
        try context.save()

        clock.advance(by: 86_400)
        let day1Noon = day1.addingTimeInterval(12 * 3_600)
        XCTAssertThrowsError(
            try service.save(day: day1Noon, mood: 0, stress: 0, whyText: "x", in: context)
        )
    }

    // MARK: REAL_STACK_GATE — on-disk store round-trip

    func testTodaysFeelingUpsertsToDiskAndReloads() throws {
        // A REAL on-disk store (not in-memory): save, then reopen a fresh
        // container over the SAME file and confirm the row reloads intact.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t11-feeling-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let clock = pinnedClock()
        let dayKey = clock.today()

        do {
            let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
            let container = try ModelContainer(
                for: PersistenceController.schema, configurations: [config]
            )
            let context = ModelContext(container)
            let service = DailyFeelingService(clock: clock)
            try service.saveToday(mood: 4, stress: 2, whyText: "shipped T11", in: context)
            try context.save()
        }

        // Reopen a FRESH container over the same on-disk file.
        let config = ModelConfiguration(schema: PersistenceController.schema, url: url)
        let container = try ModelContainer(
            for: PersistenceController.schema, configurations: [config]
        )
        let context = ModelContext(container)
        let reloaded = try context.fetch(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.day, dayKey)
        XCTAssertEqual(reloaded.first?.mood, 4)
        XCTAssertEqual(reloaded.first?.stress, 2)
        XCTAssertEqual(reloaded.first?.whyText, "shipped T11")
    }
}
