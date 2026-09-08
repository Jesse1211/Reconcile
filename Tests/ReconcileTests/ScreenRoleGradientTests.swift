import XCTest
import SwiftUI
@testable import Reconcile

/// ADR-037 (revised): under Day Arc the gradient is driven by the REAL time of day and is
/// the SAME on every screen (it no longer varies by `screenRole`). Ledger ignores both.
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

    private let dayArc = DayArcPalette()

    /// At a FIXED hour, the Day Arc gradient is identical across every screen role — the
    /// background is "the colour of the sky right now", not a per-page colour (ADR-037 rev.).
    func testDayArcGradientIsSameAcrossRolesAtSameHour() {
        let hour = 13.0 // midday
        let today = gradientTriple(dayArc.tokens(for: .today, atHour: hour))
        let timer = gradientTriple(dayArc.tokens(for: .timer, atHour: hour))
        let summary = gradientTriple(dayArc.tokens(for: .summary, atHour: hour))
        let settings = gradientTriple(dayArc.tokens(for: .settings, atHour: hour))
        XCTAssertEqual(today, timer, "same hour → same gradient regardless of role")
        XCTAssertEqual(today, summary, "same hour → same gradient regardless of role")
        XCTAssertEqual(today, settings, "same hour → same gradient regardless of role")
    }

    /// The Day Arc gradient CHANGES with the time of day (dawn ≠ midday ≠ dusk ≠ night).
    func testDayArcGradientVariesByTimeOfDay() {
        let dawn = gradientTriple(dayArc.tokens(for: .today, atHour: 6))
        let midday = gradientTriple(dayArc.tokens(for: .today, atHour: 13))
        let dusk = gradientTriple(dayArc.tokens(for: .today, atHour: 19))
        let night = gradientTriple(dayArc.tokens(for: .today, atHour: 23))
        XCTAssertNotEqual(dawn, midday, "dawn vs midday must differ")
        XCTAssertNotEqual(midday, dusk, "midday vs dusk must differ")
        XCTAssertNotEqual(dusk, night, "dusk vs night must differ")
    }

    /// Between two keyframes the gradient interpolates — a mid-morning hour is neither the
    /// pure dawn nor the pure midday triple.
    func testDayArcGradientInterpolatesBetweenKeyframes() {
        let dawn = gradientTriple(dayArc.tokens(for: .today, atHour: 6))
        let midday = gradientTriple(dayArc.tokens(for: .today, atHour: 13))
        let midMorning = gradientTriple(dayArc.tokens(for: .today, atHour: 9.5))
        XCTAssertNotEqual(midMorning, dawn)
        XCTAssertNotEqual(midMorning, midday)
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
