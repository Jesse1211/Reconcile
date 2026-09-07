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

    /// Fresh install: scope defaults to online (ADR-034), theme defaults to ledger.
    func testDefaultsOnFreshInstall() {
        let settings = AppSettings(defaults: freshDefaults())
        XCTAssertEqual(settings.todayScope, .online)
        XCTAssertEqual(settings.theme, .ledger)
    }

    /// Scope selection persists across a simulated relaunch (ADR-040).
    func testTodayScopePersistsAcrossLaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.todayScope = .mine

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.todayScope, .mine)
    }

    /// Theme selection persists across a simulated relaunch (ADR-022/ADR-040).
    func testThemePersistsAcrossLaunch() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.theme = .dayArc

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.theme, .dayArc)
    }

    /// Both selections are owned by a SINGLE layer and independently persisted (ADR-040).
    func testBothSelectionsCoexist() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.theme = .dayArc
        first.todayScope = .mine

        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.theme, .dayArc)
        XCTAssertEqual(relaunched.todayScope, .mine)
    }
}
