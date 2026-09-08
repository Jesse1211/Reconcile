import XCTest
import SwiftData
@testable import Reconcile

/// T5 gate — Quote service (ADR-009/-010/-011/-012/-013/-015/-025/-026/-027/-034/-035/-039, INV-4/-9).
///
/// REAL_STACK isolation (E4): each test builds a UNIQUE temporary on-disk SwiftData
/// store in `setUp` and DELETES it in `tearDown`; the `ModelContainer` is rebuilt per
/// test and the `Clock` is injected — so "fresh store has zero rows" gates are reliable
/// and order-independent. ZenQuotes is a FAKE injected client.
@MainActor
final class QuoteServiceTests: XCTestCase {

    // MARK: Fake ZenQuotes client (test injection)

    /// A fake `ZenQuotesClient` (ADR-013 gate: tests inject a fake). Records call counts
    /// per endpoint and can be made to throw to exercise the `online` degrade path.
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

    // MARK: Real on-disk store (E4)

    private var storeURL: URL!
    private var container: ModelContainer!
    private var context: ModelContext!
    private var clock: TestClock!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuoteServiceTests-\(UUID().uuidString)", isDirectory: true)
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

    private func service(
        scope: TodayScope = .online,
        client: FakeClient = FakeClient()
    ) -> QuoteService {
        let current = scope
        return QuoteService(context: context, clock: clock, client: client, scope: { current })
    }

    /// Build a service whose scope is backed by a mutable box so a test can flip scope.
    private func service(scopeBox: ScopeBox, client: FakeClient = FakeClient()) -> QuoteService {
        QuoteService(context: context, clock: clock, client: client, scope: { scopeBox.scope })
    }

    /// Build a service with a fixed scope + a mutable CATEGORY box (ADR-047).
    private func service(scope: TodayScope, categoryBox: CategoryBox, client: FakeClient = FakeClient()) -> QuoteService {
        QuoteService(
            context: context, clock: clock, client: client,
            scope: { scope }, category: { categoryBox.category }
        )
    }

    final class ScopeBox { var scope: TodayScope; init(_ s: TodayScope) { scope = s } }
    final class CategoryBox { var category: QuoteCategory; init(_ c: QuoteCategory) { category = c } }

    private func quoteCount() throws -> Int {
        try context.fetch(FetchDescriptor<Quote>()).count
    }

    @discardableResult
    private func seedUser(_ text: String, _ author: String? = nil) throws -> Quote {
        let q = Quote(text: text, author: author, source: .user)
        context.insert(q)
        try context.save()
        return q
    }

    // MARK: - Daily pick determinism (ADR-011)

    func testDailyPickDeterministicSameDaySameScope() throws {
        try seedUser("Alpha"); try seedUser("Beta"); try seedUser("Gamma")
        let svc = service(scope: .mine)
        let a = DailyQuotePicker.pick(from: try svc.minePool(), day: clock.today(), scope: .mine)
        let b = DailyQuotePicker.pick(from: try svc.minePool(), day: clock.today(), scope: .mine)
        XCTAssertEqual(a?.dedupKey, b?.dedupKey)
    }

    // MARK: - Scope mine predicate (ADR-011)

    func testMineReturnsUserAndLikedOnly() throws {
        try seedUser("UserOne")
        let liked = Quote(text: "LikedApi", author: "A", source: .api, likedAt: clock.now())
        context.insert(liked)
        // A transient/unliked api row must NOT appear (source==api, likedAt nil).
        let unliked = Quote(text: "UnlikedApi", author: "B", source: .api)
        context.insert(unliked)
        try context.save()

        let pool = try service(scope: .mine).minePool()
        let texts = Set(pool.map { $0.text })
        XCTAssertEqual(texts, ["UserOne", "LikedApi"])
        XCTAssertFalse(texts.contains("UnlikedApi"))
    }

    // MARK: - Like persist + dedup (INV-4/ADR-010)

