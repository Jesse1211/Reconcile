import Foundation
import SwiftData

/// The resolved value for today's quote area (ADR-011/-013/-034).
///
/// The UI renders one of these three states for the currently-selected scope.
public enum TodaysQuote: Equatable {
    /// A quote to show. `source` records where it came from; `persistedID` is the
    /// backing `Quote`'s identity when it lives in the library, else `nil` for a
    /// TRANSIENT online quote (ADR-013 — never a `Quote` row until liked, ADR-010).
    case quote(ResolvedQuote)
    /// The guiding empty state (`mine` + empty pool, ADR-033/-034). No fetch performed.
    case empty
    /// `online` fetch failed — surface error + retry (ADR-013). No local fallback.
    case error(ZenQuotesError)
}

/// A quote resolved for display (ADR-011). Carries just enough to render + to know
/// whether it is a persisted library row or a transient online quote.
public struct ResolvedQuote: Equatable {
    public let text: String
    public let author: String?
    public let source: QuoteSource
    /// The backing library `Quote`'s identity, or `nil` for a transient online quote.
    public let persistedID: PersistentIdentifier?
    /// `true` iff this is a transient online quote (no `Quote` row, ADR-013/-034).
    public var isTransientOnline: Bool { persistedID == nil && source == .api }

    public init(text: String, author: String?, source: QuoteSource, persistedID: PersistentIdentifier?) {
        self.text = text
        self.author = author
        self.source = source
        self.persistedID = persistedID
    }

    var dedupKey: String { QuoteNormalization.dedupKey(text: text, author: author) }
}

/// The quote service (T5): source selection, deterministic daily pick, like/persist/
/// dedup, user entry, ZenQuotes fetch + degrade, refresh, and source-dependent delete.
///
/// Cited ADRs: ADR-009, ADR-010, ADR-011, ADR-012, ADR-013, ADR-015, ADR-025,
/// ADR-026, ADR-027, ADR-034, ADR-035, ADR-039, INV-4, INV-9.
///
/// The service READS the current `TodayScope` from T1's settings layer (ADR-040) via
/// an injected accessor — it never persists a scope itself. The ZenQuotes boundary is
/// behind ``ZenQuotesClient`` so tests inject a fake. The online same-day result is
/// held in a TRANSIENT in-memory cache (ADR-013) and is NEVER persisted as a `Quote`
/// row (persistence is the ♡ like path only, ADR-010).
@MainActor
public final class QuoteService {
    let context: ModelContext
    let clock: Clock
    let client: ZenQuotesClient
    /// Reads the current scope from T1's settings layer (ADR-040). Injected so the
    /// service does not depend on `AppSettings` directly and stays testable.
    let scopeProvider: () -> TodayScope
    /// Reads the current online ``QuoteCategory`` from T1's settings layer (ADR-047),
    /// the SAME way scope is read. Injected (defaulting to `.any`) so the service does
    /// not depend on `AppSettings` directly and stays testable. Affects the `online`
    /// source ONLY — `mine` ignores it (ADR-047).
    let categoryProvider: () -> QuoteCategory
    /// The app-side widget snapshot writer (T12/ADR-042), invoked on quote
    /// pick/refresh/scope-change to mirror today's resolved quote into the widget
    /// (ADR-042 (b)). Optional and defaulting to `nil` so existing callers/tests are
    /// unaffected (additive/backward-compatible). T12 OWNS the writer; this flow only
    /// INVOKES it with the already-resolved quote (DESIGN T12 §2).
    let widgetWriter: WidgetSnapshotWriter?

    // MARK: Transient online cache (ADR-013)

    /// One same-day online daily result per (day, category) (ADR-013/-047). Held in
    /// memory only — NOT a `Quote` row (ADR-013). Reset when the day OR category key
    /// changes (a new day, or a category switch, fetches once). Scope is implicit:
    /// only `online` fetches/caches (`mine` never fetches, ADR-013).
    private var cachedTodayDay: Date?
    private var cachedTodayCategory: QuoteCategory?
    private var cachedTodayQuote: FetchedQuote?

