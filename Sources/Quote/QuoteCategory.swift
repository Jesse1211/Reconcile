import Foundation

/// The user-chosen CATEGORY that filters the ONLINE quote source (ADR-047).
///
/// A small CURATED set (owner decision, ADR-047) — NOT the online mirror's 100+ tags,
/// and NO `/tags` network call. `.any` applies no tag filter (`GET /random`); every
/// other case maps to a LOWERCASE tag slug the online mirror understands
/// (`GET /random?tags=<slug>`).
///
/// Category affects the `online` source ONLY (ADR-047). The `mine` (local library)
/// pool is never filtered by category.
public enum QuoteCategory: String, CaseIterable, Codable, Sendable {
    case any
    case inspirational
    case wisdom
    case happiness
    case success
    case love
    case humor
    case motivational
    case life

    /// Human-facing label for the category picker (ADR-046/-047).
    public var displayName: String {
        switch self {
        case .any:           return "Any"
        case .inspirational: return "Inspirational"
        case .wisdom:        return "Wisdom"
        case .happiness:     return "Happiness"
        case .success:       return "Success"
        case .love:          return "Love"
        case .humor:         return "Humor"
        case .motivational:  return "Motivational"
        case .life:          return "Life"
        }
    }

    /// The online mirror's LOWERCASE tag slug for this category, or `nil` for `.any`
    /// (no tag filter). The mirror's humour tag is spelled `humorous`, so `.humor`
    /// maps to `"humorous"`; every other case maps to its own lowercase raw value
    /// (ADR-047).
    public var tagSlug: String? {
        switch self {
        case .any:   return nil
        case .humor: return "humorous"
        default:     return rawValue
        }
    }
}
