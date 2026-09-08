import SwiftUI
import SwiftData

/// The bottom-tab shell: Today / Timer / Library / Summary (T1).
///
/// Each tab declares its `screenRole` (ADR-037) and THEN resolves theme tokens via
/// `.themed(_:)`, so Day Arc paints the correct per-screen gradient while the screens
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
            // Order matters: declare the role first, then resolve tokens for it.
            .screenRole(.today)
            .themed(settings.theme)
            .tabItem { Label("Today", systemImage: "sun.max") }

            timerTab
            libraryTab
            summaryTab
            settingsTab
        }
    }

    /// The Settings tab: the single place to change the visual theme (ADR-022) and the
    /// today's-quote source (`TodayScope`, ADR-040). Both write straight to `AppSettings`.
    @ViewBuilder
    private var settingsTab: some View {
        SettingsScreen()
            // Order matters: declare the role first, then resolve tokens for it (ADR-037).
            .screenRole(.settings)
            .themed(settings.theme)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
    }

    /// The Timer tab (T9): the real stopwatch screen with today's saved sessions.
    @ViewBuilder
    private var timerTab: some View {
        TimerScreen()
            // Order matters: declare the role first, then resolve tokens for it (ADR-037).
            .screenRole(.timer)
            .themed(settings.theme)
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
            .screenRole(.library)
            .themed(settings.theme)
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
            // Order matters: declare the role first, then resolve tokens for it (ADR-037).
            .screenRole(.summary)
            .themed(settings.theme)
            .tabItem {
                Label("Summary", systemImage: "chart.bar")
            }
    }
}
