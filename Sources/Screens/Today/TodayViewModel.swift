import Foundation
import SwiftData
import SwiftUI

/// The presenter for the Today screen (T7).
///
/// Owns the observable state the Today view renders and drives every mutation through
/// the T4 (``MITService``), T5 (``QuoteService``) and T11 (``DailyFeelingService``)
/// services — it adds NO new business rules of its own. The screen itself is a thin,
/// theme-agnostic SwiftUI layer (ADR-036/-037) that reads this state and calls these
/// intents. Keeping the logic here (an `@MainActor ObservableObject`, like the app's
/// other services) makes the Today behaviour unit-testable without a UI harness.
///
/// Cited ADRs: ADR-004 (MIT same-day mutable / cross-day lock), ADR-005 (rollover on
/// open), ADR-008/-030 (soft delete + cross-midnight undo), ADR-010 (♡ like persists),
/// ADR-013 (online loading/error/retry), ADR-019/-020 (evening feeling upsert),
/// ADR-024 (intention ritual save), ADR-025/-027 (refresh + degenerate-pool disable),
/// ADR-033/-034 (empty / first-run states).
@MainActor
public final class TodayViewModel: ObservableObject {

    // MARK: - Quote area state (ADR-011/-013/-033/-034)

    /// The render state of Today's quote area. Mirrors ``TodaysQuote`` but adds the
    /// UI-only `loading` state (ADR-013) that exists while an `online` fetch is in
    /// flight — the service returns a resolved value, the *loading* is the UI's.
    public enum QuoteAreaState: Equatable {
        /// No resolution yet / a fetch is in flight (ADR-013 loading state).
        case loading
        /// A quote to show (persisted library row or transient online quote).
        case quote(ResolvedQuote)
        /// `mine` + empty pool → guiding empty state (ADR-033/-034). Not an error.
        case empty
        /// `online` fetch failed → error + retry (ADR-013). No local fallback.
        case error(ZenQuotesError)
    }

    // MARK: - Published state

    /// The current quote-area render state (ADR-013/-033/-034).
    @Published public private(set) var quoteState: QuoteAreaState = .loading
    /// Today's open MIT list, rolled-in (ADR-005/-017). Sorted by the service.
    @Published public private(set) var mits: [MIT] = []
    /// Today's feeling entry if one has been captured, else `nil` (INV-7).
    @Published public private(set) var feeling: DailyFeeling?
    /// The most recent soft-delete, offered for undo (ADR-008/-030), else `nil`.
    @Published public private(set) var pendingUndo: PendingUndo?

    /// A soft-deleted MIT that can still be restored via the undo snackbar (ADR-008).
    public struct PendingUndo: Equatable {
        public let mit: MIT
        public static func == (lhs: PendingUndo, rhs: PendingUndo) -> Bool {
            lhs.mit === rhs.mit
        }
    }

    // MARK: - Dependencies

    let context: ModelContext
    let clock: Clock
    let quoteService: QuoteService
    let mitService: MITService
    let feelingService: DailyFeelingService
    /// Reads the active scope (ADR-040) so the quote area knows which source it renders.
    let scopeProvider: () -> TodayScope

    public init(
        context: ModelContext,
        clock: Clock,
        quoteService: QuoteService,
        mitService: MITService,
        feelingService: DailyFeelingService,
        scope: @escaping () -> TodayScope
    ) {
        self.context = context
        self.clock = clock
        self.quoteService = quoteService
        self.mitService = mitService
        self.feelingService = feelingService
        self.scopeProvider = scope
    }

    /// The active scope (ADR-040) — drives the source indicator + refresh-disable rule.
    public var scope: TodayScope { scopeProvider() }

    // MARK: - App-open / appear (ADR-005 rollover FIRST, then read)

    /// Refresh every section on appear. Runs the lazy MIT rollover FIRST (ADR-005 / D2)
    /// so past-due open MITs are advanced into today's list, then reloads the list, the
    /// feeling entry, and resolves the quote.
    public func onAppear() async {
        rolloverAndReloadMITs()
        reloadFeeling()
        await resolveQuote()
    }

    // MARK: - Quote area intents (ADR-010/-013/-025/-027)

