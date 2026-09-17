import XCTest
@testable import Reconcile

/// ADR-040 gate: T1's settings layer persists BOTH `Theme` and `TodayScope` across
/// launch; scope defaults to `online` on first run (ADR-034).
@MainActor
final class AppSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "AppSettingsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    /// Fresh install: scope defaults to online (ADR-034), theme defaults to ledger,
    /// category defaults to any (ADR-047).
    func testDefaultsOnFreshInstall() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.todayScope, .online)
        XCTAssertEqual(settings.theme, .ledger)
        XCTAssertEqual(settings.quoteCategory, .any)
    }

    /// Category selection persists across a simulated relaunch (ADR-047).
    func testQuoteCategoryPersistsAcrossLaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.quoteCategory = .wisdom

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.quoteCategory, .wisdom)
    }

    /// Scope selection persists across a simulated relaunch (ADR-040).
    func testTodayScopePersistsAcrossLaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.todayScope = .mine

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.todayScope, .mine)
    }

    /// Theme selection persists across a simulated relaunch (ADR-022/ADR-040). Ledger is
    /// the only theme now (Day Arc removed), so the persisted value round-trips as Ledger.
    func testThemePersistsAcrossLaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.theme = .ledger

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.theme, .ledger)
    }

    /// A theme raw value persisted by an OLDER build (the removed "dayArc") no longer
    /// decodes; the settings layer must fall back to `.ledger` rather than crash (ADR-022).
    func testRemovedThemeRawValueFallsBackToLedger() {
        let defaults = freshDefaults()
        defaults.set("dayArc", forKey: "settings.theme")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .ledger)
    }

    /// Both selections are owned by a SINGLE layer and independently persisted (ADR-040).
    func testBothSelectionsCoexist() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.theme = .ledger
        first.todayScope = .mine

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.theme, .ledger)
        XCTAssertEqual(relaunched.todayScope, .mine)
    }
}
