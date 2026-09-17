import XCTest
@testable import Reconcile

/// T7 gate — the Today screen's theme-dressed copy (ADR-024/-033/-034).
///
/// The intention ritual is DRESSED per theme (ADR-024): Ledger reads as a paper ledger
/// ("Record entry"). (Day Arc, the second theme, has been removed — Ledger is the only
/// theme.) The `mine`-empty guidance is pinned by ADR-034. Pinning the copy as pure values
/// lets the gate assert intent without a UI harness while the SwiftUI view stays
/// theme-agnostic (ADR-036).
final class TodayCopyTests: XCTestCase {

    func testIntentionRitualCopyForLedger() {
        let ledger = IntentionRitualCopy.forTheme(.ledger)
        XCTAssertEqual(ledger.saveTitle, "Record entry", "Ledger dresses the save button (ADR-024)")
        XCTAssertEqual(ledger.eyebrow, "TODAY'S ENTRY", "Ledger dresses the guiding eyebrow (ADR-024)")
    }

    func testBothThemesSupplyEveryRitualField() {
        for theme in Theme.allCases {
            let c = IntentionRitualCopy.forTheme(theme)
            XCTAssertFalse(c.eyebrow.isEmpty)
            XCTAssertFalse(c.inputPrompt.isEmpty)
            XCTAssertFalse(c.reasonPrompt.isEmpty)
            XCTAssertFalse(c.saveTitle.isEmpty)
        }
    }

    func testPlaceholderRowTitleExistsForBothThemes() {
        for theme in Theme.allCases {
            XCTAssertFalse(IntentionRitualCopy.placeholderRowTitle(for: theme).isEmpty,
                           "dashed placeholder row has a prompt in both themes (ADR-024/-033)")
        }
    }

    func testMineEmptyGuidanceIsGuidingNotError() {
        // ADR-034: guiding empty state invites write-or-switch, never an error tone.
        let g = TodayCopy.mineEmptyGuidance
        XCTAssertTrue(g.lowercased().contains("empty"))
        XCTAssertTrue(g.lowercased().contains("online"), "invites switching to Online (ADR-034)")
    }

    func testSourceIndicatorPerScope() {
        XCTAssertNotEqual(TodayCopy.sourceIndicator(for: .mine),
                          TodayCopy.sourceIndicator(for: .online),
                          "source indicator distinguishes mine vs online (ADR-011/-040)")
    }

    func testOnlineErrorCopyPerCase() {
        // Each ZenQuotes failure has purposeful retry copy (ADR-013).
        XCTAssertFalse(TodayCopy.onlineError(.timeout).isEmpty)
        XCTAssertFalse(TodayCopy.onlineError(.offline).isEmpty)
        XCTAssertFalse(TodayCopy.onlineError(.badResponse).isEmpty)
    }
}
