import Foundation

/// The source of today's quote (ADR-040/ADR-034).
///
/// The persisted current selection is owned by T1's settings layer (`AppSettings`) as
/// the SINGLE source of truth: T5 (quote service) READS it, the Settings screen WRITES it
/// (ADR-040). No other component persists a scope.
public enum TodayScope: String, CaseIterable, Codable, Sendable {
    /// The user's personal library pool.
    case mine
    /// The online (ZenQuotes) pick.
    case online

    /// Human-facing label for the source picker.
    public var displayName: String {
        switch self {
        case .mine: return "Mine"
        case .online: return "Online"
        }
    }
}
