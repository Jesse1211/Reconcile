import SwiftUI

/// The screen a view belongs to, declared by the screen and consumed by the theme
/// to vary presentation (ADR-037).
///
/// Each screen SETS its `screenRole`. The **Day Arc** theme CONSUMES it to select
/// per-screen gradient anchors (dawn on Today, midday on Timer, dusk on Summary,
/// ADR-022). The **Ledger** theme IGNORES it — its neutrals are screen-independent.
/// This keeps screens theme-agnostic: a screen only declares its role and the theme
/// decides whether the role matters.
public enum ScreenRole: String, CaseIterable, Sendable {
    case today
    case timer
    case library
    case summary
}

private struct ScreenRoleKey: EnvironmentKey {
    static let defaultValue: ScreenRole = .today
}

public extension EnvironmentValues {
    /// The current screen's role (ADR-037). Set by each screen via `.screenRole(_:)`.
    var screenRole: ScreenRole {
        get { self[ScreenRoleKey.self] }
        set { self[ScreenRoleKey.self] = newValue }
    }
}

public extension View {
    /// Declare this screen's `screenRole` (ADR-037). Day Arc consumes it; Ledger ignores it.
    func screenRole(_ role: ScreenRole) -> some View {
        environment(\.screenRole, role)
    }
}
