import Foundation

/// The per-theme copy for the full-screen intention ritual (ADR-024).
///
/// ADR-024 pins that each theme DRESSES the ritual: Ledger reads as a paper ledger
/// masthead ("Record entry"); Day Arc reads as a dawn invitation ("Begin where the
/// light is" / "Set it"). Keeping the copy in a pure, `Theme`-keyed value type makes
/// the wording testable and keeps the SwiftUI view theme-agnostic — it reads copy by
/// role, exactly as it reads color/type tokens by role (ADR-036/-037).
public struct IntentionRitualCopy: Equatable, Sendable {
    /// The guiding eyebrow above the date (ADR-024).
    public let eyebrow: String
    /// Placeholder for the large serif "one thing" input (ADR-024).
    public let inputPrompt: String
    /// Label for the optional collapsible reason field (ADR-024).
    public let reasonPrompt: String
    /// The save button title, theme-dressed (ADR-024).
    public let saveTitle: String

    public init(eyebrow: String, inputPrompt: String, reasonPrompt: String, saveTitle: String) {
        self.eyebrow = eyebrow
        self.inputPrompt = inputPrompt
        self.reasonPrompt = reasonPrompt
        self.saveTitle = saveTitle
    }

    /// Resolve the ritual copy for a theme (ADR-024). Both themes supply every field.
    public static func forTheme(_ theme: Theme) -> IntentionRitualCopy {
        switch theme {
        case .ledger:
            return IntentionRitualCopy(
                eyebrow: "TODAY'S ENTRY",
                inputPrompt: "Set today's most important…",
                reasonPrompt: "Why does it matter today?",
                saveTitle: "Record entry"
            )
        case .dayArc:
            return IntentionRitualCopy(
                eyebrow: "Begin where the light is",
                inputPrompt: "The one thing…",
                reasonPrompt: "Why does it matter today?",
                saveTitle: "Set it"
            )
        }
    }

    /// The dashed placeholder row's prompt on the Today MIT list (ADR-024/-033).
    public static func placeholderRowTitle(for theme: Theme) -> String {
        switch theme {
        case .ledger: return "Set today's most important…"
        case .dayArc: return "Set today's most important…"
        }
    }

    /// The gentle first-run invitation shown when today's MIT list is empty (ADR-033).
    public static let firstRunInvitation =
        "Nothing set yet — name the one thing that would make today count."
}
