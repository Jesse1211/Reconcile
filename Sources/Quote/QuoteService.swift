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

    // MARK: Transient online cache (ADR-013)

    /// One same-day `/today` result per (day). Held in memory only — NOT a `Quote`
    /// row (ADR-013). Reset when the day key changes (a new day fetches once).
    private var cachedTodayDay: Date?
    private var cachedTodayQuote: FetchedQuote?

    public init(
        context: ModelContext,
        clock: Clock,
        client: ZenQuotesClient,
        scope: @escaping () -> TodayScope
    ) {
        self.context = context
        self.clock = clock
        self.client = client
        self.scopeProvider = scope
    }

    /// The currently-selected scope, READ from T1's settings layer (ADR-040).
    public var scope: TodayScope { scopeProvider() }

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
        let day = clock.today()
        let scope = self.scope

        // (1) A same-day (day, scope) override takes precedence (ADR-026), unless its
        //     local target row was hard-deleted same-day — then treat as ABSENT (C3).
        if let override = fetchOverrideRow(day: day, scope: scope) {
            if let resolved = resolveOverride(override) {
                return .quote(resolved)
            }
            // Dangling quoteRef → fall through to the deterministic pick (ADR-026 C3).
        }

        switch scope {
        case .mine:
            return resolveMineDeterministic(day: day)
        case .online:
            return await resolveOnlineDaily(day: day)
        }
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
    private func resolveOnlineDaily(day: Date) async -> TodaysQuote {
        if let cached = cachedTodayFetch(for: day) {
            return .quote(Self.transientResolved(cached))
        }
        do {
            let fetched = try await client.today()          // ADR-012: /today, deterministic
            storeTodayCache(fetched, day: day)               // ADR-013: transient in-memory only
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

    /// The (day, scope) override row (ADR-026), or `nil`. Stale (day < today) records
    /// are INERT (never matched here) and are not pruned.
    func fetchOverrideRow(day: Date, scope: TodayScope) -> DailySelectedQuote? {
        let all = (try? context.fetch(FetchDescriptor<DailySelectedQuote>())) ?? []
        return all.first { $0.day == day && $0.scope == scope }
    }

    /// Resolve a stored override to a display quote, or `nil` when its local `quoteRef`
    /// is dangling (target hard-deleted same-day → ABSENT, ADR-026 C3).
    func resolvedFromOverride(_ override: DailySelectedQuote) -> ResolvedQuote? {
        resolveOverride(override)
    }

    /// The current wall-clock instant from the injectable `Clock` (ADR-038).
    func clockNow() -> Date { clock.now() }

    // MARK: - Transient online cache helpers (ADR-013)

    private func cachedTodayFetch(for day: Date) -> FetchedQuote? {
        guard cachedTodayDay == day else { return nil }
        return cachedTodayQuote
    }

    private func storeTodayCache(_ quote: FetchedQuote, day: Date) {
        cachedTodayDay = day
        cachedTodayQuote = quote
    }

    private static func transientResolved(_ fetched: FetchedQuote) -> ResolvedQuote {
        ResolvedQuote(text: fetched.text, author: fetched.author, source: .api, persistedID: nil)
    }
}
