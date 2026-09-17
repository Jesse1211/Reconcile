import XCTest
import SwiftUI
@testable import Reconcile

/// ADR-037 (revised): the time-of-day gradient belonged to the Day Arc theme, which has
/// been REMOVED (ADR-022). Ledger — the only remaining theme — ignores both the screen
/// role and the hour, resolving the same flat paper tokens everywhere. The former Day Arc
/// gradient assertions are gone with the theme.
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

    /// Under Ledger, changing the role OR the hour leaves every token unchanged.
    func testLedgerIgnoresRoleAndTime() {
        let ledger = LedgerPalette()
        let a = ledger.tokens(for: .today, atHour: 6)
        let b = ledger.tokens(for: .summary, atHour: 23)
        XCTAssertEqual(gradientTriple(a), gradientTriple(b))
        XCTAssertEqual(rgba(a.colors.background), rgba(b.colors.background))
        XCTAssertEqual(rgba(a.colors.accent), rgba(b.colors.accent))
        XCTAssertEqual(rgba(a.colors.accentCarried), rgba(b.colors.accentCarried))
    }
}
