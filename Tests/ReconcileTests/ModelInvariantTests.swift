import XCTest
import SwiftData
@testable import Reconcile

/// Model-layer invariant tests for T2 (ADR-002): INV-1, INV-4, INV-5, INV-6, INV-7, INV-9.
final class ModelInvariantTests: XCTestCase {

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

    // MARK: INV-1 — createdOn <= completedOn

    func testMITMarkCompletedStampsCompletionDay() throws {
        let clock = pinnedClock()
        let created = clock.today()
        let mit = MIT(text: "Ship T2", createdOn: created, appearsOn: created)
        clock.advance(by: 2 * 86_400)
        let day = clock.today()

        try mit.markCompleted(on: day)

        XCTAssertEqual(mit.status, .completed)
        XCTAssertEqual(mit.completedOn, day)
        XCTAssertNoThrow(try mit.validateInvariants())
    }

    func testMITCompletedBeforeCreatedThrows() throws {
        let clock = pinnedClock()
        let created = clock.today()
        let mit = MIT(text: "Time travel", createdOn: created, appearsOn: created)
        let earlier = clock.startOfDay(for: created.addingTimeInterval(-86_400))

        XCTAssertThrowsError(try mit.markCompleted(on: earlier)) { error in
            XCTAssertEqual(
                error as? MIT.InvariantError,
                .completedBeforeCreated(createdOn: created, completedOn: earlier)
            )
        }
        // Rejected mutation leaves the task open with no completion stamp.
        XCTAssertEqual(mit.status, .open)
        XCTAssertNil(mit.completedOn)
    }

    func testMITSameDayCompletionAllowed() throws {
        let clock = pinnedClock()
        let day = clock.today()
        let mit = MIT(text: "Same day", createdOn: day, appearsOn: day)
        XCTAssertNoThrow(try mit.markCompleted(on: day))
        XCTAssertEqual(mit.completedOn, day)
    }

    func testMITReopenClearsCompletion() throws {
        let clock = pinnedClock()
        let day = clock.today()
        let mit = MIT(text: "Reopen", createdOn: day, appearsOn: day)
        try mit.markCompleted(on: day)
        mit.reopen()
        XCTAssertEqual(mit.status, .open)
        XCTAssertNil(mit.completedOn)
        XCTAssertNoThrow(try mit.validateInvariants())
    }

    func testMITValidateInvariantsCatchesInconsistentState() {
        let clock = pinnedClock()
        let created = clock.today()
        let earlier = clock.startOfDay(for: created.addingTimeInterval(-86_400))
        // Construct an inconsistent completed state directly.
        let mit = MIT(
            text: "Bad",
            status: .completed,
            createdOn: created,
            completedOn: earlier,
            appearsOn: created
        )
        XCTAssertThrowsError(try mit.validateInvariants())
    }

    // MARK: INV-6 — soft-deleted MIT retained but excluded from stats

    func testMITSoftDeleteRetainsRowButExcludesFromStats() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let day = clock.today()

        let live = MIT(text: "Live", createdOn: day, appearsOn: day)
        let gone = MIT(text: "Deleted", createdOn: day, appearsOn: day)
        context.insert(live)
        context.insert(gone)
        gone.softDelete(at: clock.now())
        try context.save()

        // Row is RETAINED: a plain fetch still sees both.
        let all = try context.fetch(FetchDescriptor<MIT>())
        XCTAssertEqual(all.count, 2)

