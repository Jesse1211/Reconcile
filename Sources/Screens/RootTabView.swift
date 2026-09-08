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

    @State private var selection: Tab = .today

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Active screen fills the whole shell (its ThemeBackground ignores safe area).
            activeScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Our own fixed nav bar, overlaid at the bottom — same look in every background.
            navBar
        }
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

    // MARK: Fixed capsule nav bar (ADR-037b)

    /// A light-grey capsule with dark icons; the selected item sits on a darker pill. These
    /// colors are FIXED constants (not theme/dark-mode driven) so the bar reads identically
    /// on every screen's background.
    private var navBar: some View {
        let capsule = Color(white: 0.93)            // light-grey capsule ground
        let icon = Color(white: 0.45)               // unselected dark grey
        let iconSelected = Color(white: 0.10)       // selected near-black
        let selectedPill = Color(white: 0.82)       // darker pill behind the selected item

        return HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
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
                            Capsule(style: .continuous)
                                .fill(selectedPill)
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