    func testLikePersistsAndDedups() throws {
        let svc = service(scope: .online)
        let fetched = FetchedQuote(text: "Persist me", author: "Auth")
        let first = try svc.like(fetched)
        XCTAssertEqual(try quoteCount(), 1)
        XCTAssertEqual(first.source, .api)
        XCTAssertNotNil(first.likedAt)
        // Liking the same one again does not duplicate.
        let second = try svc.like(fetched)
        XCTAssertEqual(try quoteCount(), 1)
        XCTAssertEqual(first.id, second.id)
    }

    // MARK: - Like dedups against an existing (user) row (ADR-010/INV-4)

    func testLikeSetsLikedAtOnExistingUserRow() throws {
        let svc = service(scope: .online)
        let user = try svc.addUserQuote(text: "Same words.", author: "Anonymous")
        XCTAssertNil(user.likedAt)
        XCTAssertEqual(try quoteCount(), 1)
        // An api quote whose dedupKey matches (curly/trailing-period/anonymous folded).
        let api = FetchedQuote(text: "same   words", author: nil)
        let liked = try svc.like(api)
        XCTAssertEqual(try quoteCount(), 1, "no new row on matching dedupKey")
        XCTAssertEqual(liked.id, user.id)
        XCTAssertEqual(liked.source, .user, "landed on the existing user row")
        XCTAssertNotNil(liked.likedAt, "likedAt set on the existing row")
    }

    // MARK: - online + offline (ADR-013)

    func testOnlineOfflineSurfacesErrorNoFallback() async throws {
        try seedUser("LocalFallbackShouldNOTBeUsed")
        let client = FakeClient(throwsError: .offline)
        let svc = service(scope: .online, client: client)
        let result = await svc.todaysQuote()
        guard case .error = result else { return XCTFail("expected .error, got \(result)") }
    }

    // MARK: - Cache (ADR-013): two same-day fetches hit network once

    func testSameDayFetchesHitNetworkOnce() async throws {
        let client = FakeClient()
        let svc = service(scope: .online, client: client)
        _ = await svc.todaysQuote()
        _ = await svc.todaysQuote()
        XCTAssertEqual(client.todayCalls, 1)
    }

    // MARK: - Transient online — no library populate (ADR-013/-026/-034)

    func testOnlineDailyFetchDoesNotPersistQuoteRow() async throws {
        let svc = service(scope: .online)
        let result = await svc.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertTrue(q.isTransientOnline)
        XCTAssertEqual(try quoteCount(), 0, "fresh store stays at ZERO Quote rows")
        // Only a ♡ like creates a row.
        try svc.like(FetchedQuote(text: q.text, author: q.author))
        XCTAssertEqual(try quoteCount(), 1)
        let row = try context.fetch(FetchDescriptor<Quote>()).first
        XCTAssertEqual(row?.source, .api)
        XCTAssertNotNil(row?.likedAt)
    }

    // MARK: - Service refresh (ADR-025)

    func testMineRefreshReturnsDifferentQuote() async throws {
        try seedUser("Alpha"); try seedUser("Beta"); try seedUser("Gamma")
        let svc = service(scope: .mine)
        let before = await svc.todaysQuote()
        guard case let .quote(cur) = before else { return XCTFail("expected quote") }
        let after = await svc.refresh()
        guard case let .quote(next) = after else { return XCTFail("expected quote") }
        XCTAssertNotEqual(cur.dedupKey, next.dedupKey, "mine refresh returns a DIFFERENT quote")
    }

    func testOnlineRefreshUsesRandomAndDiffersFromToday() async throws {
        let client = FakeClient(
            today: FetchedQuote(text: "TodayPick", author: "T"),
            random: [FetchedQuote(text: "RandomPick", author: "R")]
        )
        let svc = service(scope: .online, client: client)
        let before = await svc.todaysQuote()
        guard case let .quote(cur) = before else { return XCTFail("expected quote") }
        let after = await svc.refresh()
        guard case let .quote(next) = after else { return XCTFail("expected quote") }
        XCTAssertEqual(client.randomCalls, 1, "online refresh uses /random")
        XCTAssertNotEqual(cur.text, next.text, "refreshed quote differs from /today pick")
        XCTAssertEqual(next.text, "RandomPick")
    }

    // MARK: - Daily pick stable under pool growth (ADR-011)