    public init(
        context: ModelContext,
        clock: Clock,
        client: ZenQuotesClient,
        scope: @escaping () -> TodayScope,
        category: @escaping () -> QuoteCategory = { .any },
        widgetWriter: WidgetSnapshotWriter? = nil
    ) {
        self.context = context
        self.clock = clock
        self.client = client
        self.scopeProvider = scope
        self.categoryProvider = category
        self.widgetWriter = widgetWriter
    }

    /// Mirror a resolved `TodaysQuote` into the widget snapshot (T12/ADR-042 (b)).
    ///
    /// Called at the pick/refresh/scope-change transition points with the value the
    /// app itself shows — the writer does NOT re-derive or re-pick (ADR-041). A
    /// `.quote` writes its `text`+`author`; `.empty` (scope=`mine`, empty library,
    /// ADR-034) clears the quote → the widget shows the ADR-045 placeholder; an
    /// `.error` leaves the last-written quote intact (a transient online failure is
    /// not a reason to blank the widget). No-op when no writer is injected.
    func mirrorToWidget(_ resolved: TodaysQuote) {
        guard let widgetWriter else { return }
        switch resolved {
        case .quote(let q):
            widgetWriter.todaysQuoteResolved(text: q.text, author: q.author)
        case .empty:
            widgetWriter.todaysQuoteCleared()
        case .error:
            break   // keep last snapshot; ADR-013 error is transient, ADR-045 not blank
        }
    }

    /// The currently-selected scope, READ from T1's settings layer (ADR-040).
    public var scope: TodayScope { scopeProvider() }

    /// The currently-selected online category, READ from T1's settings layer (ADR-047).
    /// Affects the `online` source only.
    public var category: QuoteCategory { categoryProvider() }

    // MARK: - mine pool (ADR-011)

    /// The `mine` pool predicate (ADR-011): `source == user OR liked == true`.
    ///
    /// With no bundled content (ADR-015) and api rows existing only once liked, this
    /// is effectively the whole persisted library. Transient/unliked api quotes are
    /// never in the pool (they are not `Quote` rows at all, ADR-013).
    public func minePool() throws -> [Quote] {
        let all = try context.fetch(FetchDescriptor<Quote>())
        return all.filter { $0.source == .user || $0.liked }
    }

    // MARK: - Today's quote resolution (ADR-011/-013/-026/-034)

    /// Resolve today's quote for the active scope (ADR-011). Applies the (day, scope)
    /// override precedence (ADR-026), the dangling-`quoteRef` fallthrough (ADR-026 C3),
    /// and the `online` transient fetch + cache (ADR-013). `mine` NEVER fetches (ADR-013).
    public func todaysQuote() async -> TodaysQuote {
        let resolved = await resolveTodaysQuote()
        // T12/ADR-042 (b): mirror the resolved pick (or scope-change re-resolution)
        // into the widget snapshot — the SAME value the app shows (ADR-011/-026).
        mirrorToWidget(resolved)
        return resolved
    }

    /// The pure resolution of today's quote, WITHOUT the widget-mirror side effect —
    /// so internal callers (e.g. refresh's current-state probes) can resolve without
    /// re-triggering a snapshot write.
    private func resolveTodaysQuote() async -> TodaysQuote {
        let day = clock.today()
        let scope = self.scope
        // The override/cache key includes category for `online` (ADR-047); `mine` is
        // category-agnostic (always `.any`) since category does not affect the pool.
        let category = self.overrideCategory(for: scope)

        // (1) A same-day (day, scope, category) override takes precedence (ADR-026/-047),
        //     unless its local target row was hard-deleted same-day — ABSENT (C3).
        if let override = fetchOverrideRow(day: day, scope: scope, category: category) {
            if let resolved = resolveOverride(override) {
                return .quote(resolved)
            }
            // Dangling quoteRef → fall through to the deterministic pick (ADR-026 C3).
        }

        switch scope {
        case .mine:
            return resolveMineDeterministic(day: day)
        case .online:
            return await resolveOnlineDaily(day: day, category: category)
        }
    }

    /// The category component of the (day, scope, category) override/cache key (ADR-047):
    /// the selected category for `online`, always `.any` for `mine` (category-agnostic).
    func overrideCategory(for scope: TodayScope) -> QuoteCategory {
        scope == .online ? category : .any
    }

