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
            tab(role: .today, title: "Today", systemImage: "sun.max")
            tab(role: .timer, title: "Timer", systemImage: "timer")
            tab(role: .library, title: "Library", systemImage: "books.vertical")
            tab(role: .summary, title: "Summary", systemImage: "chart.bar")
        }
    }

    @ViewBuilder
    private func tab(role: ScreenRole, title: String, systemImage: String) -> some View {
        PlaceholderScreen(title: title)
            // Order matters: declare the role first, then resolve tokens for it.
            .screenRole(role)
            .themed(settings.theme)
            .tabItem {
                Label(title, systemImage: systemImage)
            }
    }
}
