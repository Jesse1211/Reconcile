import SwiftUI

/// A small, self-contained color treatment for the WidgetKit surface (ADR-044).
///
/// The full app theming layer (Day-Arc gradients, token environment, ADR-036) is
/// NOT dragged into the extension — a widget is a constrained surface and ADR-044
/// only asks the Home widget to FOLLOW the persisted `Theme` "within the widget's
/// constrained surface", respecting the token vocabulary spirit. So this maps each
/// `Theme` to just the handful of roles a widget renders: a background, primary and
/// secondary text, and a divider.
///
/// The Lock widget does NOT use this (ADR-044): under the OS tint/monochrome
/// rendering mode it is theme-neutral and legible, so it renders with the system
/// tint and no explicit colors.
struct WidgetTheme {
    let background: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color

    /// The Home-widget palette for a persisted `Theme` (ADR-044).
    static func home(for theme: Theme) -> WidgetTheme {
        switch theme {
        case .ledger:
            // Paper/ink neutrals with a ledger-red-adjacent muted divider (ADR-022).
            return WidgetTheme(
                background: Color(red: 0.98, green: 0.97, blue: 0.94),
                textPrimary: Color(red: 0.12, green: 0.11, blue: 0.10),
                textSecondary: Color(red: 0.38, green: 0.36, blue: 0.33),
                divider: Color(red: 0.80, green: 0.42, blue: 0.38)
            )
        case .dayArc:
            // A single legible day-arc-adjacent ground (no full gradient on-widget,
            // ADR-044 keeps the widget surface constrained).
            return WidgetTheme(
                background: Color(red: 0.10, green: 0.13, blue: 0.22),
                textPrimary: Color(red: 0.96, green: 0.97, blue: 1.0),
                textSecondary: Color(red: 0.72, green: 0.78, blue: 0.90),
                divider: Color(red: 0.45, green: 0.55, blue: 0.78)
            )
        }
    }
}
