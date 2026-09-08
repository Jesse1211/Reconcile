import SwiftUI
import Combine

/// The persisted settings layer (ADR-040): the SINGLE source of truth for BOTH the
/// selected `Theme` (ADR-022) AND the current `TodayScope` (ADR-040/ADR-034).
///
/// Both selections persist across launch (UserDefaults-backed). The scope defaults to
/// `online` on first run (ADR-034). Later tasks: T5 READS `todayScope`; T8 WRITES it;
/// the settings UI writes `theme`. No other component persists these.
@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let theme = "settings.theme"
        static let todayScope = "settings.todayScope"
        static let quoteCategory = "settings.quoteCategory"
    }

    private let defaults: UserDefaults
    /// The app-side widget snapshot writer (T12/ADR-042 (c) / ADR-044), invoked on
    /// theme change so the Home widget can render in the selected theme. Optional and
    /// defaulting to `nil` so existing callers/tests are unaffected (additive). T12
    /// OWNS the writer; this flow only INVOKES it at the theme transition.
    private let widgetWriter: WidgetSnapshotWriter?

    /// The selected visual theme (ADR-022). Persisted across launch.
    @Published public var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            // T12/ADR-044: mirror the persisted theme into the widget snapshot so the
            // Home widget follows it. Only fires on an actual change.
            if theme != oldValue { widgetWriter?.themeChanged(theme) }
        }
    }

    /// The current quote scope (ADR-040). Persisted; defaults to `online` (ADR-034).
    @Published public var todayScope: TodayScope {
        didSet { defaults.set(todayScope.rawValue, forKey: Keys.todayScope) }
    }

    /// The current online quote CATEGORY (ADR-047). Persisted; defaults to `.any`.
    /// Affects the `online` source ONLY — T5 reads it like scope; the Settings screen
    /// writes it.
    @Published public var quoteCategory: QuoteCategory {
        didSet { defaults.set(quoteCategory.rawValue, forKey: Keys.quoteCategory) }
    }

    public init(defaults: UserDefaults = .standard, widgetWriter: WidgetSnapshotWriter? = nil) {
        self.defaults = defaults
        self.widgetWriter = widgetWriter

        // Theme default: Ledger on first run.
        if let raw = defaults.string(forKey: Keys.theme), let stored = Theme(rawValue: raw) {
            self.theme = stored
        } else {
            self.theme = .ledger
        }

        // Scope default: online on first run (ADR-034).
        if let raw = defaults.string(forKey: Keys.todayScope), let stored = TodayScope(rawValue: raw) {
            self.todayScope = stored
        } else {
            self.todayScope = .online
        }

        // Category default: Any on first run (ADR-047).
        if let raw = defaults.string(forKey: Keys.quoteCategory), let stored = QuoteCategory(rawValue: raw) {
            self.quoteCategory = stored
        } else {
            self.quoteCategory = .any
        }
    }
}
