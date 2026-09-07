import SwiftUI

/// A theme-agnostic placeholder screen for the T1 shell.
///
/// It reads all styling by role from the `\.theme` token set (ADR-036) — no hard-coded
/// color or font. The screen's `screenRole` (ADR-037) and theme resolution are applied
/// by the shell (`RootTabView`) in the correct order so Day Arc can pick its per-screen
/// gradient. NO feature logic — later tasks (T7/T8/T9/T10) replace these bodies.
struct PlaceholderScreen: View {
    let title: String

    @Environment(\.theme) private var tokens

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 12) {
                Text(title.uppercased())
                    .font(tokens.typography.eyebrow)
                    .foregroundStyle(tokens.colors.textMuted)
                Text(title)
                    .font(tokens.typography.display)
                    .foregroundStyle(tokens.colors.textPrimary)
                Text("Coming soon")
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
            }
            .padding()
        }
    }
}
