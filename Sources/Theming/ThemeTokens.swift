import SwiftUI

/// The FROZEN theme token contract (ADR-036).
///
/// Both themes (Ledger, Day Arc) MUST supply EVERY named token. Screens read tokens
/// **by role** and NEVER hard-code a color or font. A screen that reads a role not in
/// this contract is a build/compile error (the property simply does not exist), not a
/// silent fallback — the type system is the enforcement.
///
/// This is a concrete `struct`, not a protocol with defaults, precisely so that a
/// theme cannot silently omit a token: every stored property must be initialised.

/// The named color roles (ADR-036).
public struct ThemeColors: Sendable {
    // Core surfaces & text.
    public let background: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textMuted: Color
    public let accent: Color
    /// The ledger-red / rolled-over "carried" color (ADR-036).
    public let accentCarried: Color
    /// Fill color for solid buttons & selected chips (ADR-037e). On Day Arc this is a
    /// near-white; the label on top MUST stay `background` (dark) so it never vanishes.
    public let accentFill: Color
    /// Adaptive accent for glyphs/charts painted on the sky (ADR-037e): dark on a light
    /// background, light on a dark one — reuses `isLightBackground`. Never flat white
    /// (which disappears on a bright daytime sky).
    public let accentOnBackground: Color
    /// The "liked / favorited" hue — kept a saturated color so the state reads at a glance
    /// (ADR-037e); does NOT go white/adaptive.
    public let likedAccent: Color
    public let divider: Color

    // Day-Arc gradient-anchor set (ADR-036/037). The Day Arc theme selects these per
    // `screenRole`; the Ledger theme supplies flat/neutral values so the set is total.
    public let gradientTop: Color
    public let gradientMid: Color
    public let gradientBottom: Color

    public init(
        background: Color,
        surface: Color,
        surfaceRaised: Color,
        textPrimary: Color,
        textSecondary: Color,
        textMuted: Color,
        accent: Color,
        accentCarried: Color,
        accentFill: Color,
        accentOnBackground: Color,
        likedAccent: Color,
        divider: Color,
        gradientTop: Color,
        gradientMid: Color,
        gradientBottom: Color
    ) {
        self.background = background
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.accent = accent
        self.accentCarried = accentCarried
        self.accentFill = accentFill
        self.accentOnBackground = accentOnBackground
        self.likedAccent = likedAccent
        self.divider = divider
        self.gradientTop = gradientTop
        self.gradientMid = gradientMid
        self.gradientBottom = gradientBottom
    }
}

/// The named type roles (ADR-036).
public struct ThemeTypography: Sendable {
    public let display: Font
    public let title: Font
    public let body: Font
    public let mono: Font
    public let eyebrow: Font

    public init(
        display: Font,
        title: Font,
        body: Font,
        mono: Font,
        eyebrow: Font
    ) {
        self.display = display
        self.title = title
        self.body = body
        self.mono = mono
        self.eyebrow = eyebrow
    }
}

/// The resolved token set for the active theme, for the current `screenRole`.
///
/// A theme produces this via `ThemePalette.tokens(for:)`. Screens read it from the
/// `\.theme` environment value.
public struct ThemeTokens: Sendable {
    public let theme: Theme
    public let screenRole: ScreenRole
    public let colors: ThemeColors
    public let typography: ThemeTypography
    /// Whether the current background is LIGHT (high luminance). Fonts and the nav bar read
    /// this to pick dark-on-light vs light-on-dark treatment as the Day Arc background drifts
    /// from bright midday to deep night (ADR-037d). Ledger sets it from its fixed paper.
    public let isLightBackground: Bool

    public init(
        theme: Theme,
        screenRole: ScreenRole,
        colors: ThemeColors,
        typography: ThemeTypography,
        isLightBackground: Bool
    ) {
        self.theme = theme
        self.screenRole = screenRole
        self.colors = colors
        self.typography = typography
        self.isLightBackground = isLightBackground
    }
}
