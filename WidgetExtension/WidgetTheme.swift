import SwiftUI

/// A small, self-contained color treatment for the WidgetKit surface (ADR-044).
///
/// The full app theming layer (the token environment, ADR-036) is NOT dragged into the
/// extension — a widget is a constrained surface and ADR-044 only asks the Home widget to
/// FOLLOW the persisted `Theme` "within the widget's constrained surface", respecting the
/// token vocabulary spirit. So this maps the `Theme` to just the handful of roles a widget
/// renders: a background, primary and secondary text, and a divider. Ledger is the only
/// theme (Day Arc removed, ADR-022).
///
/// The Lock widget does NOT use this (ADR-044): under the OS tint/monochrome
/// rendering mode it is theme-neutral and legible, so it renders with the system
/// tint and no explicit colors.
struct WidgetTheme {
    let background: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color

    /// The Home-widget palette for a persisted `Theme` (ADR-044). Ledger is the only
    /// theme, so this always resolves to the paper/ink treatment.
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
        }
    }
}