    func testDailyPickStableUnderPoolGrowth() throws {
        // Seed a pool; find today's pick, then add quotes that sort AFTER it (larger
        // dedupKey) AND have a larger rendezvous score → the pick must stay the same.
        try seedUser("bbbbb"); try seedUser("ccccc"); try seedUser("ddddd")
        let svc = service(scope: .mine)
        let day = clock.today()
        let picked = DailyQuotePicker.pick(from: try svc.minePool(), day: day, scope: .mine)!
        let pickedKey = picked.dedupKey

        // Add later-sorting quotes; keep only those with a LARGER score than the pick
        // (guaranteed not to steal the rendezvous winner) — proves append-after stability.
        let seed = DailyQuotePicker.seedString(day: day, scope: .mine)
        let pickedScore = DailyQuotePicker.score(seed: seed, dedupKey: pickedKey)
        var added = 0
        for suffix in ["zzz1", "zzz2", "zzz3", "zzz4", "zzz5", "zzz6"] {
            let text = "zzzzz-\(suffix)"          // sorts after the alpha pool
            let key = QuoteNormalization.dedupKey(text: text, author: nil)
            if key > pickedKey, DailyQuotePicker.score(seed: seed, dedupKey: key) > pickedScore {
                try seedUser(text)
                added += 1
            }
        }
        XCTAssertGreaterThan(added, 0, "test should add at least one later-sorting quote")
        let repick = DailyQuotePicker.pick(from: try svc.minePool(), day: day, scope: .mine)!
        XCTAssertEqual(repick.dedupKey, pickedKey, "pick stable under later-sorting growth")
    }

    // MARK: - Refresh persists same-day, keyed by (day, scope), per-scope (ADR-026)

    func testOnlineRefreshOverridePersistsPerScopeAndStaysTransient() async throws {
        // A mine pool exists so a mine re-query yields mine's own pick.
        try seedUser("MineA"); try seedUser("MineB")
        let box = ScopeBox(.online)
        let client = FakeClient(
            today: FetchedQuote(text: "TodayPick", author: "T"),
            random: [FetchedQuote(text: "RefreshedOnline", author: "R")]
        )
        let svc = service(scopeBox: box, client: client)

        _ = await svc.todaysQuote()               // establishes /today
        let refreshed = await svc.refresh()       // online → /random override
        guard case let .quote(r) = refreshed else { return XCTFail("expected quote") }
        XCTAssertEqual(r.text, "RefreshedOnline")

        // Override stored as DailySelectedQuote(day, online), inline, isManualOverride, quoteRef nil.
        let overrides = try context.fetch(FetchDescriptor<DailySelectedQuote>())
        let online = overrides.first { $0.scope == .online }
        XCTAssertNotNil(online)
        XCTAssertTrue(online!.isManualOverride)
        XCTAssertNil(online!.quoteRef)
        XCTAssertEqual(online!.inlineText, "RefreshedOnline")
        XCTAssertEqual(try quoteCount(), 2, "online refresh did NOT create a Quote row (still just the 2 user rows)")

        // Simulated same-day reopen in ONLINE → refreshed quote (not /today).
        let reopened = service(scopeBox: box, client: client)   // fresh service, transient cache cleared
        box.scope = .online
        let onlineAgain = await reopened.todaysQuote()
        guard case let .quote(oa) = onlineAgain else { return XCTFail("expected quote") }
        XCTAssertEqual(oa.text, "RefreshedOnline", "same-day online re-query = refreshed override")

        // Switch to MINE same day → mine's OWN pick, NOT the online override.
        box.scope = .mine
        let mineAgain = await reopened.todaysQuote()
        guard case let .quote(ma) = mineAgain else { return XCTFail("expected quote") }
        XCTAssertNotEqual(ma.text, "RefreshedOnline", "online override must NOT leak into mine")
        XCTAssertTrue(["MineA", "MineB"].contains(ma.text))
    }

    // MARK: - Refresh override stays transient — no likedAt (ADR-026)

