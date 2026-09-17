import Foundation
import SwiftData
import Combine

/// The presentation/logic layer for the Library screen (T8).
///
/// Cited ADRs: ADR-009 (two sources, both first-release), ADR-010 (like = persist a
/// transient api quote; user entry goes straight in), ADR-011 (`mine` pool predicate
/// `source == user OR liked == true`), ADR-033 (purposeful empty state), ADR-035
/// (source-dependent / hard delete), ADR-052 (Library stripped down: Delete-only swipe,
/// no Discover-online UI, no in-screen source picker — the scope writer is Settings).
///
/// All persistence flows through the T5 ``QuoteService`` (add, delete) so the Library
/// never re-implements the like/dedup/source rules — the gate verifies these paths
/// "via the service, not just UI".
@MainActor
public final class LibraryViewModel: ObservableObject {
    /// The T5 quote service — the SOLE owner of like/persist/dedup/delete rules.
    private let service: QuoteService

    // MARK: Published UI state

    /// The library list (the `mine` pool, ADR-011): `source == user OR liked == true`,
    /// stably sorted by `dedupKey` so the order is deterministic (mirrors ADR-011's
    /// stable-sort rule) and does not jump as rows are added.
    @Published public private(set) var quotes: [Quote] = []

    public init(service: QuoteService) {
        self.service = service
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

    // MARK: - Delete (ADR-035)

    /// Explicitly delete a library row — HARD delete for either source (ADR-035): the row
    /// is removed entirely (no soft-delete/trash for quotes). This is the ONLY way to
    /// remove a `source == user` row. The Library swipe is Delete-only (ADR-052).
    public func delete(_ quote: Quote) {
        try? service.delete(quote)
        reload()
    }
}