    /// Resolve today's quote for the active scope (ADR-011/-013). Shows `loading` while
    /// an `online` fetch may be in flight, then the resolved state. `mine` never fetches.
    public func resolveQuote() async {
        quoteState = .loading
        let resolved = await quoteService.todaysQuote()
        quoteState = Self.map(resolved)
    }

    /// Manual ↻ refresh within the active scope (ADR-025). A degenerate `mine` pool
    /// (≤1 selectable, ADR-027) makes this a no-op; the button should be disabled via
    /// ``refreshDisabled``. `online` shows `loading` during the `/random` fetch.
    public func refreshQuote() async {
        guard !refreshDisabled else { return }
        if scope == .online { quoteState = .loading }
        let resolved = await quoteService.refresh()
        quoteState = Self.map(resolved)
    }

    /// Whether the ↻ control is disabled for the active scope (ADR-027): only a
    /// degenerate FULLY-LOCAL `mine` pool with ≤1 selectable quote. `online` is never
    /// disabled by pool size (its failure is governed by ADR-013).
    public var refreshDisabled: Bool {
        quoteService.refreshDisabled()
    }

    /// Retry the `online` fetch after an error (ADR-013). Same path as ``resolveQuote``.
    public func retryQuote() async {
        await resolveQuote()
    }

    /// Whether the currently-shown quote can be ♡ liked/saved (ADR-010).
    ///
    /// Only a TRANSIENT online quote that is NOT already in the library is likeable — a
    /// quote resolved from a library row, or one whose equivalent is already saved
    /// (`currentQuoteIsSaved`), is by definition already saved and offers no like.
    public var canLikeCurrentQuote: Bool {
        guard case .quote(let resolved) = quoteState, resolved.isTransientOnline else {
            return false
        }
        return !currentQuoteIsSaved
    }

    /// Whether the currently-shown quote is SAVED — determined by looking it up in the
    /// library by `dedupKey` (ADR-010/INV-4), not by session state. So the ♡ fills whenever
    /// an equivalent quote already lives in the library (liked before, or user-authored),
    /// and stays filled across re-resolve / reopen.
    public var currentQuoteIsSaved: Bool {
        guard case .quote(let resolved) = quoteState else { return false }
        // A locally-resolved library row is saved by construction; otherwise consult the
        // library by dedupKey so a transient online quote also reflects prior saves.
        if resolved.persistedID != nil { return true }
        return quoteService.isSavedInLibrary(text: resolved.text, author: resolved.author)
    }

    /// ♡ Save (like) the currently-shown transient online quote into the library
    /// (ADR-010, persists via T5). Deduped by `dedupKey` (INV-4). After a like the
    /// quote is a persisted row, so the state is re-resolved to reflect saved-ness.
    ///
    /// - Returns: the persisted `Quote`, or `nil` if the current quote is not a
    ///   likeable transient online quote (nothing to persist).
    @discardableResult
    public func likeCurrentQuote() async -> Quote? {
        guard case .quote(let resolved) = quoteState, resolved.isTransientOnline else {
            return nil
        }
        let fetched = FetchedQuote(text: resolved.text, author: resolved.author)
        guard let row = try? quoteService.like(fetched) else { return nil }
        // Reflect the now-saved state IN PLACE: keep showing the same quote, but carry the
        // persisted row's identity so `currentQuoteIsSaved` flips true and the ♡ fills.
        // (Do NOT re-resolve: for an online scope that would fetch a fresh TRANSIENT quote,
        // which has no persistedID and would leave the heart empty — the original bug.)
        quoteState = .quote(ResolvedQuote(
            text: resolved.text,
            author: resolved.author,
            source: .api,
            persistedID: row.persistentModelID
        ))
        return row
    }

    // MARK: - MIT intents (ADR-004/-005/-008/-024/-030)

    /// Run rollover (ADR-005) then reload today's open MIT list (ADR-017).
    public func rolloverAndReloadMITs() {
        _ = try? mitService.rollover(in: context)
        reloadMITs()
    }

    /// Reload today's open MIT list WITHOUT re-running rollover (ADR-017).
    public func reloadMITs() {
        mits = (try? mitService.todaysOpenMITs(in: context)) ?? []
    }

