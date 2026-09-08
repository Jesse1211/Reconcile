import Foundation

/// The production `ZenQuotesClient` (ADR-047): a read-only, KEYLESS HTTP client for the
/// **quotable community mirror** (`quotable.vercel.app`) with a ~10s single-request
/// timeout (ADR-013).
///
/// The mirror has NO `/today`, so BOTH the daily pick and a refresh fetch `GET /random`
/// (with a `tags` query item when the ``QuoteCategory`` has a slug) — the service keeps
/// "one fixed quote per day" by CACHING the daily result per (day, scope, category)
/// (ADR-011/-013/-047). The response shape is a single object
/// `{ "content": <text>, "author": <string>, "tags": [<Capitalized>] }`.
///
/// No aggressive auto-retry, no content moderation (ADR-013) — a single request, mapped
/// to a ``ZenQuotesError`` on failure so the service can surface error+retry.
public struct LiveZenQuotesClient: ZenQuotesClient {
    /// Base URL for the quotable mirror (ADR-047, no API key).
    private let baseURL: URL
    /// Single-request timeout budget (~10s, ADR-013).
    private let timeout: TimeInterval
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://quotable.vercel.app")!,
        timeout: TimeInterval = 10,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    /// The daily online quote (ADR-047): the mirror has no `/today`, so this fetches
    /// `/random` for `category` — the SERVICE caches it per (day, scope, category) to
    /// keep the day's pick fixed (ADR-011/-013).
    public func today(category: QuoteCategory) async throws -> FetchedQuote {
        try await fetchRandom(category: category)
    }

    /// A genuinely different random quote for `category` (ADR-047) — refresh / browse.
    public func random(category: QuoteCategory) async throws -> FetchedQuote {
        try await fetchRandom(category: category)
    }

    private func fetchRandom(category: QuoteCategory) async throws -> FetchedQuote {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("random"), resolvingAgainstBaseURL: false
        )
        if let slug = category.tagSlug {
            components?.queryItems = [URLQueryItem(name: "tags", value: slug)]
        }
        guard let url = components?.url else { throw ZenQuotesError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ZenQuotesError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .dataNotAllowed, .cannotFindHost:
                throw ZenQuotesError.offline
            default:
                throw ZenQuotesError.offline
            }
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ZenQuotesError.badResponse
        }
        return try Self.parse(data)
    }

    /// Parse the mirror's `{ "content": ..., "author": ... }` object into a
    /// `FetchedQuote` (ADR-047). A JSON ARRAY form (defensive) parses its first element.
    static func parse(_ data: Data) throws -> FetchedQuote {
        struct Row: Decodable {
            let content: String
            let author: String?
        }
        let row: Row
        if let single = try? JSONDecoder().decode(Row.self, from: data) {
            row = single
        } else if let first = (try? JSONDecoder().decode([Row].self, from: data))?.first {
            row = first
        } else {
            throw ZenQuotesError.badResponse
        }
        guard !row.content.isEmpty else { throw ZenQuotesError.badResponse }
        return FetchedQuote(text: row.content, author: row.author)
    }
}
