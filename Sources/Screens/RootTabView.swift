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

    public init() {
        // The nav (tab) bar is FIXED: always a white background with dark icons, and the
        // selected item highlighted in near-black. It does NOT follow the app theme or the
        // system light/dark mode — this keeps it stable while the per-screen Day Arc
        // gradients change behind it (owner decision).
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white

        let selected = UIColor(white: 0.10, alpha: 1.0)      // near-black for the chosen tab
        let normal = UIColor(white: 0.45, alpha: 1.0)        // dark grey for the rest
        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
        }

        let bar = UITabBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        // Ignore system Dark Mode so the bar stays white in both.
        bar.overrideUserInterfaceStyle = .light
    }

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
        // The tab bar's fixed white/dark appearance is configured once in `init()` via
        // UITabBarAppearance — it deliberately does NOT follow the theme accent.
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
