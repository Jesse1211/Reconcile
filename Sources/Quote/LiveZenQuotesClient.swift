import Foundation

/// The production `ZenQuotesClient` (ADR-012): a read-only, key-less HTTP client
/// for ZenQuotes with a ~10s single-request timeout (ADR-013).
///
/// ZenQuotes returns a JSON array of `{ "q": <text>, "a": <author>, ... }`. Both
/// `/today` and `/random` share that shape; this client parses the FIRST element.
/// No aggressive auto-retry, no content moderation (ADR-013) — a single request,
/// mapped to a ``ZenQuotesError`` on failure so the service can surface error+retry.
public struct LiveZenQuotesClient: ZenQuotesClient {
    /// Base URL for the ZenQuotes API (ADR-012, no API key).
    private let baseURL: URL
    /// Single-request timeout budget (~10s, ADR-013).
    private let timeout: TimeInterval
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://zenquotes.io/api")!,
        timeout: TimeInterval = 10,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.session = session
    }

    public func today() async throws -> FetchedQuote {
        try await fetch(path: "today")
    }

    public func random() async throws -> FetchedQuote {
        try await fetch(path: "random")
    }

    private func fetch(path: String) async throws -> FetchedQuote {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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

    /// Parse ZenQuotes' `[{ "q": ..., "a": ... }]` payload into a `FetchedQuote`.
    static func parse(_ data: Data) throws -> FetchedQuote {
        struct Row: Decodable {
            let q: String
            let a: String?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        guard let first = rows.first, !first.q.isEmpty else {
            throw ZenQuotesError.badResponse
        }
        return FetchedQuote(text: first.q, author: first.a)
    }
}
