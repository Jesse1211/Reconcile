import XCTest
import SwiftData
@testable import Reconcile

/// T7 gate — Today screen presenter (ADR-004/-005/-008/-010/-013/-019/-020/-024/-025/
/// -027/-030/-033/-034).
///
/// REAL_STACK isolation (E4): each test builds a UNIQUE temporary on-disk SwiftData
/// store in `setUp` and DELETES it in `tearDown`; the `Clock` is a pinned `TestClock`
/// and ZenQuotes is a FAKE injected client. The presenter drives the real T4/T5/T11
/// services, so these gates exercise the actual product behaviour, not mocks.
@MainActor
final class TodayViewModelTests: XCTestCase {

    // MARK: Fake ZenQuotes client

    final class FakeClient: ZenQuotesClient {
        var todayQuote: FetchedQuote
        var randomQuotes: [FetchedQuote]
        var throwsError: ZenQuotesError?
        private(set) var todayCalls = 0
        private(set) var randomCalls = 0

        init(
            today: FetchedQuote = FetchedQuote(text: "The daily one", author: "Daily"),
            random: [FetchedQuote] = [FetchedQuote(text: "A random one", author: "Rand")],
            throwsError: ZenQuotesError? = nil
        ) {
            self.todayQuote = today
            self.randomQuotes = random
            self.throwsError = throwsError
        }

        func today() async throws -> FetchedQuote {
            todayCalls += 1
            if let e = throwsError { throw e }
            return todayQuote
        }

        func random() async throws -> FetchedQuote {
            let idx = randomCalls
            randomCalls += 1
            if let e = throwsError { throw e }
            return randomQuotes[idx % randomQuotes.count]
        }
    }

    // MARK: Real on-disk store (E4)

