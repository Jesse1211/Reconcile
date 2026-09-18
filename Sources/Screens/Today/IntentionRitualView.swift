import SwiftUI

/// The full-screen "intention ritual" for setting today's most important thing (ADR-024).
///
/// Entered from the dashed placeholder row on the Today MIT list — NOT a floating FAB.
/// Low-chrome: a guiding eyebrow, the date, a LARGE serif input for the one thing, and
/// an OPTIONAL collapsible "why does it matter today?" reason field that persists to
/// `MIT.reason`. Each theme dresses it via ``IntentionRitualCopy`` (ADR-024) and reads
/// all styling by role from the `\.theme` tokens (ADR-036) — no hard-coded color/font.
///
/// On save it calls back with the entered text + optional reason; the caller creates the
/// MIT (via ``TodayViewModel/saveIntention(text:reason:)``), dismisses, and toasts undo.
struct IntentionRitualView: View {
    @Environment(\.theme) private var tokens
    @Environment(\.dismiss) private var dismiss

    /// The date shown in the masthead (today, from the injected clock).
    let date: Date
    /// Called with the entered one-thing + optional reason when the user saves.
    let onSave: (_ text: String, _ reason: String?) -> Void

    @State private var text: String = ""
    @State private var reason: String = ""

    private var copy: IntentionRitualCopy { IntentionRitualCopy.forTheme(tokens.theme) }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(alignment: .leading, spacing: 24) {
                // No masthead — the "TODAY'S ENTRY" eyebrow + date are redundant here
                // (owner tweak), matching the feeling sheet; open straight to the input.
                // The one thing — large serif input (ADR-024).
                TextField(copy.inputPrompt, text: $text, axis: .vertical)
                    .font(tokens.typography.display)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("intention.text")

                // Optional reason (persists to MIT.reason, ADR-024). Always shown — the
                // same pattern as the feeling sheet's "Why? (optional)", no collapse.
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(copy.reasonPrompt) (optional)")
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textMuted)
                    TextField("\(copy.reasonPrompt) (optional)", text: $reason, axis: .vertical)
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.textPrimary)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("intention.reason.field")
                }

                Spacer()

                // Save shows only a ✓ (owner tweak), matching the feeling sheet — the
                // ledger-red fill is kept, just a checkmark instead of "Record entry".
                Button {
                    let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(text, trimmedReason.isEmpty ? nil : trimmedReason)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(tokens.typography.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(tokens.colors.background)
                        .background(tokens.colors.accentFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .accessibilityLabel("Save")
                .accessibilityIdentifier("intention.save")
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(tokens.colors.textSecondary)
            }
        }
    }
}
