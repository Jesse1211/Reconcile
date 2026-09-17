import XCTest
import SwiftData
@testable import Reconcile

/// T8 gate — Library screen logic (ADR-009/-010/-011/-033/-035/-052).
///
/// The gate asserts these paths "via the service, not just UI", so the tests drive
/// ``LibraryViewModel`` (which routes ALL persistence through the T5 ``QuoteService``)
/// and read back the real on-disk store. REAL_STACK isolation (E4): a UNIQUE temporary
/// on-disk SwiftData store per test, deleted in `tearDown`; the `Clock` is injected;
/// ZenQuotes is a FAKE injected client.
///
/// The Library is Delete-only and has no in-screen Discover-online or source-picker UI
/// (ADR-052); those flows — and their tests — were removed. Un-like remains a service /
/// model concern (ADR-039), covered in QuoteServiceTests / ModelInvariantTests.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    // MARK: Fake ZenQuotes client

    final class FakeClient: ZenQuotesClient {
        var todayQuote: FetchedQuote
        var randomQuotes: [FetchedQuote]
        var throwsError: ZenQuotesError?

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
            if let e = throwsError { throw e }
            return todayQuote
        }

        func random(category: QuoteCategory) async throws -> FetchedQuote {
            if let e = throwsError { throw e }
            return randomQuotes[0]
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
        return LibraryViewModel(service: service)
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

    // MARK: - Delete (ADR-035 / ADR-052 Delete-only swipe)

    func testDeleteUserRowRemovesIt() throws {
        let model = makeModel(scope: ScopeBox(.mine))
        let user = model.addUserQuote(text: "Delete this", author: nil)!
        XCTAssertEqual(try quoteCount(), 1)

        model.delete(user)
        XCTAssertEqual(try quoteCount(), 0, "explicit delete of a user row removes it (ADR-035)")
        XCTAssertTrue(model.isEmpty)
    }
}
