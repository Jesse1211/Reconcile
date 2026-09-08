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
        ZStack(alignment: .bottom) {
            // Active screen fills the whole shell (its ThemeBackground ignores safe area).
            // A per-selection id + opacity transition gives a gentle cross-fade on switch.
            activeScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Reserve room for the overlaid nav capsule so scrollable content can scroll
                // ABOVE it instead of being hidden behind it (the system TabView reserved
                // this automatically; our custom overlay must do it explicitly).
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: Self.navBarReservedHeight)
                }
                .id(selection)
                .transition(.opacity)

            // Our own fixed nav bar, overlaid at the bottom — same look in every background.
            navBar
        }
        // Animate both the screen cross-fade and the pill slide on selection change
        // (respecting Reduce Motion).
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86),
                   value: selection)
    }

    @ViewBuilder
    private var activeScreen: some View {
        switch selection {
        case .today:
            TodayScreen(
                context: modelContext,
                clock: clock,
                settings: settings,
                client: LiveZenQuotesClient()
            )
            .themed(settings.theme, role: .today)
        case .timer:
            TimerScreen()
                .themed(settings.theme, role: .timer)
        case .library:
            LibraryScreen(model: makeLibraryModel())
                .themed(settings.theme, role: .library)
        case .summary:
            SummaryScreen()
                .themed(settings.theme, role: .summary)
        case .settings:
            SettingsScreen()
                .themed(settings.theme, role: .settings)
        }
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
                    selection = tab   // animated by the body-level .animation(value: selection)
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
            scope: { settings.todayScope }
        )
        return LibraryViewModel(
            service: service,
            scope: { settings.todayScope },
            setScope: { settings.todayScope = $0 }   // ADR-040: the Library is the scope writer
        )
    }
}
