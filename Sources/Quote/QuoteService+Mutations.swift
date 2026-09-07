import Foundation
import SwiftData

// MARK: - Like / user-entry / un-like / delete (ADR-009/-010/-035/-039/INV-4/INV-9)

public extension QuoteService {
    /// Like (persist) a transient api quote into the library (ADR-010).
    ///
    /// Persists as `source == api, likedAt = now`, DEDUPED by `dedupKey` (INV-4): if a
    /// row already matches, `likedAt` is set on THAT row (no duplicate) — even when the
    /// existing row is `source == user` (a user duplicate the like lands on, ADR-010).
    /// Returns the row now representing the quote (existing or newly-inserted).
    @discardableResult
    func like(_ quote: FetchedQuote) throws -> Quote {
        let key = quote.dedupKey
        if let existing = try firstQuote(dedupKey: key) {
            existing.like(at: clockNow())        // INV-9: set likedAt on the EXISTING row
            try context.save()
            return existing
        }
        let row = Quote(text: quote.text, author: quote.author, source: .api, likedAt: clockNow())
        context.insert(row)
        try context.save()
        return row
    }

    /// Add a user-entered quote straight into the library (ADR-009/-010).
    ///
    /// User quotes need no separate like — they are inherently saved (`source == user`).
    /// Deduped by `dedupKey` (INV-4): entering a duplicate returns the existing row
    /// rather than inserting a second one.
    @discardableResult
    func addUserQuote(text: String, author: String?) throws -> Quote {
        let key = QuoteNormalization.dedupKey(text: text, author: author)
        if let existing = try firstQuote(dedupKey: key) {
            return existing
        }
        let row = Quote(text: text, author: author, source: .user)
        context.insert(row)
        try context.save()
        return row
    }

    /// Un-like a persisted quote — SOURCE-DEPENDENT (ADR-035/ADR-039/INV-9).
    ///
    ///   * `source == api`  → HARD-delete the row (un-like == delete; no "retain with
    ///     `likedAt = nil`" state for api rows, ADR-010/-035).
    ///   * `source == user` → clear `likedAt` but RETAIN the row (it stays in `mine`
    ///     via `source == user`, ADR-039).
    func unlike(_ quote: Quote) throws {
        switch quote.source {
        case .api:
            context.delete(quote)                 // ADR-035: api un-like == hard delete
        case .user:
            quote.unlike()                        // ADR-039: clear likedAt, RETAIN row
        }
        try context.save()
    }

    /// Explicitly delete a quote — HARD delete for either source (ADR-035).
    ///
    /// Removes the row entirely (no soft-delete/trash for quotes, unlike MIT's ADR-008).
    func delete(_ quote: Quote) throws {
        context.delete(quote)
        try context.save()
    }

    // MARK: - Browse-to-like (ADR-012 / T8)

    /// Fetch a fresh online quote to BROWSE for the Library's browse-and-like flow
    /// (ADR-012: browse-to-like uses ZenQuotes `/random`, NEVER `/today`).
    ///
    /// The returned quote is TRANSIENT (ADR-013): it is NOT persisted and does NOT write
    /// a (day, scope) override — browsing is a pure discovery read, distinct from the
    /// `online`-scope daily pick (`/today`, ADR-011) and the `online`-scope refresh
    /// override (`/random` written as the day's pick, ADR-025/-026). It becomes a `Quote`
    /// row only when the user ♡ likes it via ``like(_:)`` (ADR-010). Failures throw a
    /// ``ZenQuotesError`` for the caller to surface as error + retry (ADR-013).
    func browseRandom() async throws -> FetchedQuote {
        try await client.random()
    }

    // MARK: - Lookup

    /// The first persisted `Quote` whose `dedupKey` matches (INV-4), or `nil`.
    func firstQuote(dedupKey: String) throws -> Quote? {
        let all = try context.fetch(FetchDescriptor<Quote>())
        return all.first { $0.dedupKey == dedupKey }
    }
}

// MARK: - Refresh (ADR-025/-026/-027)

public extension QuoteService {
    /// Whether the ↻ refresh control is DISABLED for the active scope (ADR-027).
    ///
    /// Disabled ONLY for a degenerate FULLY-LOCAL `mine` pool with ≤1 selectable quote.
    /// `online` is NEVER disabled by pool size (ADR-027) — `/random` can always fetch a
    /// different quote (its failure is governed by ADR-013, not by disabling).
    func refreshDisabled() -> Bool {
        switch scope {
        case .online:
            return false
        case .mine:
            let pool = (try? minePool()) ?? []
            return pool.count <= 1
        }
    }