    private var storeURL: URL!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: TestClock!
    private var scope: TodayScope = .online

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("store.sqlite")
        let config = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        context = ModelContext(container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000), calendar: cal)
        scope = .online
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        if let url = storeURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    // MARK: Factory

    private func makeModel(client: FakeClient = FakeClient()) -> TodayViewModel {
        let quoteService = QuoteService(
            context: context, clock: clock, client: client, scope: { [weak self] in self?.scope ?? .online }
        )
        return TodayViewModel(
            context: context,
            clock: clock,
            quoteService: quoteService,
            mitService: MITService(clock: clock),
            feelingService: DailyFeelingService(clock: clock),
            scope: { [weak self] in self?.scope ?? .online }
        )
    }

    // MARK: - Quote area (ADR-013/-033/-034)

    func testOnlineResolvesToFetchedQuote() async {
        scope = .online
        let model = makeModel(client: FakeClient(today: FetchedQuote(text: "Hello", author: "Ada")))
        await model.resolveQuote()
        guard case .quote(let q) = model.quoteState else { return XCTFail("expected quote") }
        XCTAssertEqual(q.text, "Hello")
        XCTAssertTrue(q.isTransientOnline, "online /today quote is transient (ADR-013)")
    }

    func testOnlineFailureSurfacesErrorNotFallback() async {
        scope = .online
        let model = makeModel(client: FakeClient(throwsError: .offline))
        await model.resolveQuote()
        XCTAssertEqual(model.quoteState, .error(.offline), "online failure → error+retry (ADR-013)")
    }

    func testRetryAfterErrorRecovers() async {
        scope = .online
        let client = FakeClient(throwsError: .offline)
        let model = makeModel(client: client)
        await model.resolveQuote()
        XCTAssertEqual(model.quoteState, .error(.offline))
        client.throwsError = nil
        client.todayQuote = FetchedQuote(text: "Recovered", author: nil)
        await model.retryQuote()
        guard case .quote(let q) = model.quoteState else { return XCTFail("expected quote after retry") }
        XCTAssertEqual(q.text, "Recovered")
    }

    func testMineEmptyPoolShowsGuidingEmptyStateNotError() async {
        scope = .mine
        let model = makeModel()
        await model.resolveQuote()
        XCTAssertEqual(model.quoteState, .empty, "mine + empty pool → guiding empty (ADR-033/-034)")
    }

    func testMineNeverFetches() async {
        scope = .mine
        let client = FakeClient()
        let model = makeModel(client: client)
        await model.resolveQuote()
        XCTAssertEqual(client.todayCalls, 0, "mine never fetches (ADR-013)")
        XCTAssertEqual(client.randomCalls, 0)
    }

    // MARK: - ♡ like / save (ADR-010)

    func testLikeCurrentOnlineQuotePersistsIntoLibrary() async throws {
        scope = .online
        let model = makeModel(client: FakeClient(today: FetchedQuote(text: "Persist me", author: "Zed")))
        await model.resolveQuote()
        XCTAssertTrue(model.canLikeCurrentQuote, "a transient online quote is likeable (ADR-010)")
        let row = await model.likeCurrentQuote()
        XCTAssertNotNil(row)
        let count = try context.fetchCount(FetchDescriptor<Quote>())
        XCTAssertEqual(count, 1, "♡ like persists exactly one Quote row (ADR-010)")
        XCTAssertEqual(row?.source, .api)
        XCTAssertNotNil(row?.likedAt)
        // After liking, the SAME displayed quote must read as saved (heart fills), and it
        // must no longer be offered as likeable — it is now a persisted row, not transient.
        XCTAssertTrue(model.currentQuoteIsSaved, "after ♡ the current quote reads as saved (heart fills)")
        XCTAssertFalse(model.canLikeCurrentQuote, "a saved quote is no longer a transient likeable one")
    }

    func testMineQuoteIsNotLikeableFromToday() async throws {
        // Seed a user quote so mine has a pool.
        let q = Quote(text: "Mine one", author: "Me", source: .user)
        context.insert(q)
        try context.save()
        scope = .mine
        let model = makeModel()
        await model.resolveQuote()
        XCTAssertFalse(model.canLikeCurrentQuote, "a persisted mine quote is already saved — not likeable")
        XCTAssertTrue(model.currentQuoteIsSaved)
        let liked = await model.likeCurrentQuote()
        XCTAssertNil(liked, "nothing transient to persist")
    }

    // MARK: - Refresh + degenerate pool (ADR-025/-027)

    func testRefreshDisabledOnDegenerateMinePool() async throws {
        // 0 quotes → disabled; 1 → disabled; 2 → enabled (ADR-027).
        scope = .mine
        let model = makeModel()
        XCTAssertTrue(model.refreshDisabled, "empty mine pool → refresh disabled (ADR-027)")

        context.insert(Quote(text: "One", author: "A", source: .user))
        try context.save()
        XCTAssertTrue(model.refreshDisabled, "single-quote mine pool → still disabled (ADR-027)")

        context.insert(Quote(text: "Two", author: "B", source: .user))
        try context.save()
        XCTAssertFalse(model.refreshDisabled, "≥2 selectable → refresh enabled (ADR-027)")
    }

    func testRefreshOnlineNeverDisabledByPoolSize() {
        scope = .online
        let model = makeModel()
        XCTAssertFalse(model.refreshDisabled, "online is never pool-disabled (ADR-027)")
    }

    func testRefreshOnlineFetchesDifferentViaRandom() async {
        scope = .online
        let client = FakeClient(random: [FetchedQuote(text: "Different", author: "R")])
        let model = makeModel(client: client)
        await model.resolveQuote()
        await model.refreshQuote()
        XCTAssertEqual(client.randomCalls, 1, "online refresh uses /random (ADR-025)")
        guard case .quote(let q) = model.quoteState else { return XCTFail() }
        XCTAssertEqual(q.text, "Different")
    }

    func testRefreshOnDegeneratePoolIsNoOp() async throws {
        context.insert(Quote(text: "Only", author: "A", source: .user))
        try context.save()
        scope = .mine
        let model = makeModel()
        await model.resolveQuote()
        let before = model.quoteState
        await model.refreshQuote()
        XCTAssertEqual(model.quoteState, before, "degenerate mine refresh is a no-op (ADR-027)")
    }

    // MARK: - MIT list + rollover (ADR-005/-017)

    func testTodaysListShowsRolledInMITs() throws {
        let mitService = MITService(clock: clock)
        // Create an open MIT "yesterday", then advance the clock a day.
        let yesterday = clock.today()
        let mit = mitService.create(text: "Carry me", in: context)
        mit.appearsOn = yesterday
        try context.save()
        clock.advance(by: 86_400 * 2) // two days later

        let model = makeModel()
        model.rolloverAndReloadMITs()
        XCTAssertEqual(model.mits.count, 1, "past-due open MIT rolls into today (ADR-005)")
        XCTAssertEqual(model.mits.first?.appearsOn, clock.today())
    }

    // MARK: - Intention ritual save (ADR-024)

    func testSaveIntentionCreatesMITWithReason() throws {
        let model = makeModel()
        let mit = model.saveIntention(text: "  Ship it  ", reason: "  because it matters  ")
        XCTAssertNotNil(mit)
        XCTAssertEqual(mit?.text, "Ship it", "text is trimmed")
        XCTAssertEqual(mit?.reason, "because it matters", "reason persists to MIT.reason (ADR-024)")
        XCTAssertEqual(model.mits.count, 1)
    }

    func testSaveIntentionBlankTextRejected() {
        let model = makeModel()
        XCTAssertNil(model.saveIntention(text: "   ", reason: nil), "blank one-thing is rejected")
        XCTAssertTrue(model.mits.isEmpty)
    }

    func testSaveIntentionBlankReasonStoredAsNil() {
        let model = makeModel()
        let mit = model.saveIntention(text: "Do", reason: "   ")
        XCTAssertNil(mit?.reason, "blank reason → nil (optional field, ADR-024)")
    }

    // MARK: - Complete / edit / soft-delete + undo (ADR-004/-008/-030)

    func testToggleCompleteRemovesFromOpenList() {
        let model = makeModel()
        _ = model.saveIntention(text: "Task", reason: nil)
        let mit = model.mits[0]
        model.toggleComplete(mit)
        XCTAssertTrue(model.mits.isEmpty, "completing removes it from today's open list (ADR-004)")
        XCTAssertEqual(mit.status, .completed)
        XCTAssertEqual(mit.completedOn, clock.today())
    }

    func testEditMITUpdatesTextAndReason() {
        let model = makeModel()
        _ = model.saveIntention(text: "Old", reason: nil)
        let mit = model.mits[0]
        model.editMIT(mit, text: "New", reason: .some("now with reason"))
        XCTAssertEqual(mit.text, "New")
        XCTAssertEqual(mit.reason, "now with reason")
    }

    func testSoftDeleteRemovesAndOffersUndo() {
        let model = makeModel()
        _ = model.saveIntention(text: "Oops", reason: nil)
        let mit = model.mits[0]
        model.softDelete(mit)
        XCTAssertTrue(model.mits.isEmpty, "soft-delete removes from list (ADR-008)")
        XCTAssertTrue(mit.isDeleted)
        XCTAssertNotNil(model.pendingUndo, "delete offers undo (ADR-008)")
    }

    func testUndoRestoresIntoToday() {
        let model = makeModel()
        _ = model.saveIntention(text: "Bring back", reason: nil)
        let mit = model.mits[0]
        model.softDelete(mit)
        model.undoDelete()
        XCTAssertEqual(model.mits.count, 1, "undo restores the MIT (ADR-008)")
        XCTAssertFalse(mit.isDeleted)
        XCTAssertEqual(mit.appearsOn, clock.today())
        XCTAssertNil(model.pendingUndo)
    }

    func testCrossMidnightUndoRestoresIntoTodayNotLockedDay() {
        let model = makeModel()
        _ = model.saveIntention(text: "Night task", reason: nil)
        let mit = model.mits[0]
        model.softDelete(mit)
        // The day rolls before the user hits undo.
        clock.advance(by: 86_400 * 2)
        model.undoDelete()
        XCTAssertEqual(mit.appearsOn, clock.today(), "cross-midnight undo re-enters TODAY (ADR-030)")
        XCTAssertEqual(model.mits.count, 1)
    }

    // MARK: - Empty / first-run (ADR-033)

    func testMitListEmptyFlag() {
        let model = makeModel()
        model.reloadMITs()
        XCTAssertTrue(model.mitListIsEmpty, "fresh store → empty MIT list drives first-run line (ADR-033)")
    }

    // MARK: - Evening feeling (ADR-019/-020)

    func testSaveFeelingUpsertsTodaysEntry() throws {
        let model = makeModel()
        let saved = model.saveFeeling(mood: 4, stress: 2, why: "good day")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.mood, 4)
        XCTAssertEqual(saved?.stress, 2)
        XCTAssertEqual(saved?.whyText, "good day")
        // Re-save updates in place (INV-7): still one row.
        _ = model.saveFeeling(mood: 1, stress: 5, why: nil)
        let count = try context.fetchCount(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(count, 1, "one feeling per day, upserted (INV-7/ADR-020)")
        XCTAssertEqual(model.feeling?.mood, 1)
        XCTAssertEqual(model.feeling?.stress, 5)
        XCTAssertNil(model.feeling?.whyText, "blank why → nil")
    }

    func testSaveFeelingRejectsOutOfRangeWithoutMutating() throws {
        let model = makeModel()
        let bad = model.saveFeeling(mood: 6, stress: 3, why: nil)
        XCTAssertNil(bad, "out-of-range mood is rejected, never clamped (INV-7)")
        let count = try context.fetchCount(FetchDescriptor<DailyFeeling>())
        XCTAssertEqual(count, 0, "a rejected feeling never inserts a row")
    }

    func testFeelingEditableToday() {
        let model = makeModel()
        XCTAssertTrue(model.feelingEditable, "today's feeling is editable (INV-8)")
    }
}
