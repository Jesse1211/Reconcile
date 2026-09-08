import Foundation

/// A transient online quote fetched from ZenQuotes (ADR-012/-013).
///
/// This is NOT a persisted `Quote`. A displayed/refreshed online quote is held
/// only in memory for the day (ADR-013 transient cache) — it becomes a `Quote`
/// row ONLY when the user ♡ likes it (ADR-010). Its `dedupKey` (INV-4) is derived
/// so a like can dedup against an existing library row.
public struct FetchedQuote: Equatable, Sendable {
    /// The quote text.
    public let text: String
    /// Optional author (`nil`/`""`/`"Anonymous"` fold together for dedup, INV-4).
    public let author: String?

    public init(text: String, author: String?) {
        self.text = text
        self.author = author
    }

    /// The dedup key this quote WOULD produce if persisted (INV-4).
    public var dedupKey: String {
        QuoteNormalization.dedupKey(text: text, author: author)
    }
}

/// Errors surfaced by a `ZenQuotesClient` (ADR-013).
///
/// `online` scope has NO local content to fall back to, so a failure must surface
/// an error + retry (ADR-013) — never a silent fallback.
public enum ZenQuotesError: Error, Equatable, Sendable {
    /// The request timed out (~10s single-request budget, ADR-013).
    case timeout
    /// No network / transport failure.
    case offline
    /// The server returned an unexpected/unparseable response.
    case badResponse
}

/// The online-quote fetch boundary (ADR-012/-047), behind a protocol so tests inject
/// a fake.
///
/// Two fetches, each filtered by the user-chosen ``QuoteCategory`` (ADR-047 — affects
/// the `online` source only):
///   * `today(category:)`  — the DEFAULT daily online quote. The quotable mirror has
///     no `/today`, so the service fetches `GET /random?tags=<slug>` (or `/random`
///     for `.any`) and CACHES it per (day, scope, category) to keep "one fixed quote
///     per day" (ADR-011/-013/-047).
///   * `random(category:)` — a genuinely DIFFERENT quote for browse-to-like (T8) AND
///     `online`-scope manual refresh (ADR-025), via `GET /random?tags=<slug>`.
///
/// Both take a `category` defaulting to `.any` so existing call sites/tests compile
/// unchanged. The service owns caching (ADR-013 transient same-day cache) and never
/// persists a fetched quote as a `Quote` row — persistence is the ♡ like path only
/// (ADR-010).
public protocol ZenQuotesClient: Sendable {
    /// Fetch the daily online quote for `category` (ADR-047). `.any` applies no tag
    /// filter. The service caches the result per (day, scope, category), ADR-013.
    func today(category: QuoteCategory) async throws -> FetchedQuote
    /// Fetch a random quote for `category` (ADR-047) — refresh / browse-to-like.
    func random(category: QuoteCategory) async throws -> FetchedQuote
}

public extension ZenQuotesClient {
    /// Convenience overloads defaulting to `.any` so unfiltered call sites/tests
    /// (and conformers that only implement the categorized methods) stay concise.
    func today() async throws -> FetchedQuote { try await today(category: .any) }
    func random() async throws -> FetchedQuote { try await random(category: .any) }
}
