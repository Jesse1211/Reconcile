import SwiftUI
import SwiftData

/// The bottom-tab shell: Today / Timer / Library / Summary (T1).
///
/// Each tab declares its `screenRole` (ADR-037) and THEN resolves theme tokens via
/// `.themed(_:role:)`, so Day Arc paints the correct per-screen gradient while the screens
/// themselves stay theme-agnostic. The active `Theme` comes from `AppSettings`
/// (ADR-040), so switching theme re-styles the shell live without a restart.
///
/// The Today tab (T7), Timer tab (T9), Library tab (T8), and Summary tab (T10) are all
/// wired to their real screens.
public struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.clock) private var clock

    public init() {}

    public var body: some View {
        TabView {
            // Today (T7) — the real screen.
            TodayScreen(
                context: modelContext,
                clock: clock,
                settings: settings,
                client: LiveZenQuotesClient()
            )
            // Resolve tokens for this screen's role (ADR-037) — role is explicit so it
            // never depends on modifier order.
            .themed(settings.theme, role: .today)
            .tabItem { Label("Today", systemImage: "sun.max") }

            timerTab
            libraryTab
            summaryTab
            settingsTab
        }
        // Tint the tab bar's SELECTED item with the active theme's accent (ADR-022) so it
        // reads as part of the theme instead of the system default blue. Resolved at the
        // shell level from the persisted Theme; the per-screen role doesn't matter for the
        // accent, so `.today` is a fine anchor.
        .tint(settings.theme.tokens(for: .today).colors.accent)
    }

    /// The Settings tab: the single place to change the visual theme (ADR-022) and the
    /// today's-quote source (`TodayScope`, ADR-040). Both write straight to `AppSettings`.
    @ViewBuilder
    private var settingsTab: some View {
        SettingsScreen()
            .themed(settings.theme, role: .settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
    }

    /// The Timer tab (T9): the real stopwatch screen with today's saved sessions.
    @ViewBuilder
    private var timerTab: some View {
        TimerScreen()
            .themed(settings.theme, role: .timer)
            .tabItem {
                Label("Timer", systemImage: "timer")
            }
    }

    /// The Library tab (T8): builds the T5 quote service from the live model context and
    /// the production ZenQuotes client, wires the scope reader/writer to T1's settings
    /// layer (ADR-040 — the Library WRITES the persisted scope), and shows ``LibraryScreen``.
    @ViewBuilder
    private var libraryTab: some View {
        LibraryScreen(model: makeLibraryModel())
            .themed(settings.theme, role: .library)
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
    }

    @MainActor
    private func makeLibraryModel() -> LibraryViewModel {
        let settings = self.settings
        let service = QuoteService(
            context: modelContext,
            clock: clock,
            client: LiveZenQuotesClient(),
            scope: { settings.todayScope }
        )
        return LibraryViewModel(
            service: service,
            scope: { settings.todayScope },
            setScope: { settings.todayScope = $0 }   // ADR-040: the Library is the scope writer
        )
    }

    /// The Summary tab (T10): the first real analytics screen — charts, mood, timeline,
    /// and KPIs rendered from the read-model.
    @ViewBuilder
    private var summaryTab: some View {
        SummaryScreen()
            .themed(settings.theme, role: .summary)
            .tabItem {
                Label("Summary", systemImage: "chart.bar")
            }
    }
}
