import SwiftUI

/// The bottom-tab shell: Today / Timer / Library / Summary (T1).
///
/// Each tab declares its `screenRole` (ADR-037) and THEN resolves theme tokens via
/// `.themed(_:)`, so Day Arc paints the correct per-screen gradient while the screens
/// themselves stay theme-agnostic. The active `Theme` comes from `AppSettings`
/// (ADR-040), so switching theme re-styles the shell live without a restart.
public struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings

    public init() {}

    public var body: some View {
        TabView {
            tab(role: .today, title: "Today", systemImage: "sun.max") {
                PlaceholderScreen(title: "Today")
            }
            tab(role: .timer, title: "Timer", systemImage: "timer") {
                TimerScreen()
            }
            tab(role: .library, title: "Library", systemImage: "books.vertical") {
                PlaceholderScreen(title: "Library")
            }
            tab(role: .summary, title: "Summary", systemImage: "chart.bar") {
                PlaceholderScreen(title: "Summary")
            }
        }
    }

    @ViewBuilder
    private func tab<Content: View>(
        role: ScreenRole,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            // Order matters: declare the role first, then resolve tokens for it.
            .screenRole(role)
            .themed(settings.theme)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
    }
}
