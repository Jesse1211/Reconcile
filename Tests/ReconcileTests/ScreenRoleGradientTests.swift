import XCTest
import SwiftUI
@testable import Reconcile

/// ADR-037 gate: `screenRole` drives the Day Arc per-screen gradient; Ledger ignores it.
final class ScreenRoleGradientTests: XCTestCase {

    /// Resolve a SwiftUI `Color` to comparable RGBA components via UIKit.
    private func rgba(_ color: Color) -> [CGFloat] {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func gradientTriple(_ tokens: ThemeTokens) -> [[CGFloat]] {
        [rgba(tokens.colors.gradientTop),
         rgba(tokens.colors.gradientMid),
         rgba(tokens.colors.gradientBottom)]
    }

    /// Under Day Arc, different roles yield different gradient anchors (ADR-037).
    func testDayArcGradientVariesByScreenRole() {
        let today = gradientTriple(Theme.dayArc.tokens(for: .today))
        let summary = gradientTriple(Theme.dayArc.tokens(for: .summary))
        let timer = gradientTriple(Theme.dayArc.tokens(for: .timer))
        XCTAssertNotEqual(today, summary, "Today (dawn) vs Summary (dusk) must differ")
        XCTAssertNotEqual(today, timer, "Today (dawn) vs Timer (midday) must differ")
        XCTAssertNotEqual(timer, summary, "Timer (midday) vs Summary (dusk) must differ")
    }

    /// Under Ledger, changing the role leaves every token unchanged (ADR-037).
    func testLedgerIgnoresScreenRole() {
        let a = Theme.ledger.tokens(for: .today)
        let b = Theme.ledger.tokens(for: .summary)
        XCTAssertEqual(gradientTriple(a), gradientTriple(b))
        XCTAssertEqual(rgba(a.colors.background), rgba(b.colors.background))
        XCTAssertEqual(rgba(a.colors.accent), rgba(b.colors.accent))
        XCTAssertEqual(rgba(a.colors.accentCarried), rgba(b.colors.accentCarried))
    }
}
