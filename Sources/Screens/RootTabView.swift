import SwiftUI
import SwiftData

/// The bottom-tab shell: Today / Timer / Library / Summary / Settings (T1).
///
/// Each screen resolves theme tokens via `.themed(_:role:)`, so Day Arc paints the correct
/// per-screen gradient while the screens stay theme-agnostic. The active `Theme` comes from
/// `AppSettings` (ADR-040), so switching theme re-styles the shell live without a restart.
///
/// **Nav bar (ADR-037b, owner decision):** a FIXED light-grey capsule with dark icons and a
/// darker "pill" behind the selected item — the SAME in every background, theme, and system
/// light/dark mode. The system `TabView` bar on iOS 26 is a floating glass capsule that
/// ignores `UITabBarAppearance`, so we hide it and draw our own fixed capsule instead.
public struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.clock) private var clock

    /// The bottom tabs, in order.
    private enum Tab: CaseIterable {
        case today, timer, library, summary, settings
        var title: String {
            switch self {
            case .today: return "Today"
            case .timer: return "Timer"
            case .library: return "Library"
            case .summary: return "Summary"
            case .settings: return "Settings"
            }
        }
        var systemImage: String {
            switch self {
            case .today: return "sun.max"
            case .timer: return "timer"
            case .library: return "books.vertical"
            case .summary: return "chart.bar"
            case .settings: return "gearshape"
            }
        }
        var screenRole: ScreenRole {
            switch self {
            case .today: return .today
            case .timer: return .timer
            case .library: return .library
            case .summary: return .summary
            case .settings: return .settings
            }
        }
    }

    /// Vertical room the overlaid nav capsule occupies above the bottom safe area — the
    /// amount scrollable content must reserve so it can scroll above the bar (ADR-037b).
    private static let navBarReservedHeight: CGFloat = 76

    @State private var selection: Tab = .today
    /// Namespace for the selected-tab pill so it SLIDES between tabs (matchedGeometry).
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        // A once-a-minute timeline re-renders the shell so the Day Arc background, nav-bar
        // tint, and adaptive text keep pace with the REAL time of day (ADR-037c/d) even while
        // a screen sits idle — not only when some other change forces a re-render.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            ZStack(alignment: .bottom) {
                // A real TabView keeps EVERY tab's view (and @StateObject/@State) alive across
                // switches — no teardown, no re-running .task, no repeat network fetch. The
                // system bar is hidden; our own capsule is overlaid instead.
                TabView(selection: $selection) {
                    tabScreen(.today) {
                        TodayScreen(context: modelContext, clock: clock,
                                    settings: settings, client: LiveZenQuotesClient())
                    }
                    tabScreen(.timer) { TimerScreen() }
                    tabScreen(.library) { LibraryScreen(model: makeLibraryModel()) }
                    tabScreen(.summary) { SummaryScreen() }
                    tabScreen(.settings) { SettingsScreen() }
                }
                .toolbar(.hidden, for: .tabBar)

                // Our own fixed nav bar, overlaid at the bottom.
                navBar
            }
        }
    }

    /// One tab: theme it for its role, reserve room for the overlaid capsule, and tag it
    /// with its `Tab` for the `TabView` selection binding.
    @ViewBuilder
    private func tabScreen<Content: View>(_ tab: Tab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .themed(settings.theme, role: tab.screenRole)
            // Reserve room for the overlaid nav capsule so scrollable content scrolls ABOVE
            // it rather than behind it (a real TabView would reserve this for its own bar).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: Self.navBarReservedHeight)
            }
            .tag(tab)
    }

    // MARK: Capsule nav bar (ADR-037b/-037d)

    /// The nav capsule tracks the current time-of-day gradient like the rest of Day Arc
    /// (ADR-037d): its ground is the current gradient mid tone as a translucent glass, and
    /// its icon colors ADAPT to that tone's brightness (dark icons over a light bar, light
    /// icons over a dark bar) so it stays legible from midday to midnight. Ledger resolves to
    /// its fixed paper tones. Colors come from the active theme's tokens at the current hour.
    private var navTokens: ThemeTokens {
        settings.theme.palette.tokens(for: .today, atHour: currentHour)
    }
    private var currentHour: Double {
        let c = clock.calendar.dateComponents([.hour, .minute], from: clock.now())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    private var navBar: some View {
        let t = navTokens
        // Glass capsule tinted by the current sky; icons adapt to its brightness.
        let capsule = t.colors.gradientMid.opacity(0.72)
        let onDark = !t.isLightBackground
        let icon = (onDark ? Color.white : Color.black).opacity(0.55)
        let iconSelected = (onDark ? Color.white : Color.black).opacity(0.95)
        let selectedPill = (onDark ? Color.white : Color.black).opacity(0.16)

        return HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    // Slide the selected pill (matchedGeometry) unless Reduce Motion is on.
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            selection = tab
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? iconSelected : icon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            // The SAME pill view moves between tabs via matchedGeometry,
                            // so it slides rather than popping in/out.
                            Capsule(style: .continuous)
                                .fill(selectedPill)
                                .matchedGeometryEffect(id: "selectedPill", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(capsule)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @MainActor
    private func makeLibraryModel() -> LibraryViewModel {
        let settings = self.settings
        let service = QuoteService(
            context: modelContext,
            clock: clock,
            client: LiveZenQuotesClient(),
            scope: { settings.todayScope },
            category: { settings.quoteCategory }   // ADR-047
        )
        return LibraryViewModel(
            service: service,
            scope: { settings.todayScope },
            setScope: { settings.todayScope = $0 }   // ADR-040: the Library is the scope writer
        )
    }
}
