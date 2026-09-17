import Foundation

/// Pinned, testable copy for the Today quote area and evening feeling (ADR-033/-034).
///
/// The guiding `mine`-empty line is pinned by ADR-034; keeping it here (not inline in
/// the view) lets a gate assert the exact intent without a UI harness.
public enum TodayCopy {
    /// The source indicator label for the active scope (ADR-011/-040).
    public static func sourceIndicator(for scope: TodayScope) -> String {
        switch scope {
        case .mine: return "Saved"
        case .online: return "Online"
        }
    }

    /// The guiding empty state for `mine` + empty pool (ADR-033/-034). NOT an error,
    /// NOT a blank view — directs the user to add a quote in the Library (owner copy).
    public static let mineEmptyGuidance = "Add one in library"

    /// The `online`-failure line shown alongside the retry control (ADR-013).
    public static func onlineError(_ error: ZenQuotesError) -> String {
        switch error {
        case .timeout: return "That took too long. Check your connection and try again."
        case .offline: return "You're offline. Reconnect to load today's quote."
        case .badResponse: return "Couldn't read today's quote. Try again."
        }
    }
}
