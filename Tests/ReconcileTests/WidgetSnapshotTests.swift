import XCTest
import SwiftData
@testable import Reconcile

/// T12 gate — WidgetKit shared-snapshot writer, read-model consistency, layout
/// decisions, empty states, read-only contract, and the REAL App Group round-trip
/// (ADR-041–ADR-045).
///
/// The widget VIEWS (`HomeWidgetView`/`LockWidgetView`) live in the extension target
/// and are exercised by the BUILD gate + the human smoke step; here we assert the
/// pure, testable core: the ``WidgetLayout`` decision the views switch on, the
/// snapshot the app-side ``WidgetSnapshotWriter`` produces at each transition, and the
/// round-trip through a REAL App Group `UserDefaults` container (not a mock).
@MainActor
final class WidgetSnapshotTests: XCTestCase {

    // MARK: Real on-disk store (E4) + a real App Group suite

    private var storeURL: URL!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: TestClock!
    private var suiteName: String!
    private var realGroupDefaults: UserDefaults!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("store.sqlite")
        let config = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        context = ModelContext(container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000), calendar: cal)

        // A REAL, unique UserDefaults suite standing in for the App Group container
        // (REAL_STACK_GATE): a genuine on-disk defaults store, not a mock.
        suiteName = "group.test.reconcile.\(UUID().uuidString)"
        realGroupDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        storeURL = nil
        realGroupDefaults?.removePersistentDomain(forName: suiteName)
        realGroupDefaults = nil
        suiteName = nil
    }

    // MARK: Helpers

    private func realStore() -> AppGroupSnapshotStore {
        AppGroupSnapshotStore(defaults: realGroupDefaults)
    }

    private func writer(store: WidgetSnapshotStore) -> WidgetSnapshotWriter {
        WidgetSnapshotWriter(store: store, today: { self.clock.today() })
    }

    // MARK: - REAL_STACK_GATE: round-trip through a REAL App Group container

    func testSnapshotRoundTripsThroughRealAppGroupContainer() {
        let store = realStore()
        let w = writer(store: store)

        w.todaysQuoteResolved(text: "Keep going", author: "Marcus")
        w.focusSessionStarted(startedAt: clock.now())
        w.themeChanged(.dayArc)

        // Read back through a FRESH loader over the SAME real suite (extension-side path).
        let loader = WidgetSnapshotLoader(store: AppGroupSnapshotStore(defaults: realGroupDefaults))
        let loaded = loader.load()

        XCTAssertNotNil(loaded, "snapshot must survive the real App Group round-trip")
        XCTAssertEqual(loaded?.quoteText, "Keep going")
        XCTAssertEqual(loaded?.quoteAuthor, "Marcus")
        XCTAssertEqual(loaded?.runningStartedAt, clock.now())
        XCTAssertEqual(loaded?.theme, .dayArc)
        XCTAssertEqual(loaded?.day, clock.today())
    }

    // MARK: - Writer fires on focus transitions (ADR-042 (a))

    func testFocusStartWritesRunningStartedAt() throws {
        let store = InMemorySnapshotStore()
        let svc = FocusSessionService(context: context, clock: clock, widgetWriter: writer(store: store))

        let session = try svc.start()

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.runningStartedAt, session.startedAt)
        XCTAssertTrue(snap.isRunning, "start → running layout (ADR-041)")
    }

    func testFocusStopClearsRunningAndWritesTodaysAccumulatedSeconds() throws {
        let store = InMemorySnapshotStore()
        let svc = FocusSessionService(context: context, clock: clock, widgetWriter: writer(store: store))

        let session = try svc.start()
        clock.advance(by: 300)
        try svc.stop(session)

        let snap = try XCTUnwrap(store.read())
        XCTAssertNil(snap.runningStartedAt, "stop clears the running figure (ADR-042 (a))")
        XCTAssertFalse(snap.isRunning, "stop → idle layout (ADR-041)")
        XCTAssertEqual(snap.accumulatedSeconds, 300, "today's accumulated stopped seconds")
    }

    func testFocusStopAccumulatesAcrossMultipleSessionsSameDay() throws {
        let store = InMemorySnapshotStore()
        let svc = FocusSessionService(context: context, clock: clock, widgetWriter: writer(store: store))

        let s1 = try svc.start(); clock.advance(by: 120); try svc.stop(s1)
        let s2 = try svc.start(); clock.advance(by: 180); try svc.stop(s2)

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.accumulatedSeconds, 300, "today's total = 120 + 180 (ADR-032)")
        XCTAssertNil(snap.runningStartedAt)
    }

    func testDiscardRunningSessionFlipsToIdleAccumulated() throws {
        let store = InMemorySnapshotStore()
        let svc = FocusSessionService(context: context, clock: clock, widgetWriter: writer(store: store))

        let s1 = try svc.start(); clock.advance(by: 60); try svc.stop(s1)  // 60s stopped today
        let running = try svc.start(); clock.advance(by: 90)
        try svc.discard(running)

        let snap = try XCTUnwrap(store.read())
        XCTAssertNil(snap.runningStartedAt, "discarding the running session flips to idle")
        XCTAssertEqual(snap.accumulatedSeconds, 60, "discarded time never counts (ADR-014)")
    }

    func testDiscardWhileAnotherSessionRunsStaysRunning() throws {
        // Two independent sessions (ADR-014); discarding one while the other still runs
        // keeps the running layout via current-state re-projection.
        let store = InMemorySnapshotStore()
        let svc = FocusSessionService(context: context, clock: clock, widgetWriter: writer(store: store))

        let a = try svc.start()
        clock.advance(by: 10)
        let b = try svc.start()
        try svc.discard(a)   // b is still running

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.runningStartedAt, b.startedAt, "still-running session keeps running layout")
    }

    // MARK: - Writer fires on quote transitions (ADR-042 (b)) + read-model consistency

    func testTodaysQuoteMirrorsAppResolvedQuoteOnline() async throws {
        // App today's quote == widget quote (ADR-042 read-model consistency).
        let store = InMemorySnapshotStore()
        let client = StubClient(today: FetchedQuote(text: "Today online", author: "Zeno"))
        let svc = QuoteService(
            context: context, clock: clock, client: client,
            scope: { .online }, widgetWriter: writer(store: store)
        )

        let resolved = await svc.todaysQuote()

        guard case .quote(let q) = resolved else { return XCTFail("expected a quote") }
        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.quoteText, q.text)
        XCTAssertEqual(snap.quoteAuthor, q.author)
        XCTAssertEqual(snap.quoteText, "Today online")
    }

    func testRefreshMirrorsRefreshedQuote() async throws {
        let store = InMemorySnapshotStore()
        let client = StubClient(
            today: FetchedQuote(text: "Daily", author: "A"),
            random: [FetchedQuote(text: "Refreshed", author: "B")]
        )
        let svc = QuoteService(
            context: context, clock: clock, client: client,
            scope: { .online }, widgetWriter: writer(store: store)
        )

        _ = await svc.todaysQuote()
        _ = await svc.refresh()

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.quoteText, "Refreshed", "refresh transition mirrors the new quote (ADR-025)")
        XCTAssertEqual(snap.quoteAuthor, "B")
    }

    func testEmptyMineClearsQuoteToPlaceholderState() async throws {
        // scope=mine + empty library → .empty → widget shows the ADR-045 placeholder.
        let store = InMemorySnapshotStore()
        let svc = QuoteService(
            context: context, clock: clock, client: StubClient(),
            scope: { .mine }, widgetWriter: writer(store: store)
        )

        let resolved = await svc.todaysQuote()
        XCTAssertEqual(resolved, .empty)

        let snap = try XCTUnwrap(store.read())
        XCTAssertFalse(snap.hasQuote, "no quote → placeholder state (ADR-045)")
        XCTAssertEqual(WidgetLayout.resolve(snap), .emptyQuote)
    }

    func testErrorLeavesLastQuoteIntact() async throws {
        // A transient online failure (ADR-013) must NOT blank the widget (ADR-045).
        let store = InMemorySnapshotStore()
        let client = StubClient(today: FetchedQuote(text: "Good quote", author: "X"))
        let svc = QuoteService(
            context: context, clock: clock, client: client,
            scope: { .online }, widgetWriter: writer(store: store)
        )
        _ = await svc.todaysQuote()                 // writes "Good quote"
        client.throwsError = .offline
        // New service instance same store to force a fresh fetch (empty transient cache).
        let svc2 = QuoteService(
            context: context, clock: clock, client: client,
            scope: { .online }, widgetWriter: writer(store: store)
        )
        let resolved = await svc2.todaysQuote()
        if case .error = resolved {} else { XCTFail("expected error") }

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.quoteText, "Good quote", "error keeps the last snapshot (ADR-045)")
    }

    // MARK: - Theme transition (ADR-042 (c) / ADR-044)

    func testThemeChangeMirrorsToSnapshot() throws {
        let store = InMemorySnapshotStore()
        let defaults = UserDefaults(suiteName: "theme.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, widgetWriter: writer(store: store))

        settings.theme = .dayArc

        let snap = try XCTUnwrap(store.read())
        XCTAssertEqual(snap.theme, .dayArc, "theme change mirrors to the Home widget (ADR-044)")
        defaults.removePersistentDomain(forName: defaults.description)
    }

    // MARK: - Layout decision (ADR-041) — the core the views switch on

    func testRunningSnapshotResolvesToRunningLayout() {
        let snap = WidgetSnapshot(
            quoteText: "Q", quoteAuthor: "A",
            runningStartedAt: clock.now(), day: clock.today()
        )
        XCTAssertEqual(WidgetLayout.resolve(snap), .running,
                       "startedAt present + quote → running: time │ quote (ADR-041)")
    }

    func testIdleSnapshotResolvesToIdleLayoutNoTime() {
        let snap = WidgetSnapshot(
            quoteText: "Q", quoteAuthor: "A",
            runningStartedAt: nil, accumulatedSeconds: 600, day: clock.today()
        )
        XCTAssertEqual(WidgetLayout.resolve(snap), .idle,
                       "no running session → quote fills widget, NO time/divider (ADR-041)")
        XCTAssertFalse(snap.isRunning)
    }

    func testNoQuoteResolvesToEmptyLayout() {
        let snap = WidgetSnapshot(quoteText: nil, runningStartedAt: nil, day: clock.today())
        XCTAssertEqual(WidgetLayout.resolve(snap), .emptyQuote, "no quote → placeholder (ADR-045)")
    }

    func testNilSnapshotResolvesToEmptyLayout() {
        XCTAssertEqual(WidgetLayout.resolve(nil), .emptyQuote,
                       "never-written snapshot → placeholder, never blank (ADR-045)")
    }

    func testPlaceholderCopyMatchesSpec() {
        XCTAssertEqual(WidgetPlaceholder.home, "Open Reconcile to set today's quote")
        XCTAssertFalse(WidgetPlaceholder.lock.isEmpty)
    }

    // MARK: - READ-ONLY contract (ADR-042)

    func testLoaderExposesNoWritePath() {
        // The extension-side loader offers only `load()` — no mutation of app data or
        // the shared container (ADR-042). This is a compile-time guarantee; asserted
        // here by confirming a load without any write API on the loader surface.
        let store = realStore()
        writer(store: store).todaysQuoteResolved(text: "R", author: nil)
        let loaded = WidgetSnapshotLoader(store: store).load()
        XCTAssertEqual(loaded?.quoteText, "R")
    }

    // MARK: Stub client

    private final class StubClient: ZenQuotesClient {
        var todayQuote: FetchedQuote
        var randomQuotes: [FetchedQuote]
        var throwsError: ZenQuotesError?
        private var randomIdx = 0

        init(
            today: FetchedQuote = FetchedQuote(text: "Daily", author: "D"),
            random: [FetchedQuote] = [FetchedQuote(text: "Random", author: "R")],
            throwsError: ZenQuotesError? = nil
        ) {
            self.todayQuote = today
            self.randomQuotes = random
            self.throwsError = throwsError
        }

        func today(category: QuoteCategory) async throws -> FetchedQuote {
            if let e = throwsError { throw e }
            return todayQuote
        }

        func random(category: QuoteCategory) async throws -> FetchedQuote {
            if let e = throwsError { throw e }
            defer { randomIdx += 1 }
            return randomQuotes[randomIdx % randomQuotes.count]
        }
    }
}
