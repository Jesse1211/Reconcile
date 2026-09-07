import XCTest
import SwiftUI
@testable import Reconcile

/// ADR-036 gate: BOTH themes supply EVERY named token, for every screen role.
///
/// Reading a role not in the contract is a compile error (the property does not exist),
/// so this test enumerates every contract role and asserts each resolves in both themes.
final class ThemeTokenContractTests: XCTestCase {

    private func assertEveryColorRoleResolves(_ c: ThemeColors) {
        // Touch every color role in the ADR-036 contract. Reference-equality to a
        // sentinel is meaningless for Color; instead we assert the values are usable by
        // building an array — a missing role would fail to compile, not fail at runtime.
        let roles: [Color] = [
            c.background, c.surface, c.surfaceRaised,
            c.textPrimary, c.textSecondary, c.textMuted,
            c.accent, c.accentCarried, c.divider,
            c.gradientTop, c.gradientMid, c.gradientBottom
        ]
        XCTAssertEqual(roles.count, 12, "ADR-036 defines exactly 12 color roles")
    }

    private func assertEveryTypeRoleResolves(_ t: ThemeTypography) {
        let roles: [Font] = [t.display, t.title, t.body, t.mono, t.eyebrow]
        XCTAssertEqual(roles.count, 5, "ADR-036 defines exactly 5 type roles")
    }

    func testBothThemesSupplyEveryTokenForEveryScreenRole() {
        for theme in Theme.allCases {
            for role in ScreenRole.allCases {
                let tokens = theme.tokens(for: role)
                XCTAssertEqual(tokens.theme, theme)
                XCTAssertEqual(tokens.screenRole, role)
                assertEveryColorRoleResolves(tokens.colors)
                assertEveryTypeRoleResolves(tokens.typography)
            }
        }
    }
}
