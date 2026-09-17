import SwiftUI

/// A shared screen frame: a PINNED title header at the very top (never scrolls away),
/// with the screen's own (scrolling) content below it. Every top-level tab screen uses
/// this so the page title stays fixed while content scrolls — the same treatment across
/// Today / Library / Summary / Settings.
///
/// The bottom nav bar shows icons only (no labels, ADR-037b as revised); the page title
/// here is what names the screen. Theme-agnostic: reads the title font/color by role from
/// the `\.theme` tokens (ADR-036).
///
/// - `title`: the large page title (e.g. "Today", "Quotes", "Summary", "Settings").
/// - `trailing`: an optional control pinned on the header's trailing edge (e.g. the
///   Library "+" add button). Defaults to nothing.
/// - `content`: the screen body below the header. It owns its own scrolling.
struct ScreenScaffold<Trailing: View, Content: View>: View {
    @Environment(\.theme) private var tokens

    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                // PINNED header — stays at the top while the content below scrolls.
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(tokens.typography.display)
                        .foregroundStyle(tokens.colors.textPrimary)
                    Spacer()
                    trailing()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                content()
            }
        }
    }
}
