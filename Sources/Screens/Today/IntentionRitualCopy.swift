import Foundation

/// The per-theme copy for the full-screen intention ritual (ADR-024).
///
/// ADR-024 pins that the theme DRESSES the ritual: Ledger reads as a paper ledger
/// masthead ("Record entry"). (Day Arc, which read as a dawn invitation, has been
/// removed — Ledger is the only theme.) Keeping the copy in a pure, `Theme`-keyed value
/// type makes the wording testable and keeps the SwiftUI view theme-agnostic — it reads
/// copy by role, exactly as it reads color/type tokens by role (ADR-036/-037).
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

    /// Resolve the ritual copy for a theme (ADR-024). The (only) theme supplies every field.
    public static func forTheme(_ theme: Theme) -> IntentionRitualCopy {
        switch theme {
        case .ledger:
            return IntentionRitualCopy(
                eyebrow: "TODAY'S ENTRY",
                inputPrompt: "Set today's most important…",
                reasonPrompt: "Why does it matter today?",
                saveTitle: "Record entry"
            )
        }
    }

    /// The dashed placeholder row's prompt on the Today MIT list (ADR-024/-033).
    public static func placeholderRowTitle(for theme: Theme) -> String {
        switch theme {
        case .ledger: return "Set today's most important…"
        }
    }
}
