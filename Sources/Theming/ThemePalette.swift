import SwiftUI

/// Resolves the frozen token contract (ADR-036) for a concrete theme and screen role.
///
/// Each theme has exactly one palette. `tokens(for:)` returns a fully-populated
/// `ThemeTokens`, so both themes are guaranteed to supply every token role.
public protocol ThemePalette: Sendable {
    var theme: Theme { get }
    func tokens(for role: ScreenRole) -> ThemeTokens
}

public extension Theme {
    /// The palette that resolves this theme's tokens.
    var palette: ThemePalette {
        switch self {
        case .ledger: return LedgerPalette()
        case .dayArc: return DayArcPalette()
        }
    }

    /// Convenience: resolve tokens for this theme and a screen role (ADR-036/037).
    func tokens(for role: ScreenRole) -> ThemeTokens {
        palette.tokens(for: role)
    }
}

// MARK: - Ledger (ADR-022)

/// Paper/ink neutrals, serif + mono, a single ledger-red accent for carried items.
/// Ignores `screenRole` entirely (ADR-037): its neutrals are screen-independent, and
/// its gradient-anchor tokens are supplied as flat/neutral values so the set is total.
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
        divider: rule,
        // Flat/neutral values so the gradient-anchor set is total in Ledger too.
        gradientTop: paper,
        gradientMid: paper,
        gradientBottom: paper
    )

    private static let typography = ThemeTypography(
        display: .system(.largeTitle, design: .serif).weight(.semibold),
        title: .system(.title2, design: .serif).weight(.medium),
        body: .system(.body, design: .serif),
        mono: .system(.body, design: .monospaced),
        eyebrow: .system(.caption, design: .serif).weight(.semibold)
    )

    public func tokens(for role: ScreenRole) -> ThemeTokens {
        // Ledger IGNORES role (ADR-037): same tokens for every screen.
        ThemeTokens(
            theme: theme,
            screenRole: role,
            colors: Self.colors,
            typography: Self.typography
        )
    }
}

// MARK: - Day Arc (ADR-022)

/// A time-of-day gradient ground + glass cards. CONSUMES `screenRole` (ADR-037) to
/// pick per-screen gradient anchors: dawn on Today, midday on Timer, dusk on Summary,
/// and a distinct dim tone on Library.
public struct DayArcPalette: ThemePalette {
    public let theme: Theme = .dayArc
    public init() {}

    private static let background = Color(red: 0.06, green: 0.07, blue: 0.11)
    private static let surface = Color(white: 1.0, opacity: 0.06)
    private static let surfaceRaised = Color(white: 1.0, opacity: 0.12)
    private static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.98)
    private static let textSecondary = Color(red: 0.78, green: 0.80, blue: 0.86)
    private static let textMuted = Color(red: 0.55, green: 0.58, blue: 0.66)
    private static let accent = Color(red: 0.98, green: 0.72, blue: 0.36)
    private static let accentCarried = Color(red: 0.90, green: 0.40, blue: 0.42)
    private static let divider = Color(white: 1.0, opacity: 0.14)

    private static let typography = ThemeTypography(
        display: .system(.largeTitle, design: .rounded).weight(.bold),
        title: .system(.title2, design: .rounded).weight(.semibold),
        body: .system(.body, design: .default),
        mono: .system(.body, design: .monospaced),
        eyebrow: .system(.caption, design: .rounded).weight(.semibold)
    )

    /// Per-screen gradient anchors (ADR-037). Each role selects a distinct triple.
    private func gradientAnchors(for role: ScreenRole) -> (top: Color, mid: Color, bottom: Color) {
        switch role {
        case .today: // dawn
            return (
                Color(red: 0.98, green: 0.66, blue: 0.42),
                Color(red: 0.60, green: 0.44, blue: 0.62),
                Color(red: 0.12, green: 0.14, blue: 0.30)
            )
        case .timer: // midday
            return (
                Color(red: 0.42, green: 0.72, blue: 0.98),
                Color(red: 0.30, green: 0.52, blue: 0.82),
                Color(red: 0.10, green: 0.20, blue: 0.42)
            )
        case .library: // twilight neutral
            return (
                Color(red: 0.30, green: 0.30, blue: 0.44),
                Color(red: 0.20, green: 0.20, blue: 0.32),
                Color(red: 0.08, green: 0.08, blue: 0.16)
            )
        case .summary: // dusk
            return (
                Color(red: 0.86, green: 0.40, blue: 0.44),
                Color(red: 0.44, green: 0.26, blue: 0.52),
                Color(red: 0.10, green: 0.10, blue: 0.24)
            )
        }
    }

    public func tokens(for role: ScreenRole) -> ThemeTokens {
        let anchors = gradientAnchors(for: role)
        let colors = ThemeColors(
            background: Self.background,
            surface: Self.surface,
            surfaceRaised: Self.surfaceRaised,
            textPrimary: Self.textPrimary,
            textSecondary: Self.textSecondary,
            textMuted: Self.textMuted,
            accent: Self.accent,
            accentCarried: Self.accentCarried,
            divider: Self.divider,
            gradientTop: anchors.top,
            gradientMid: anchors.mid,
            gradientBottom: anchors.bottom
        )
        return ThemeTokens(
            theme: theme,
            screenRole: role,
            colors: colors,
            typography: Self.typography
        )
    }
}
