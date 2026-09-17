import XCTest
import SwiftUI
@testable import Reconcile

/// ADR-037 (revised): the time-of-day gradient and per-screen gradient anchors belonged to
/// the Day Arc theme, which has been REMOVED (ADR-022) along with the `atHour:` resolution
/// path. Ledger — the only remaining theme — ignores the screen role, resolving the same
/// flat paper tokens everywhere. The former Day Arc gradient assertions are gone with the
/// theme; this pins that role no longer varies any token.
final class ScreenRoleGradientTests: XCTestCase {

    /// Resolve a SwiftUI `Color` to comparable RGBA components via UIKit.
    private func rgba(_ color: Color) -> [CGFloat] {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    /// Under Ledger, changing the role leaves every token unchanged.
    func testLedgerIgnoresRole() {
        let ledger = LedgerPalette()
        let a = ledger.tokens(for: .today)
        let b = ledger.tokens(for: .summary)
        XCTAssertEqual(rgba(a.colors.background), rgba(b.colors.background))
        XCTAssertEqual(rgba(a.colors.surface), rgba(b.colors.surface))
        XCTAssertEqual(rgba(a.colors.accent), rgba(b.colors.accent))
        XCTAssertEqual(rgba(a.colors.accentCarried), rgba(b.colors.accentCarried))
    }
}
