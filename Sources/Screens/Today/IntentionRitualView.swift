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
    @State private var showReason: Bool = false

    private var copy: IntentionRitualCopy { IntentionRitualCopy.forTheme(tokens.theme) }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(alignment: .leading, spacing: 24) {
                // Masthead: guiding eyebrow + date (ADR-024).
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.eyebrow.uppercased())
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textMuted)
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(tokens.typography.title)
                        .foregroundStyle(tokens.colors.textSecondary)
                    Rectangle()
                        .fill(tokens.colors.divider)
                        .frame(height: 1)
                        .padding(.top, 4)
                }

                // The one thing — large serif input (ADR-024).
                TextField(copy.inputPrompt, text: $text, axis: .vertical)
                    .font(tokens.typography.display)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("intention.text")

                // Optional collapsible reason (persists to MIT.reason, ADR-024).
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation { showReason.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showReason ? "chevron.down" : "chevron.right")
                            Text(copy.reasonPrompt)
                        }
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.textSecondary)
                    }
                    .accessibilityIdentifier("intention.reason.toggle")

                    if showReason {
                        TextField(copy.reasonPrompt, text: $reason, axis: .vertical)
                            .font(tokens.typography.body)
                            .foregroundStyle(tokens.colors.textPrimary)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("intention.reason.field")
                    }
                }

                Spacer()

                // Theme-dressed save (ADR-024).
                Button {
                    let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(text, trimmedReason.isEmpty ? nil : trimmedReason)
                    dismiss()
                } label: {
                    Text(copy.saveTitle)
                        .font(tokens.typography.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(tokens.colors.background)
                        .background(tokens.colors.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
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
