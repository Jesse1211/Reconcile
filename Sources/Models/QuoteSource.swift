import Foundation

/// The origin of a `Quote` (ADR-002).
///
/// `user` quotes are authored/added by the person; `api` quotes are fetched from
/// the online provider (ZenQuotes). Stored as a raw `String` so the value is
/// stable across SwiftData migrations.
public enum QuoteSource: String, CaseIterable, Codable, Sendable {
    /// Added by the user in their personal library.
    case user
    /// Fetched from the online quote provider.
    case api
}
