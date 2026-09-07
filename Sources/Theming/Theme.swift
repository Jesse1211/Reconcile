import Foundation

/// The two switchable visual themes (ADR-022).
///
/// Screens are authored once and themed twice: they read tokens by role from the
/// SwiftUI `Environment` and never hard-code a color or font (ADR-036).
public enum Theme: String, CaseIterable, Codable, Sendable {
    /// Paper/ink neutrals, serif + mono, ruled columns, ledger-red accent.
    case ledger
    /// Time-of-day gradient ground, glass cards; per-screen gradient via `screenRole`.
    case dayArc

    public var displayName: String {
        switch self {
        case .ledger: return "Ledger"
        case .dayArc: return "Day Arc"
        }
    }
}
