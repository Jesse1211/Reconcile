import SwiftUI
import UIKit

/// Resolves the frozen token contract (ADR-036) for a concrete theme and screen role.
///
/// Each theme has exactly one palette. `tokens(for:)` returns a fully-populated
/// `ThemeTokens`, so both themes are guaranteed to supply every token role.
public protocol ThemePalette: Sendable {
    var theme: Theme { get }
    func tokens(for role: ScreenRole) -> ThemeTokens
    /// Resolve tokens for a role AND a fractional hour-of-day (0..<24). Day Arc uses the
    /// hour to interpolate its whole-app gradient across the day (ADR-037, revised); themes
    /// whose background does not depend on time ignore it. Defaults to `tokens(for:)`.
    func tokens(for role: ScreenRole, atHour hour: Double) -> ThemeTokens
}

public extension ThemePalette {
    /// Default: time-independent themes (e.g. Ledger) ignore the hour.
    func tokens(for role: ScreenRole, atHour hour: Double) -> ThemeTokens {
        tokens(for: role)
    }
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

// MARK: - Color interpolation (Day Arc time-of-day gradient)

private extension Color {
    /// Linearly interpolate this color toward `other` by `t` (0...1) in sRGB space.
    func mixed(with other: Color, _ t: Double) -> Color {
        let a = UIColor(self).rgba
        let b = UIColor(other).rgba
        let t = min(max(t, 0), 1)
        return Color(
            red:   a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue:  a.b + (b.b - a.b) * t,
            opacity: a.a + (b.a - a.a) * t
        )
    }
}

private extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - Day Arc (ADR-022)

/// A time-of-day gradient ground + glass cards. The gradient is driven by the REAL
/// current time (ADR-037, revised): the SAME background on every screen, interpolated
/// continuously across the day — dawn → midday → dusk → night → (next) dawn. `screenRole`
/// no longer varies the background (every page shares "the colour of the sky right now").
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

    /// Keyed gradient anchors at four times of day (fractional hour → triple). The live
    /// gradient interpolates between the two surrounding keys, wrapping across midnight.
    /// Times: dawn 06:00, midday 13:00, dusk 19:00, night 23:00.
    private typealias Triple = (top: Color, mid: Color, bottom: Color)
    private static let keyframes: [(hour: Double, colors: Triple)] = [
        (6,  (Color(red: 0.98, green: 0.66, blue: 0.42),   // dawn
              Color(red: 0.60, green: 0.44, blue: 0.62),
              Color(red: 0.12, green: 0.14, blue: 0.30))),
        (13, (Color(red: 0.42, green: 0.72, blue: 0.98),   // midday
              Color(red: 0.30, green: 0.52, blue: 0.82),
              Color(red: 0.10, green: 0.20, blue: 0.42))),
        (19, (Color(red: 0.86, green: 0.40, blue: 0.44),   // dusk
              Color(red: 0.44, green: 0.26, blue: 0.52),
              Color(red: 0.10, green: 0.10, blue: 0.24))),
        (23, (Color(red: 0.10, green: 0.10, blue: 0.22),   // night
              Color(red: 0.06, green: 0.06, blue: 0.14),
              Color(red: 0.03, green: 0.03, blue: 0.08)))
    ]

    /// The gradient anchors for a fractional hour-of-day (0..<24), interpolated between the
    /// two surrounding keyframes. Between the last (23:00) and first (06:00) keys the
    /// interpolation wraps across midnight, so the whole day is one continuous loop.
    private func gradientAnchors(atHour hour: Double) -> Triple {
        let keys = Self.keyframes
        // Find the segment [a, b] that `hour` falls in; else it's in the wrap segment.
        for i in 0..<(keys.count - 1) where hour >= keys[i].hour && hour < keys[i + 1].hour {
            let t = (hour - keys[i].hour) / (keys[i + 1].hour - keys[i].hour)
            return Self.lerp(keys[i].colors, keys[i + 1].colors, t)
        }
        // Wrap segment: from night (23:00) around to dawn (06:00) — span = 24 - 23 + 6 = 7h.
        let last = keys[keys.count - 1]
        let first = keys[0]
        let span = (24 - last.hour) + first.hour
        let elapsed = hour >= last.hour ? (hour - last.hour) : (hour + (24 - last.hour))
        return Self.lerp(last.colors, first.colors, elapsed / span)
    }

    private static func lerp(_ a: Triple, _ b: Triple, _ t: Double) -> Triple {
        let t = min(max(t, 0), 1)
        return (a.top.mixed(with: b.top, t),
                a.mid.mixed(with: b.mid, t),
                a.bottom.mixed(with: b.bottom, t))
    }

    public func tokens(for role: ScreenRole) -> ThemeTokens {
        // Time-independent fallback (previews/tests that don't inject an hour): use dawn.
        tokens(for: role, atHour: 6)
    }

    public func tokens(for role: ScreenRole, atHour hour: Double) -> ThemeTokens {
        let anchors = gradientAnchors(atHour: hour)
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
