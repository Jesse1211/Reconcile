import XCTest
@testable import Reconcile

final class ClockTests: XCTestCase {
    /// A test can pin "today" (ADR-038 gate: Clock is injectable).
    func testTestClockPinsNow() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(now: fixed)
        XCTAssertEqual(clock.now(), fixed)
        clock.advance(by: 60)
        XCTAssertEqual(clock.now(), fixed.addingTimeInterval(60))
    }

    /// `today()` / `startOfDay` returns a LOCAL startOfDay with no time-of-day leak (ADR-038).
    func testTodayIsLocalStartOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        // An arbitrary mid-afternoon instant.
        let afternoon = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(now: afternoon, calendar: cal)

        let today = clock.today()
        let comps = cal.dateComponents([.hour, .minute, .second], from: today)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
        XCTAssertEqual(today, cal.startOfDay(for: afternoon))
    }

    /// Two instants on the same local day collapse to the same canonical key (ADR-038).
    func testSameDayCollapsesToSameKey() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_700_000_000), calendar: cal)
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        let laterSameDay = morning.addingTimeInterval(3 * 3600)
        XCTAssertEqual(clock.startOfDay(for: morning), clock.startOfDay(for: laterSameDay))
    }
}