    func testOnlineRefreshOverrideSetsNoLikedAt() async throws {
        let svc = service(scope: .online, client: FakeClient(
            today: FetchedQuote(text: "T", author: nil),
            random: [FetchedQuote(text: "RefreshedNoLike", author: nil)]
        ))
        _ = await svc.todaysQuote()
        _ = await svc.refresh()
        XCTAssertEqual(try quoteCount(), 0, "refreshed online quote not in library")
        let anyLiked = try context.fetch(FetchDescriptor<Quote>()).contains { $0.likedAt != nil }
        XCTAssertFalse(anyLiked)
    }

    // MARK: - Degenerate pool (ADR-027)

    func testMineRefreshDisabledOnDegeneratePool() throws {
        // Empty pool → disabled.
        XCTAssertTrue(service(scope: .mine).refreshDisabled())
        // Singleton pool → disabled.
        try seedUser("Only")
        XCTAssertTrue(service(scope: .mine).refreshDisabled())
        // Two → enabled.
        try seedUser("Second")
        XCTAssertFalse(service(scope: .mine).refreshDisabled())
    }

    func testOnlineRefreshNeverDisabled() throws {
        // Even with an empty library, online refresh is never disabled by pool size.
        XCTAssertFalse(service(scope: .online).refreshDisabled())
    }

    // MARK: - Default scope + empty-library online (ADR-034)

    func testEmptyLibraryOnlineFetches() async throws {
        let client = FakeClient(today: FetchedQuote(text: "FirstRun", author: "Z"))
        let svc = service(scope: .online, client: client)
        let result = await svc.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertEqual(q.text, "FirstRun")
        XCTAssertEqual(client.todayCalls, 1)
        XCTAssertEqual(try quoteCount(), 0)
    }

    func testEmptyLibraryOnlineOfflineErrorRetry() async throws {
        let svc = service(scope: .online, client: FakeClient(throwsError: .offline))
        let result = await svc.todaysQuote()
        guard case .error = result else { return XCTFail("expected error+retry") }
    }

    // MARK: - Empty-library mine (ADR-034)

    func testEmptyLibraryMineGuidingEmptyStateNoFetch() async throws {
        let client = FakeClient()
        let svc = service(scope: .mine, client: client)
        let result = await svc.todaysQuote()
        guard case .empty = result else { return XCTFail("expected .empty") }
        XCTAssertEqual(client.todayCalls, 0, "mine never fetches")
        XCTAssertEqual(client.randomCalls, 0)
        XCTAssertTrue(svc.refreshDisabled())
    }

    // MARK: - Pick composition & pick() contract (ADR-011)

    func testPickContractEmptyReturnsNil() {
        XCTAssertNil(DailyQuotePicker.pick(from: [], day: clock.today(), scope: .mine))
    }

    func testPickContractSingletonReturnsThatElement() throws {
        let only = try seedUser("Lonely")
        let pool = try service(scope: .mine).minePool()
        XCTAssertEqual(pool.count, 1)
        let picked = DailyQuotePicker.pick(from: pool, day: clock.today(), scope: .mine)
        XCTAssertEqual(picked?.id, only.id)
    }

    func testPickCompositionOnlineIsToday() async throws {
        let client = FakeClient(today: FetchedQuote(text: "TheTodayQuote", author: "X"))
        let svc = service(scope: .online, client: client)
        let result = await svc.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertEqual(q.text, "TheTodayQuote")
        XCTAssertEqual(client.todayCalls, 1)
        XCTAssertEqual(client.randomCalls, 0, "daily online uses /today, not /random")
    }

    // MARK: - Un-like / delete is source-dependent (ADR-035/-039/INV-9)

    func testUnlikeUserRetainsRow() throws {
        let svc = service(scope: .mine)
        let user = try svc.addUserQuote(text: "MyOwn", author: "Me")
        user.like(at: clock.now())
        try context.save()
        try svc.unlike(user)
        XCTAssertEqual(try quoteCount(), 1, "user row RETAINED on un-like")
        XCTAssertNil(user.likedAt)
        XCTAssertTrue(try svc.minePool().contains { $0.id == user.id }, "still in mine via source==user")
    }

    func testUnlikeApiRemovesRow() throws {
        let svc = service(scope: .online)
        let api = try svc.like(FetchedQuote(text: "ApiLiked", author: "A"))
        XCTAssertEqual(try quoteCount(), 1)
        try svc.unlike(api)
        XCTAssertEqual(try quoteCount(), 0, "api un-like HARD-deletes (same as delete)")
    }

