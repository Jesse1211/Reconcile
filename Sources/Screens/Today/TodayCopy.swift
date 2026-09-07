import Foundation

/// Pinned, testable copy for the Today quote area and evening feeling (ADR-033/-034).
///
/// The guiding `mine`-empty line is pinned by ADR-034; keeping it here (not inline in
/// the view) lets a gate assert the exact intent without a UI harness.
public enum TodayCopy {
    /// The source indicator label for the active scope (ADR-011/-040).
    public static func sourceIndicator(for scope: TodayScope) -> String {
        switch scope {
        case .mine: return "From your library"
        case .online: return "Online"
        }
    }

    /// The guiding empty state for `mine` + empty pool (ADR-033/-034). NOT an error,
    /// NOT a blank view — invites the user to write one or switch to Online.
    public static let mineEmptyGuidance =
        "Your library is empty — write one, or switch to Online to discover."

    /// The `online`-failure line shown alongside the retry control (ADR-013).
    public static func onlineError(_ error: ZenQuotesError) -> String {
        switch error {
        case .timeout: return "That took too long. Check your connection and try again."
        case .offline: return "You're offline. Reconnect to load today's quote."
        case .badResponse: return "Couldn't read today's quote. Try again."
        }
    }

    // MARK: - Evening feeling (ADR-019/-020)

    /// The evening feeling section eyebrow (ADR-019).
    public static let feelingEyebrow = "This evening"
    /// The mood picker label (0-5 scale, ADR-019/-020).
    public static let moodLabel = "Mood"
    /// The stress picker label (0-5 scale, ADR-019/-020).
    public static let stressLabel = "Stress"
    /// The optional "why" field prompt (ADR-019/-020).
    public static let whyPrompt = "Why? (optional)"
    /// The feeling save button title.
    public static let feelingSaveTitle = "Save how today felt"
}
