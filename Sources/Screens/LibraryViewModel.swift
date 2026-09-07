import Foundation
import SwiftData
import Combine

/// The presentation/logic layer for the Library screen (T8).
///
/// Cited ADRs: ADR-009 (two sources, both first-release), ADR-010 (like = persist a
/// transient api quote; user entry goes straight in), ADR-011 (`mine` pool predicate
/// `source == user OR liked == true`), ADR-012 (browse-online-and-like uses ZenQuotes
/// `/random`, NEVER `/today`), ADR-033 (purposeful empty state), ADR-035/ADR-039
/// (source-dependent delete / un-like), ADR-040 (the source picker WRITES the persisted
/// current `TodayScope` owned by T1's settings layer — T5 reads it).
///
/// All persistence flows through the T5 ``QuoteService`` (browse-and-like, add, delete,
/// un-like) so the Library never re-implements the like/dedup/source rules — the gate
/// verifies these paths "via the service, not just UI". The scope write goes to the
/// injected settings sink (``AppSettings.todayScope``), the SINGLE persisted-scope owner.
@MainActor
public final class LibraryViewModel: ObservableObject {
    /// The T5 quote service — the SOLE owner of like/persist/dedup/delete rules.
    private let service: QuoteService

    /// Reads the currently-persisted scope (ADR-040). The picker's binding uses this
    /// as its source of truth and writes through ``setScope(_:)``.
    private let scopeGetter: () -> TodayScope
    /// WRITES the persisted current scope into T1's settings layer (ADR-040). The
    /// Library is the ONLY component that writes the scope; T5 reads it.
    private let scopeSetter: (TodayScope) -> Void

    // MARK: Published UI state

    /// The library list (the `mine` pool, ADR-011): `source == user OR liked == true`,
    /// stably sorted by `dedupKey` so the order is deterministic (mirrors ADR-011's
    /// stable-sort rule) and does not jump as rows are added.
    @Published public private(set) var quotes: [Quote] = []

    /// The transient online quote currently being browsed (ADR-012/-013), if any. NOT a
    /// `Quote` row — it becomes one only when the user ♡ likes it (ADR-010).
    @Published public private(set) var browsing: FetchedQuote?

    /// `true` while a `/random` browse fetch is in flight (loading state).
    @Published public private(set) var isBrowsing: Bool = false

    /// The last browse error (ADR-013), surfaced as an inline retry affordance.
    @Published public private(set) var browseError: ZenQuotesError?

    public init(
        service: QuoteService,
        scope: @escaping () -> TodayScope,
        setScope: @escaping (TodayScope) -> Void
    ) {
        self.service = service
        self.scopeGetter = scope
        self.scopeSetter = setScope
    }

    // MARK: - List (ADR-011 mine predicate)

    /// Reload the library list from the store (the `mine` pool, ADR-011). Idempotent;
    /// call after any mutation so the view reflects the persisted truth.
    public func reload() {
        let pool = (try? service.minePool()) ?? []
        quotes = pool.sorted { $0.dedupKey < $1.dedupKey }
    }

    /// `true` when the library has no quotes → the screen shows the guiding empty state
    /// (ADR-033: "Your library is empty — save a quote you like").
    public var isEmpty: Bool { quotes.isEmpty }

    // MARK: - Manual add (ADR-009/-010)

    /// Add a user-entered quote straight into the library (ADR-009/-010): `source ==
    /// user`, inherently saved (no separate like). Deduped by `dedupKey` (INV-4). Blank
    /// text is rejected (returns `nil`); a blank author folds to `nil` (INV-4).
    @discardableResult
    public func addUserQuote(text rawText: String, author rawAuthor: String?) -> Quote? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let author = rawAuthor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAuthor = (author?.isEmpty ?? true) ? nil : author
        let row = try? service.addUserQuote(text: text, author: normalizedAuthor)
        reload()
        return row
    }

    // MARK: - Browse online + like (ADR-012/-010)

    /// Fetch a NEW online quote to browse via ZenQuotes `/random` (ADR-012 — browse-to-
    /// like uses `/random`, NEVER `/today`). The result is TRANSIENT (ADR-013): it is
    /// held only in ``browsing`` and does NOT create a `Quote` row until liked (ADR-010).
    public func browseNext() async {
        isBrowsing = true
        browseError = nil
        defer { isBrowsing = false }
        do {
            browsing = try await service.browseRandom()
        } catch {
            browsing = nil
            browseError = (error as? ZenQuotesError) ?? .offline
        }
    }

    /// Like (persist) the currently-browsed transient online quote into the library
    /// (ADR-010): inserts a `source == api, likedAt = now` row, DEDUPED by `dedupKey`
    /// (INV-4). Clears the browse slot afterward and reloads the list. No-op if nothing
    /// is being browsed. Returns the persisted row (existing or new).
    @discardableResult
    public func likeBrowsed() -> Quote? {
        guard let fetched = browsing else { return nil }
        let row = try? service.like(fetched)
        browsing = nil
        reload()
        return row
    }

    /// Dismiss the browsed quote WITHOUT liking it — it stays transient (ADR-013), no
    /// row is created.
    public func dismissBrowsed() {
        browsing = nil
    }

    // MARK: - Delete / un-like (ADR-035/-039)

    /// Un-like a library row — SOURCE-DEPENDENT (ADR-035/ADR-039/INV-9), via the service:
    ///   * `source == api`  → the row is REMOVED (un-like == hard delete; ADR-035).
    ///   * `source == user` → `likedAt` is cleared but the row is RETAINED (it stays in
    ///     the `mine` pool via `source == user`; ADR-039).
    public func unlike(_ quote: Quote) {
        try? service.unlike(quote)
        reload()
    }

    /// Explicitly delete a library row — HARD delete for either source (ADR-035): the row
    /// is removed entirely (no soft-delete/trash for quotes). This is the ONLY way to
    /// remove a `source == user` row.
    public func delete(_ quote: Quote) {
        try? service.delete(quote)
        reload()
    }

    // MARK: - Source picker (ADR-040)

    /// The currently-persisted scope (ADR-040), read from T1's settings layer.
    public var scope: TodayScope { scopeGetter() }

    /// WRITE the persisted current `TodayScope` into T1's settings layer (ADR-040). The
    /// Library source picker is the ONLY writer of the persisted scope; T5 reads it on
    /// its next daily-pick resolution. No-op if unchanged.
    public func setScope(_ newScope: TodayScope) {
        guard newScope != scopeGetter() else { return }
        scopeSetter(newScope)
        objectWillChange.send()
    }
}
