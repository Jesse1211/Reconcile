import XCTest
import SwiftUI
import SwiftData
@testable import Reconcile

/// T10 render gate: the Summary screen renders all five blocks under BOTH themes, in
/// both the populated and the empty (brand-new user) state, without crashing (ADR-022/
/// -033). Swift Charts rendering is exercised by hosting the view and forcing a layout
/// pass; the numeric correctness of each block lives in `SummaryServiceTests`.
@MainActor
final class SummaryScreenRenderTests: XCTestCase {

    private func pinnedClock() -> TestClock {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_700_010_000), calendar: cal)
        clock.setNow(clock.today())
        return clock
    }

    /// Host the Summary screen with a given theme + container and force a layout pass.
    private func render(theme: Theme, clock: Clock, container: ModelContainer) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        settings.theme = theme
        let view = SummaryScreen()
            .screenRole(.summary)
            .themed(theme)
            .environment(\.clock, clock)
            .environmentObject(settings)
            .modelContainer(container)

        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Reaching here without a trap means the whole view tree (charts + timeline +
        // KPI cards) resolved every theme token and rendered.
        XCTAssertNotNil(host.view)
    }

    private func populatedContainer(_ clock: TestClock) throws -> ModelContainer {
        let container = PersistenceController.makeInMemoryContainer()
        let ctx = ModelContext(container)
        let mit = MITService(clock: clock)
        let a = mit.create(text: "Ship Summary", in: ctx); try mit.complete(a)
        _ = mit.create(text: "Open one", in: ctx)
        let session = FocusSession(
            startedAt: clock.today().addingTimeInterval(-1800),
            endedAt: clock.today().addingTimeInterval(1800)
        )
        session.accumulatedSeconds = 3600
        ctx.insert(session)
        _ = try DailyFeeling.upsert(day: clock.today(), mood: 4, stress: 2, whyText: nil, in: ctx)
        try ctx.save()
        return container
    }

    func testRendersPopulatedUnderBothThemes() throws {
        let clock = pinnedClock()
        let container = try populatedContainer(clock)
        render(theme: .ledger, clock: clock, container: container)
        render(theme: .dayArc, clock: clock, container: container)
    }

    func testRendersEmptyStateUnderBothThemes() throws {
        let clock = pinnedClock()
        let container = PersistenceController.makeInMemoryContainer()
        render(theme: .ledger, clock: clock, container: container)
        render(theme: .dayArc, clock: clock, container: container)
    }
}
