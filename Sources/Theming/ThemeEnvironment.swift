import SwiftUI

/// The resolved token set for the active theme + current `screenRole`, read by screens.
///
/// Screens read `\.theme` (a `ThemeTokens`) and pull colors/fonts by role. Because
/// `ThemeTokens` is a concrete type with a fixed set of roles, reading a role that is
/// not in the ADR-036 contract does not compile — there is no silent fallback.
private struct ThemeTokensKey: EnvironmentKey {
    // Default is Ledger at the `.today` role so previews/tests always resolve.
    static let defaultValue: ThemeTokens = Theme.ledger.tokens(for: .today)
}

public extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }
}

/// Resolves `ThemeTokens` from the selected `Theme` and the view's `screenRole`, and
/// injects them into the environment. Apply this at each screen root (or the shell) so
/// the token set stays consistent with the declared role.
private struct ThemedModifier: ViewModifier {
    let theme: Theme
    /// The role is passed in explicitly (not read from the environment) so token
    /// resolution never depends on modifier ordering. A separate `.screenRole` read
    /// would resolve against the PARENT environment (the value this modifier's own
    /// `.screenRole(_:)` injects flows only to children), so every screen would get the
    /// default `.today` role and share one gradient — the ordering trap this avoids.
    let role: ScreenRole

    func body(content: Content) -> some View {
        content
            // Inject BOTH the resolved tokens for (theme, role) AND the role itself, so
            // any child that reads `\.screenRole` (or re-derives) sees the right role.
            .environment(\.theme, theme.tokens(for: role))
            .environment(\.screenRole, role)
    }
}

public extension View {
    /// Resolve and inject `ThemeTokens` for `theme` at the given screen `role` (ADR-037).
    /// The role is explicit so the result never depends on modifier order.
    func themed(_ theme: Theme, role: ScreenRole) -> some View {
        modifier(ThemedModifier(theme: theme, role: role))
    }
}

/// The theme-aware background for a screen: Day Arc paints its per-screen gradient
/// (from the resolved gradient-anchor tokens, ADR-037); Ledger paints its flat paper.
public struct ThemeBackground: View {
    @Environment(\.theme) private var tokens

    public init() {}

    public var body: some View {
        Group {
            switch tokens.theme {
            case .dayArc:
                LinearGradient(
                    colors: [
                        tokens.colors.gradientTop,
                        tokens.colors.gradientMid,
                        tokens.colors.gradientBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .ledger:
                tokens.colors.background
            }
        }
        .ignoresSafeArea()
    }
}
