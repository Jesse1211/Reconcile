import XCTest
import SwiftData
@testable import Reconcile

/// T8 gate — Library screen logic (ADR-009/-010/-011/-012/-033/-035/-039/-040).
///
/// The gate asserts these paths "via the service, not just UI", so the tests drive
/// ``LibraryViewModel`` (which routes ALL persistence through the T5 ``QuoteService``)
/// and read back the real on-disk store. REAL_STACK isolation (E4): a UNIQUE temporary
/// on-disk SwiftData store per test, deleted in `tearDown`; the `Clock` is injected;
/// ZenQuotes is a FAKE injected client.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    // MARK: Fake ZenQuotes client

    final class FakeClient: ZenQuotesClient {
        var todayQuote: FetchedQuote
        var randomQuotes: [FetchedQuote]
        var throwsError: ZenQuotesError?
        private(set) var todayCalls = 0
        private(set) var randomCalls = 0
        // ADR-047: last category requested per endpoint (recorded for assertions).
        private(set) var lastTodayCategory: QuoteCategory?
        private(set) var lastRandomCategory: QuoteCategory?

        init(
            today: FetchedQuote = FetchedQuote(text: "The daily one", author: "Daily"),
            random: [FetchedQuote] = [FetchedQuote(text: "A random one", author: "Rand")],
            throwsError: ZenQuotesError? = nil
        ) {
            self.todayQuote = today
            self.randomQuotes = random
            self.throwsError = throwsError
        }

        func today(category: QuoteCategory) async throws -> FetchedQuote {
            todayCalls += 1
            lastTodayCategory = category
            if let e = throwsError { throw e }
            return todayQuote
        }

        func random(category: QuoteCategory) async throws -> FetchedQuote {
            let idx = randomCalls
            randomCalls += 1
            lastRandomCategory = category
            if let e = throwsError { throw e }
            return randomQuotes[idx % randomQuotes.count]
        }
    }

    // MARK: Mutable scope box (stands in for T1's persisted settings layer, ADR-040)

    final class ScopeBox { var scope: TodayScope; init(_ s: TodayScope) { scope = s } }

    // MARK: Real on-disk store (E4)

    private var storeURL: URL!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: TestClock!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("store.sqlite")
        let config = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        container = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        context = ModelContext(container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000), calendar: cal)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        if let dir = storeURL?.deletingLastPathComponent() {
            try? FileManager.default.removeItem(at: dir)
        }
        storeURL = nil
    }

    // MARK: Helpers

    private func makeService(scope: ScopeBox, client: FakeClient = FakeClient()) -> QuoteService {
        QuoteService(context: context, clock: clock, client: client, scope: { scope.scope })
    }

    private func makeModel(
        scope: ScopeBox,
        client: FakeClient = FakeClient()
    ) -> LibraryViewModel {
        let service = makeService(scope: scope, client: client)
        return LibraryViewModel(
            service: service,
            scope: { scope.scope },
            setScope: { scope.scope = $0 }
        )
    }

    private func quoteCount() throws -> Int {
        try context.fetch(FetchDescriptor<Quote>()).count
    }

    // MARK: - Empty state (ADR-033)

    func testFreshLibraryIsEmpty() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        model.reload()
        XCTAssertTrue(model.isEmpty, "fresh store → guiding empty state (ADR-033)")
        XCTAssertEqual(try quoteCount(), 0)
    }

    // MARK: - Manual add (ADR-009/-010)

    func testManualAddInsertsUserRow() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        let row = model.addUserQuote(text: "  Carpe diem  ", author: "  Horace  ")
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.source, .user, "manual add → source==user (ADR-009/-010)")
        XCTAssertEqual(row?.text, "Carpe diem", "text is trimmed")
        XCTAssertEqual(row?.author, "Horace", "author is trimmed")
        XCTAssertEqual(try quoteCount(), 1)
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.quotes.contains { $0.id == row?.id })
    }

    func testManualAddBlankTextRejected() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        XCTAssertNil(model.addUserQuote(text: "   ", author: "X"))
        XCTAssertEqual(try quoteCount(), 0, "blank text is not inserted")
    }

    func testManualAddBlankAuthorFoldsToNil() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        let row = model.addUserQuote(text: "No author here", author: "   ")
        XCTAssertNil(row?.author, "blank author folds to nil (INV-4)")
    }

    // MARK: - Browse-and-like inserts into the library (ADR-012/-010)

    func testBrowseAndLikeInsertsIntoLibrary() async throws {
        let client = FakeClient(random: [FetchedQuote(text: "Browsed gem", author: "B")])
        let model = makeModel(scope: ScopeBox(.online), client: client)

        // Browse a transient online quote via /random — NO row yet (ADR-013).
        await model.browseNext()
        XCTAssertEqual(model.browsing?.text, "Browsed gem")
        XCTAssertEqual(client.randomCalls, 1, "browse uses /random (ADR-012)")
        XCTAssertEqual(client.todayCalls, 0, "browse NEVER uses /today (ADR-012)")
        XCTAssertEqual(try quoteCount(), 0, "browsing is transient — no row until liked (ADR-013)")

        // ♡ like → persist into the library (ADR-010), verified via the store.
        let row = model.likeBrowsed()
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.source, .api, "liked online quote persists as source==api (ADR-010)")
        XCTAssertNotNil(row?.likedAt, "likedAt set on like (INV-9)")
        XCTAssertEqual(try quoteCount(), 1, "browse-and-like INSERTS into the library")
        XCTAssertNil(model.browsing, "browse slot cleared after like")
        XCTAssertTrue(model.quotes.contains { $0.id == row?.id }, "appears in the mine pool (ADR-011)")
    }

    func testBrowseErrorSurfacesRetry() async throws {
        let client = FakeClient(throwsError: .offline)
        let model = makeModel(scope: ScopeBox(.online), client: client)
        await model.browseNext()
        XCTAssertEqual(model.browseError, .offline, "browse failure → error+retry (ADR-013)")
        XCTAssertNil(model.browsing)
        XCTAssertEqual(try quoteCount(), 0)
    }

    func testDismissBrowsedDoesNotPersist() async throws {
        let client = FakeClient(random: [FetchedQuote(text: "Not saved", author: nil)])
        let model = makeModel(scope: ScopeBox(.online), client: client)
        await model.browseNext()
        model.dismissBrowsed()
        XCTAssertNil(model.browsing)
        XCTAssertEqual(try quoteCount(), 0, "dismiss without like → stays transient (ADR-013)")
    }

    // MARK: - Delete / un-like source-dependent (ADR-035/-039)

    func testUnlikeApiRowRemovesIt() async throws {
        let client = FakeClient(random: [FetchedQuote(text: "ApiGem", author: "A")])
        let model = makeModel(scope: ScopeBox(.online), client: client)
        await model.browseNext()
        let api = model.likeBrowsed()!
        XCTAssertEqual(try quoteCount(), 1)

        // Un-liking an api row is a HARD delete (same action as delete, ADR-035).
        model.unlike(api)
        XCTAssertEqual(try quoteCount(), 0, "un-like api → row gone (ADR-035)")
        XCTAssertTrue(model.isEmpty)
    }

    func testUnlikeUserRowRetainsIt() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        let user = model.addUserQuote(text: "My words", author: "Me")!
        user.like(at: clock.now())          // a user row that was ALSO liked
        try context.save()

        model.unlike(user)
        XCTAssertEqual(try quoteCount(), 1, "un-like user → row RETAINED (ADR-039)")
        XCTAssertNil(user.likedAt, "likedAt cleared")
        XCTAssertTrue(model.quotes.contains { $0.id == user.id }, "still in Library/mine via source==user")
    }

    func testDeleteUserRowRemovesIt() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        let user = model.addUserQuote(text: "Delete this", author: nil)!
        XCTAssertEqual(try quoteCount(), 1)

        model.delete(user)
        XCTAssertEqual(try quoteCount(), 0, "explicit delete of a user row removes it (ADR-035)")
        XCTAssertTrue(model.isEmpty)
    }

    func testRefetchSameDedupKeyIsTransientNotAutoReliked() async throws {
        // Like then un-like (hard-delete) an api quote.
        let client = FakeClient(random: [FetchedQuote(text: "Gone", author: "G")])
        let model = makeModel(scope: ScopeBox(.online), client: client)
        await model.browseNext()
        let api = model.likeBrowsed()!
        model.unlike(api)
        XCTAssertEqual(try quoteCount(), 0)

        // A subsequent identical browse is a fresh TRANSIENT quote — NOT auto-re-liked.
        let refetchClient = FakeClient(random: [FetchedQuote(text: "Gone", author: "G")])
        let refetch = makeModel(scope: ScopeBox(.online), client: refetchClient)
        await refetch.browseNext()
        XCTAssertEqual(refetch.browsing?.text, "Gone")
        XCTAssertEqual(try quoteCount(), 0, "re-fetch same dedupKey → transient, no auto-re-like (ADR-035)")
    }

    // MARK: - Source picker WRITES the persisted scope (ADR-040)

    func testSourcePickerWritesPersistedScopeAndServiceReadsIt() async throws {
        // A shared scope box stands in for T1's persisted settings layer (single owner).
        let box = ScopeBox(.online)
        let model = makeModel(scope: box)
        XCTAssertEqual(model.scope, .online, "reflects the persisted scope")

        // The picker WRITES the scope (ADR-040).
        model.setScope(.mine)
        XCTAssertEqual(box.scope, .mine, "picker WROTE the persisted scope")
        XCTAssertEqual(model.scope, .mine)

        // T5 READS the SAME persisted scope on its next resolution (ADR-040).
        let user = try context.fetch(FetchDescriptor<Quote>())   // sanity
        XCTAssertTrue(user.isEmpty)
        _ = model.addUserQuote(text: "Local pick", author: "Me")
        let service = makeService(scope: box)
        XCTAssertEqual(service.scope, .mine, "T5 reads the scope the picker wrote")
        let resolved = await service.todaysQuote()
        guard case let .quote(q) = resolved else {
            return XCTFail("expected a mine pick after scope write")
        }
        XCTAssertEqual(q.source, .user, "T5's mine pick uses the library the picker's scope selected")
        XCTAssertEqual(q.text, "Local pick")
    }

    func testSetSameScopeIsNoOp() {
        let box = ScopeBox(.mine)
        let model = makeModel(scope: box)
        model.setScope(.mine)   // unchanged
        XCTAssertEqual(box.scope, .mine)
    }
}