    /// The deterministic `mine` pick (ADR-011): empty pool → `.empty` (guiding state,
    /// no fetch); else the rendezvous pick. Never fetches (ADR-013).
    private func resolveMineDeterministic(day: Date) -> TodaysQuote {
        let pool = (try? minePool()) ?? []
        guard let picked = DailyQuotePicker.pick(from: pool, day: day, scope: .mine) else {
            return .empty
        }
        return .quote(ResolvedQuote(
            text: picked.text,
            author: picked.author,
            source: picked.source,
            persistedID: picked.persistentModelID
        ))
    }

    /// The `online` daily pick (ADR-011/-012): the `/today` quote, served from the
    /// transient same-day cache when present (ADR-013), else fetched once and cached.
    /// A transient online quote is NEVER persisted as a `Quote` row (ADR-013/-034).
    private func resolveOnlineDaily(day: Date, category: QuoteCategory) async -> TodaysQuote {
        if let cached = cachedTodayFetch(for: day, category: category) {
            return .quote(Self.transientResolved(cached))
        }
        do {
            // ADR-047: the mirror has no /today — the daily pick fetches /random for the
            // category and is CACHED per (day, category) to stay fixed for the day.
            let fetched = try await client.today(category: category)
            storeTodayCache(fetched, day: day, category: category)   // ADR-013: transient only
            return .quote(Self.transientResolved(fetched))
        } catch {
            return .error((error as? ZenQuotesError) ?? .offline)   // ADR-013: error + retry
        }
    }

    // MARK: - Override resolution (ADR-026)

    /// Resolve a (day, scope) override to a display quote, or `nil` when it is a
    /// dangling local ref (target hard-deleted same-day → treat as ABSENT, ADR-026 C3).
    func resolveOverride(_ override: DailySelectedQuote) -> ResolvedQuote? {
        if let ref = override.quoteRef {
            // Local `mine` override: dereference the persisted target (ADR-026). A FETCH
            // (not the registered-object cache) is used so a same-day hard-delete is seen.
            guard let target = fetchQuote(id: ref) else {
                return nil   // dangling ref → ABSENT (ADR-026 C3)
            }
            return ResolvedQuote(
                text: target.text,
                author: target.author,
                source: target.source,
                persistedID: target.persistentModelID
            )
        }
        // Transient online override: content stored INLINE (ADR-026 resolution (b)).
        guard let text = override.inlineText else { return nil }
        return ResolvedQuote(text: text, author: override.inlineAuthor, source: .api, persistedID: nil)
    }

    private func fetchQuote(id: PersistentIdentifier) -> Quote? {
        let all = (try? context.fetch(FetchDescriptor<Quote>())) ?? []
        return all.first { $0.persistentModelID == id }
    }

    /// The (day, scope, category) override row (ADR-026/-047), or `nil`. Stale
    /// (day < today) records are INERT (never matched here) and are not pruned.
    /// The category component is `.any` for `mine` (category-agnostic, ADR-047).
    func fetchOverrideRow(day: Date, scope: TodayScope, category: QuoteCategory) -> DailySelectedQuote? {
        let all = (try? context.fetch(FetchDescriptor<DailySelectedQuote>())) ?? []
        return all.first { $0.day == day && $0.scope == scope && $0.category == category }
    }

    /// Resolve a stored override to a display quote, or `nil` when its local `quoteRef`
    /// is dangling (target hard-deleted same-day → ABSENT, ADR-026 C3).
    func resolvedFromOverride(_ override: DailySelectedQuote) -> ResolvedQuote? {
        resolveOverride(override)
    }

    /// The current wall-clock instant from the injectable `Clock` (ADR-038).
    func clockNow() -> Date { clock.now() }

    // MARK: - Transient online cache helpers (ADR-013)

    private func cachedTodayFetch(for day: Date, category: QuoteCategory) -> FetchedQuote? {
        guard cachedTodayDay == day, cachedTodayCategory == category else { return nil }
        return cachedTodayQuote
    }

    private func storeTodayCache(_ quote: FetchedQuote, day: Date, category: QuoteCategory) {
        cachedTodayDay = day
        cachedTodayCategory = category
        cachedTodayQuote = quote
    }

    private static func transientResolved(_ fetched: FetchedQuote) -> ResolvedQuote {
        ResolvedQuote(text: fetched.text, author: fetched.author, source: .api, persistedID: nil)
    }
}
