import SwiftUI

/// Resolves the frozen token contract (ADR-036) for a concrete theme and screen role.
///
/// Each theme has exactly one palette. `tokens(for:)` returns a fully-populated
/// `ThemeTokens`, so a theme is guaranteed to supply every token role. `role` is the
/// single seam a future theme uses to vary presentation per screen (ADR-037); Ledger —
/// the only theme today — ignores it, but the parameter stays so screens can declare a
/// role a new palette can honour without touching call sites.
public protocol ThemePalette: Sendable {
    var theme: Theme { get }
    func tokens(for role: ScreenRole) -> ThemeTokens
}

public extension Theme {
    /// The palette that resolves this theme's tokens.
    var palette: ThemePalette {
        switch self {
        case .ledger: return LedgerPalette()
        }
    }

    /// Convenience: resolve tokens for this theme and a screen role (ADR-036/037).
    func tokens(for role: ScreenRole) -> ThemeTokens {
        palette.tokens(for: role)
    }
}

// MARK: - Ledger (ADR-022)

/// Paper/ink neutrals, serif + mono, a single ledger-red accent for carried items.
/// Ignores `screenRole` entirely (ADR-037): its neutrals are screen-independent.
public struct LedgerPalette: ThemePalette {
    public let theme: Theme = .ledger
    public init() {}

    private static let paper = Color(red: 0.98, green: 0.97, blue: 0.94)
    private static let paperRaised = Color(red: 1.0, green: 0.99, blue: 0.97)
    private static let surface = Color(red: 0.96, green: 0.95, blue: 0.91)
    private static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    private static let inkSoft = Color(red: 0.32, green: 0.30, blue: 0.27)
    private static let inkMuted = Color(red: 0.55, green: 0.52, blue: 0.48)
    private static let ledgerRed = Color(red: 0.62, green: 0.13, blue: 0.14)
    private static let rule = Color(red: 0.80, green: 0.77, blue: 0.71)

    private static let colors = ThemeColors(
        background: paper,
        surface: surface,
        surfaceRaised: paperRaised,
        textPrimary: ink,
        textSecondary: inkSoft,
        textMuted: inkMuted,
        accent: ledgerRed,
        accentCarried: ledgerRed,
        accentFill: ledgerRed,          // Ledger buttons stay the ledger-red fill…
        accentOnBackground: ledgerRed,  // …and glyphs/charts use the same ink-red on paper.
        likedAccent: ledgerRed,
        divider: rule
    )

    private static let typography = ThemeTypography(
        display: .system(.largeTitle, design: .serif).weight(.semibold),
        title: .system(.title2, design: .serif).weight(.medium),
        body: .system(.body, design: .serif),
        mono: .system(.body, design: .monospaced),
        eyebrow: .system(.caption, design: .serif).weight(.semibold)
    )

    public func tokens(for role: ScreenRole) -> ThemeTokens {
        // Ledger IGNORES role (ADR-037): same paper tokens for every screen.
        ThemeTokens(
            theme: theme,
            screenRole: role,
            colors: Self.colors,
            typography: Self.typography
        )
    }
}