    /// Manually refresh the daily quote within the active scope (ADR-025/-026).
    ///
    ///   * `online` → fetch a DIFFERENT quote via `/random` (ADR-012/-025), persist as
    ///     the (day, scope) override stored INLINE (transient — no `likedAt`, not in the
    ///     library, ADR-026). Fetch failure surfaces `.error` (ADR-013).
    ///   * `mine` → a random DIFFERENT local quote (excluding the current, ADR-025),
    ///     persisted as the (day, scope) override via `quoteRef` to that existing row.
    ///
    /// Returns the new `TodaysQuote`. In `mine`, when the pool is degenerate (≤1
    /// selectable, ADR-027) refresh is a NO-OP that returns the current resolution.
    @discardableResult
    func refresh() async -> TodaysQuote {
        let day = clock.today()
        let resolved: TodaysQuote
        switch scope {
        case .mine:
            resolved = refreshMine(day: day)
        case .online:
            resolved = await refreshOnline(day: day)
        }
        // T12/ADR-042 (b): a refresh is a quote transition → mirror the refreshed
        // quote into the widget snapshot (the app's resolved value, ADR-025/-026).
        mirrorToWidget(resolved)
        return resolved
    }

    private func refreshMine(day: Date) -> TodaysQuote {
        // ADR-027: degenerate local pool ≤1 selectable → refresh disabled / no-op.
        if refreshDisabled() {
            return resolveCurrentForNoOp(day: day)
        }
        let pool = (try? minePool()) ?? []
        let current = currentResolvedQuote(day: day, scope: .mine)
        let currentRow = current.flatMap { resolved in
            pool.first { $0.dedupKey == resolved.dedupKey }
        }
        guard let picked = DailyQuotePicker.pickDifferent(
            from: pool, excluding: currentRow, day: day, scope: .mine
        ) else {
            return resolveCurrentForNoOp(day: day)
        }
        writeOverride(day: day, scope: .mine, localTarget: picked, inline: nil)
        return .quote(ResolvedQuote(
            text: picked.text, author: picked.author, source: picked.source,
            persistedID: picked.persistentModelID
        ))
    }

    private func refreshOnline(day: Date) async -> TodaysQuote {
        do {
            let fetched = try await client.random()   // ADR-012/-025: /random, genuinely different
            // ADR-026: store the transient online quote INLINE (quoteRef nil); NOT a Quote row.
            writeOverride(day: day, scope: .online, localTarget: nil, inline: fetched)
            return .quote(ResolvedQuote(text: fetched.text, author: fetched.author, source: .api, persistedID: nil))
        } catch {
            return .error((error as? ZenQuotesError) ?? .offline)   // ADR-013
        }
    }

    /// Write (upsert) the (day, scope) manual override (ADR-026, `isManualOverride=true`).
    /// A `mine` override references the local target via `quoteRef`; an `online` override
    /// stores the fetched quote INLINE (`inlineText`/`inlineAuthor`/`inlineDedupKey`).
    private func writeOverride(day: Date, scope: TodayScope, localTarget: Quote?, inline: FetchedQuote?) {
        // Replace any existing same-day (day, scope) override so it does not accumulate.
        if let existing = fetchOverrideRow(day: day, scope: scope) {
            context.delete(existing)
        }
        let record: DailySelectedQuote
        if let target = localTarget {
            record = DailySelectedQuote(
                day: day, scope: scope, quoteRef: target.persistentModelID, isManualOverride: true
            )
        } else if let fetched = inline {
            record = DailySelectedQuote.inline(
                day: day, scope: scope, text: fetched.text, author: fetched.author, isManualOverride: true
            )
        } else {
            return
        }
        context.insert(record)
        try? context.save()
    }

    // MARK: internal helpers reused by refresh

    /// The current resolved quote for a scope WITHOUT triggering an online fetch —
    /// used by `mine` refresh to know which quote to exclude.
    private func currentResolvedQuote(day: Date, scope: TodayScope) -> ResolvedQuote? {
        if let override = fetchOverrideRow(day: day, scope: scope),
           let resolved = resolvedFromOverride(override) {
            return resolved
        }
        guard scope == .mine else { return nil }
        let pool = (try? minePool()) ?? []
        guard let picked = DailyQuotePicker.pick(from: pool, day: day, scope: .mine) else { return nil }
        return ResolvedQuote(text: picked.text, author: picked.author, source: picked.source, persistedID: picked.persistentModelID)
    }

    private func resolveCurrentForNoOp(day: Date) -> TodaysQuote {
        if let resolved = currentResolvedQuote(day: day, scope: .mine) {
            return .quote(resolved)
        }
        return .empty
    }
}