    func testDeleteUserRemovesRow() throws {
        let svc = service(scope: .mine)
        let user = try svc.addUserQuote(text: "DeleteMe", author: nil)
        try svc.delete(user)
        XCTAssertEqual(try quoteCount(), 0)
    }

    func testRefetchSameDedupKeyIsTransientNotAutoReliked() async throws {
        let svc = service(scope: .online)
        // Like then delete (un-like) an api quote.
        let api = try svc.like(FetchedQuote(text: "Gone", author: "G"))
        try svc.unlike(api)
        XCTAssertEqual(try quoteCount(), 0)
        // A subsequent identical fetch is a fresh TRANSIENT quote (no row, not liked).
        let refetch = service(scope: .online, client: FakeClient(today: FetchedQuote(text: "Gone", author: "G")))
        let result = await refetch.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertTrue(q.isTransientOnline)
        XCTAssertEqual(try quoteCount(), 0, "no auto-re-like; transient only")
    }

    // MARK: - Dangling quoteRef fallthrough (ADR-026 C3)

    func testDanglingQuoteRefFallsThroughToDeterministicPick() async throws {
        let a = try seedUser("Anchor-A")
        try seedUser("Anchor-B")
        let box = ScopeBox(.mine)
        let svc = service(scopeBox: box)
        let day = clock.today()

        // Manually pin a mine override to quote A.
        let override = DailySelectedQuote(day: day, scope: .mine, quoteRef: a.persistentModelID, isManualOverride: true)
        context.insert(override)
        try context.save()

        // Sanity: override resolves to A first.
        let pinned = await svc.todaysQuote()
        guard case let .quote(p) = pinned else { return XCTFail("expected quote") }
        XCTAssertEqual(p.text, "Anchor-A")

        // Hard-delete A the SAME day → override dangling → fall to deterministic pick.
        try svc.delete(a)
        let after = await svc.todaysQuote()
        guard case let .quote(q) = after else { return XCTFail("expected deterministic pick, no crash") }
        XCTAssertNotEqual(q.text, "Anchor-A")
        XCTAssertEqual(q.text, "Anchor-B", "fell through to the only remaining pool member")
    }

    // MARK: - Day-boundary override revert (ADR-026)

    func testOnlineOverrideRevertsNextDay() async throws {
        let box = ScopeBox(.online)
        let client = FakeClient(
            today: FetchedQuote(text: "DailyToday", author: "D"),
            random: [FetchedQuote(text: "Day1Override", author: "O")]
        )
        let svc = service(scopeBox: box, client: client)
        _ = await svc.todaysQuote()
        _ = await svc.refresh()                 // day1 override

        // Advance the Clock to day2.
        clock.advance(by: 86_400)
        let day2 = service(scopeBox: box, client: client)  // fresh service, cache cleared
        let result = await day2.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertEqual(q.text, "DailyToday", "day2 reverts to /today; day1 override inert")
    }

    // MARK: - REAL_STACK_GATE: like persists to real on-disk store and survives reload