        // Stats predicate EXCLUDES the soft-deleted one.
        let stats = try context.fetch(FetchDescriptor<MIT>(predicate: MIT.statsPredicate))
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats.first?.text, "Live")

        XCTAssertFalse(gone.countsTowardStats)
        XCTAssertTrue(live.countsTowardStats)
        XCTAssertNotNil(gone.deletedAt)
    }

    func testMITRestoreReturnsToStats() throws {
        let clock = pinnedClock()
        let day = clock.today()
        let mit = MIT(text: "Restore", createdOn: day, appearsOn: day)
        mit.softDelete(at: clock.now())
        XCTAssertFalse(mit.countsTowardStats)
        mit.restore()
        XCTAssertTrue(mit.countsTowardStats)
        XCTAssertNil(mit.deletedAt)
    }

    // MARK: INV-9 — likedAt is the single stored like field; liked is derived

    func testQuoteLikedDerivesFromLikedAt() {
        let clock = pinnedClock()
        let q = Quote(text: "Be here now", author: "Ram Dass", source: .user)
        XCTAssertFalse(q.liked)
        XCTAssertNil(q.likedAt)

        q.like(at: clock.now())
        XCTAssertTrue(q.liked)
        XCTAssertEqual(q.likedAt, clock.now())

        q.unlike()
        XCTAssertFalse(q.liked)
        XCTAssertNil(q.likedAt)
    }

    func testQuoteReLikeDoesNotOverwriteTimestamp() {
        let clock = pinnedClock()
        let q = Quote(text: "x", source: .user)
        q.like(at: clock.now())
        let first = q.likedAt
        clock.advance(by: 100)
        q.like(at: clock.now())
        XCTAssertEqual(q.likedAt, first)
    }

    func testQuoteSetLikedToggles() {
        let clock = pinnedClock()
        let q = Quote(text: "x", source: .user)
        q.setLiked(true, at: clock.now())
        XCTAssertTrue(q.liked)
        q.setLiked(false, at: clock.now())
        XCTAssertFalse(q.liked)
    }

    /// INV-9 guard: there is NO stored `liked` property, only derived. Reflection
    /// over the model's stored keys must not surface a `liked` field.
    func testQuoteHasNoStoredLikedField() {
        let q = Quote(text: "x", source: .user)
        let mirror = Mirror(reflecting: q)
        let hasStoredLiked = mirror.children.contains { child in
            (child.label ?? "").caseInsensitiveCompare("liked") == .orderedSame
                || (child.label ?? "").caseInsensitiveCompare("_liked") == .orderedSame
        }
        XCTAssertFalse(hasStoredLiked, "INV-9: `liked` must be derived, never stored")
    }

    // MARK: INV-4 — dedup normalization

    func testDedupNormalizeLowercasesTrimsCollapsesWhitespace() {
        XCTAssertEqual(
            QuoteNormalization.normalize("  The   Quick\tBrown\nFox  "),
            "the quick brown fox"
        )
    }

    func testDedupNormalizeStripsSingleTrailingPeriod() {
        XCTAssertEqual(QuoteNormalization.normalize("Hello world."), "hello world")
        // Only ONE trailing period is stripped.
        XCTAssertEqual(QuoteNormalization.normalize("Wait..."), "wait..")
    }

    func testDedupNormalizeFoldsCurlyQuotes() {
        // Curly apostrophe and curly double quotes fold to ASCII.
        XCTAssertEqual(
            QuoteNormalization.normalize("It\u{2019}s \u{201C}fine\u{201D}"),
            "it's \"fine\""
        )
    }

    func testDedupAuthorFoldsNilEmptyAnonymous() {
        XCTAssertEqual(QuoteNormalization.normalizeAuthor(nil), "")
        XCTAssertEqual(QuoteNormalization.normalizeAuthor(""), "")
        XCTAssertEqual(QuoteNormalization.normalizeAuthor("Anonymous"), "")
        XCTAssertEqual(QuoteNormalization.normalizeAuthor("  anonymous "), "")
        XCTAssertEqual(QuoteNormalization.normalizeAuthor("Seneca"), "seneca")
    }

    func testDedupKeyCombinesTextAndAuthor() {
        let key = QuoteNormalization.dedupKey(text: "Carpe diem.", author: "Horace")
        XCTAssertEqual(key, "carpe diem|horace")
    }

    func testDedupKeyEquivalenceAcrossFormattingAndAnonymous() {
        // Same quote, different casing/spacing/trailing-period, and Anonymous vs nil.
        let a = Quote.dedupKey(text: "Be Kind.", author: "Anonymous")
        let b = Quote.dedupKey(text: "  be   kind  ", author: nil)
        XCTAssertEqual(a, b)
    }

    func testQuoteStoresDedupKeyAndKeepsItInSync() {
        let q = Quote(text: "Carpe diem.", author: "Horace", source: .user)
        XCTAssertEqual(q.dedupKey, "carpe diem|horace")
        q.update(text: "Memento mori", author: "Anonymous")
        XCTAssertEqual(q.dedupKey, "memento mori|")
    }

    func testDedupPreventsDuplicateInsertViaKeyLookup() throws {
        let context = inMemoryContext()
        let q1 = Quote(text: "Stay hungry.", author: "Jobs", source: .api)
        context.insert(q1)
        try context.save()

        // A would-be duplicate with different formatting.
        let candidateKey = Quote.dedupKey(text: "  stay   hungry  ", author: "jobs")
        let descriptor = FetchDescriptor<Quote>(
            predicate: #Predicate { $0.dedupKey == candidateKey }
        )
        let existing = try context.fetch(descriptor)
        XCTAssertEqual(existing.count, 1, "INV-4: dedupKey identifies the duplicate")
    }

    // MARK: INV-5 — non-negative timestamp-derived duration; cache written only on stop

    func testFocusSessionRunningDurationFromTimestamps() {
        let clock = pinnedClock()
        let session = FocusSession(startedAt: clock.now())
        XCTAssertTrue(session.isRunning)
        // Cache is ignored while running.
        XCTAssertEqual(session.accumulatedSeconds, 0)
        clock.advance(by: 125)
        XCTAssertEqual(session.duration(now: clock.now()), 125)
        // Still running: cache untouched.
        XCTAssertEqual(session.accumulatedSeconds, 0)
    }

    func testFocusSessionStopWritesCacheFromTimestamps() {
        let clock = pinnedClock()
        let session = FocusSession(startedAt: clock.now())
        clock.advance(by: 300)
        session.stop(at: clock.now())
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.accumulatedSeconds, 300)
        XCTAssertEqual(session.duration(now: clock.now()), 300)
    }

    func testFocusSessionStopIsIdempotent() {
        let clock = pinnedClock()
        let session = FocusSession(startedAt: clock.now())
        clock.advance(by: 60)
        session.stop(at: clock.now())
        let end = session.endedAt
        clock.advance(by: 999)
        session.stop(at: clock.now())
        XCTAssertEqual(session.endedAt, end)
        XCTAssertEqual(session.accumulatedSeconds, 60)
    }

    func testFocusSessionDurationNeverNegative() {
        let clock = pinnedClock()
        let session = FocusSession(startedAt: clock.now())
        // A reversed interval (end before start) clamps to zero, never negative.
        let before = clock.now().addingTimeInterval(-500)
        XCTAssertEqual(session.duration(now: before), 0)

        // Even a stored reversed endedAt yields a non-negative duration.
        let reversed = FocusSession(
            startedAt: clock.now(),
            endedAt: clock.now().addingTimeInterval(-10)
        )
        XCTAssertGreaterThanOrEqual(reversed.duration(now: clock.now()), 0)
    }

    // MARK: INV-7 — one DailyFeeling per day; scales in 0...5

    func testDailyFeelingClampsScales() {
        let clock = pinnedClock()
        let day = clock.today()
        let f = DailyFeeling(day: day, mood: 9, stress: -3)
        XCTAssertEqual(f.mood, 5)
        XCTAssertEqual(f.stress, 0)
        f.setMood(-1)
        f.setStress(42)
        XCTAssertEqual(f.mood, 0)
        XCTAssertEqual(f.stress, 5)
    }

    func testDailyFeelingUpsertUpdatesInPlace() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let day = clock.today()

        try DailyFeeling.upsert(day: day, mood: 3, stress: 2, whyText: "ok", in: context)
        try DailyFeeling.upsert(day: day, mood: 5, stress: 1, whyText: "better", in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(all.count, 1, "INV-7: exactly one DailyFeeling per day")
        XCTAssertEqual(all.first?.mood, 5)
        XCTAssertEqual(all.first?.stress, 1)
        XCTAssertEqual(all.first?.whyText, "better")
    }

    func testDailyFeelingUpsertDistinctDaysCreatesRows() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()
        let day1 = clock.today()
        clock.advance(by: 86_400)
        let day2 = clock.today()
        XCTAssertNotEqual(day1, day2)

        try DailyFeeling.upsert(day: day1, mood: 1, stress: 1, whyText: nil, in: context)
        try DailyFeeling.upsert(day: day2, mood: 2, stress: 2, whyText: nil, in: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyFeeling>()).count, 2)
    }

    // MARK: Container registers all domain models

    func testContainerRegistersAllDomainModels() {
        let container = PersistenceController.makeInMemoryContainer()
        let names = Set(container.schema.entities.map(\.name))
        XCTAssertTrue(names.isSuperset(of: [
            "MIT", "Quote", "FocusSession", "DailyFeeling", "DailySelectedQuote",
        ]))
        XCTAssertFalse(names.contains("ScaffoldMarker"), "T2 removed the T1 scaffold")
    }

    // MARK: DailySelectedQuote inline dedup

    func testDailySelectedQuoteInlineDerivesDedupKey() {
        let clock = pinnedClock()
        let sel = DailySelectedQuote.inline(
            day: clock.today(),
            scope: .online,
            text: "Keep going.",
            author: "Anonymous"
        )
        XCTAssertTrue(sel.isInline)
        XCTAssertEqual(sel.inlineDedupKey, "keep going|")
    }

    func testDailySelectedQuoteRefRoundTripsThroughPersistence() throws {
        let context = inMemoryContext()
        let clock = pinnedClock()

        // A saved quote has a stable PersistentIdentifier.
        let quote = Quote(text: "Referenced", author: "A", source: .user)
        context.insert(quote)
        try context.save()
        let ref = quote.persistentModelID

        let sel = DailySelectedQuote(day: clock.today(), scope: .mine, quoteRef: ref)
        context.insert(sel)
        try context.save()
        XCTAssertFalse(sel.isInline)
        XCTAssertEqual(sel.quoteRef, ref)

        // Re-fetch from a fresh context to confirm the reference persisted.
        let refetched = try context.fetch(FetchDescriptor<DailySelectedQuote>())
        XCTAssertEqual(refetched.count, 1)
        XCTAssertEqual(refetched.first?.quoteRef, ref)
        // The referenced quote is reachable via the decoded identifier.
        XCTAssertEqual(context.model(for: ref) as? Quote, quote)
    }
}
