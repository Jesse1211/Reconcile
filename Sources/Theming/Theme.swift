import Foundation

/// The app's single visual theme (ADR-022; Day Arc removed).
///
/// Screens are authored once against the token contract: they read tokens by role from
/// the SwiftUI `Environment` and never hard-code a color or font (ADR-036). The enum is
/// retained (rather than collapsed away) because it is the persisted setting type and the
/// palette selector; a stored, now-removed raw value ("dayArc") decodes to `nil` and the
/// settings layer falls back to `.ledger`.
public enum Theme: String, CaseIterable, Codable, Sendable {
    /// Paper/ink neutrals, serif + mono, ruled columns, ledger-red accent.
    case ledger

    public var displayName: String {
        switch self {
        case .ledger: return "Ledger"
        }
    }
}