    /// Save the intention ritual (ADR-024): create a new MIT for TODAY with the one
    /// thing and an OPTIONAL reason (persisted to `MIT.reason`). Blank text is rejected
    /// (returns `nil`); a blank/whitespace reason is stored as `nil`.
    ///
    /// - Returns: the created MIT, or `nil` when `text` is blank.
    @discardableResult
    public func saveIntention(text: String, reason: String?) -> MIT? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleanReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mit = mitService.create(
            text: trimmed,
            reason: (cleanReason?.isEmpty ?? true) ? nil : cleanReason,
            in: context
        )
        try? context.save()
        reloadMITs()
        return mit
    }

    /// Edit an MIT's text/reason on the current local day (ADR-004). A cross-day
    /// historical MIT is read-only and the edit is REJECTED by the service. Persists
    /// the (optional) reason to `MIT.reason`.
    public func editMIT(_ mit: MIT, text: String? = nil, reason: String?? = nil) {
        try? mitService.edit(mit, text: text, reason: reason)
        try? context.save()
        reloadMITs()
    }

    /// Toggle an MIT complete/open on the current local day (ADR-004 / D1). Completing
    /// removes it from today's open list; the daily completed-count (ADR-006) tracks it.
    public func toggleComplete(_ mit: MIT) {
        try? mitService.toggleCompletion(mit)
        try? context.save()
        reloadMITs()
    }

    /// Soft-delete an MIT (ADR-008): it leaves the list but is retained for undo. Offers
    /// the delete for undo via ``pendingUndo`` (dismiss window is the UI's concern).
    public func softDelete(_ mit: MIT) {
        mitService.softDelete(mit)
        try? context.save()
        pendingUndo = PendingUndo(mit: mit)
        reloadMITs()
    }

    /// Undo the most recent soft-delete (ADR-008 / ADR-030). Cross-midnight-safe: an
    /// open restored MIT re-enters TODAY, never the now-locked previous day.
    public func undoDelete() {
        guard let pending = pendingUndo else { return }
        mitService.undoDelete(pending.mit)
        try? context.save()
        pendingUndo = nil
        rolloverAndReloadMITs()
    }

    /// Clear the pending-undo offer (the snackbar timed out / was dismissed).
    public func dismissUndo() {
        pendingUndo = nil
    }

    // MARK: - Empty / first-run (ADR-033/-034)

    /// Whether Today's MIT list is empty — drives the gentle first-run invitation line
    /// alongside the dashed intention placeholder row (ADR-033/-024).
    public var mitListIsEmpty: Bool { mits.isEmpty }

    // MARK: - Evening feeling (ADR-019/-020)

    /// Reload today's captured feeling, if any (INV-7). Read-only; never inserts.
    public func reloadFeeling() {
        feeling = try? feelingService.todaysFeeling(in: context)
    }

    /// Whether today's feeling entry is editable RIGHT NOW (INV-8). Today's is always
    /// editable; a historical (rolled) entry is read-only.
    public var feelingEditable: Bool {
        feelingService.isEditable(day: clock.today())
    }

    /// Save (UPSERT) today's evening feeling (ADR-019/-020): two `0...5` pickers (mood,
    /// stress) plus an optional "why". One-per-day: re-saving updates today's row in
    /// place (INV-7). A blank why is stored as `nil`.
    ///
    /// - Returns: the upserted feeling, or `nil` if the scales were out of range
    ///   (rejected, never clamped — INV-7). On success ``feeling`` is refreshed.
    @discardableResult
    public func saveFeeling(mood: Int, stress: Int, why: String?) -> DailyFeeling? {
        let cleanWhy = why?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (cleanWhy?.isEmpty ?? true) ? nil : cleanWhy
        let saved = try? feelingService.saveToday(
            mood: mood, stress: stress, whyText: stored, in: context
        )
        try? context.save()
        reloadFeeling()
        return saved
    }

    // MARK: - Mapping helpers

    /// Map a service ``TodaysQuote`` to a UI ``QuoteAreaState`` (never `loading` — that
    /// is a UI-only in-flight state the presenter sets around a fetch).
    static func map(_ resolved: TodaysQuote) -> QuoteAreaState {
        switch resolved {
        case .quote(let q): return .quote(q)
        case .empty: return .empty
        case .error(let e): return .error(e)
        }
    }
}