    func testLikePersistsToOnDiskStoreAndReloads() throws {
        let svc = service(scope: .online)
        _ = try svc.like(FetchedQuote(text: "Durable quote", author: "Persist"))
        try context.save()

        // Reopen the SAME on-disk store in a fresh container/context.
        container = nil
        context = nil
        let config = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [config])
        let freshContext = ModelContext(reopened)
        let rows = try freshContext.fetch(FetchDescriptor<Quote>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text, "Durable quote")
        XCTAssertEqual(rows.first?.source, .api)
        XCTAssertNotNil(rows.first?.likedAt)
        container = reopened
        context = freshContext
    }

    // MARK: - Category (ADR-047)

    /// Slug mapping: `.any` → nil (no tag filter); `.humor` → `"humorous"`; the rest
    /// map to their own lowercase raw value.
    func testCategorySlugMapping() {
        XCTAssertNil(QuoteCategory.any.tagSlug)
        XCTAssertEqual(QuoteCategory.humor.tagSlug, "humorous")
        XCTAssertEqual(QuoteCategory.wisdom.tagSlug, "wisdom")
        XCTAssertEqual(QuoteCategory.love.tagSlug, "love")
        XCTAssertEqual(QuoteCategory.motivational.tagSlug, "motivational")
        // Every non-any case has a non-nil slug; only humor differs from its raw value.
        for c in QuoteCategory.allCases where c != .any {
            XCTAssertNotNil(c.tagSlug)
            if c != .humor { XCTAssertEqual(c.tagSlug, c.rawValue) }
        }
    }

    /// The online daily fetch passes the SELECTED category to the client (ADR-047).
    func testOnlineDailyFetchPassesSelectedCategory() async throws {
        let client = FakeClient(today: FetchedQuote(text: "WisdomPick", author: "W"))
        let svc = service(scope: .online, categoryBox: CategoryBox(.wisdom), client: client)
        _ = await svc.todaysQuote()
        XCTAssertEqual(client.lastTodayCategory, .wisdom)
    }

    /// Same day + SAME category → same cached quote, fetched only once (ADR-013/-047).
    func testOnlineDailyCachedPerCategorySameCategory() async throws {
        let client = FakeClient(today: FetchedQuote(text: "Cached", author: "C"))
        let svc = service(scope: .online, categoryBox: CategoryBox(.success), client: client)
        _ = await svc.todaysQuote()
        _ = await svc.todaysQuote()
        XCTAssertEqual(client.todayCalls, 1, "same (day, category) hits the network once")
    }

    /// Changing the category the SAME day fetches AGAIN (a new (day, category) key),
    /// and the daily fetch carries the new category (ADR-047).
    func testChangingCategorySameDayRefetches() async throws {
        let box = CategoryBox(.wisdom)
        let client = FakeClient(today: FetchedQuote(text: "Any/Wisdom", author: "X"))
        let svc = service(scope: .online, categoryBox: box, client: client)

        _ = await svc.todaysQuote()
        XCTAssertEqual(client.todayCalls, 1)
        XCTAssertEqual(client.lastTodayCategory, .wisdom)

        box.category = .humor                    // user switches category, same day
        _ = await svc.todaysQuote()
        XCTAssertEqual(client.todayCalls, 2, "a category switch is a new (day, category) → refetch")
        XCTAssertEqual(client.lastTodayCategory, .humor)
    }

    /// `mine` scope IGNORES the category — it never fetches and never keys on category
    /// (ADR-047). The client is untouched regardless of the selected category.
    func testMineScopeIgnoresCategory() async throws {
        try seedUser("MineOnly")
        let client = FakeClient()
        let svc = service(scope: .mine, categoryBox: CategoryBox(.love), client: client)
        let result = await svc.todaysQuote()
        guard case let .quote(q) = result else { return XCTFail("expected quote") }
        XCTAssertEqual(q.text, "MineOnly")
        XCTAssertEqual(client.todayCalls, 0, "mine never fetches (category irrelevant)")
        XCTAssertEqual(client.randomCalls, 0)
    }

    /// The (day, scope, category) override is category-scoped: an `online` refresh under
    /// one category does NOT apply after the user switches to another category (ADR-047).
    func testOnlineRefreshOverrideKeyedByCategory() async throws {
        let box = CategoryBox(.wisdom)
        let client = FakeClient(
            today: FetchedQuote(text: "DailyWisdom", author: "D"),
            random: [FetchedQuote(text: "RefreshedWisdom", author: "R")]
        )
        let svc = service(scope: .online, categoryBox: box, client: client)

        _ = await svc.todaysQuote()               // daily for wisdom
        let refreshed = await svc.refresh()       // wisdom override
        guard case let .quote(r) = refreshed, r.text == "RefreshedWisdom" else {
            return XCTFail("expected refreshed wisdom quote")
        }

        // Switch category same day → the wisdom override must NOT apply; a fresh daily
        // fetch for the new category happens instead.
        box.category = .humor
        let humor = await svc.todaysQuote()
        guard case let .quote(h) = humor else { return XCTFail("expected quote") }
        XCTAssertNotEqual(h.text, "RefreshedWisdom", "wisdom override must not leak into humor")
        XCTAssertEqual(client.lastTodayCategory, .humor)
    }
}
