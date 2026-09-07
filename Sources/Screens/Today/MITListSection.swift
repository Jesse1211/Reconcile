import SwiftUI

/// Today's MIT list (ADR-004/-005/-008/-024/-033).
///
/// Shows today's open MITs (including rolled-in ones, ADR-005), a gentle first-run
/// invitation when empty (ADR-033), and always ends in the dashed placeholder row that
/// opens the full-screen intention ritual (ADR-024). Each row supports complete (tap
/// the checkbox), edit (tap the text) and soft-delete + undo (ADR-008). Styling is read
/// by role from the `\.theme` tokens (ADR-036).
struct MITListSection: View {
    @Environment(\.theme) private var tokens
    @ObservedObject var model: TodayViewModel

    /// Opens the intention ritual (ADR-024). The container presents it full-screen.
    let onOpenRitual: () -> Void
    /// Opens an editor for an existing MIT on the current day (ADR-004).
    let onEdit: (MIT) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S MOST IMPORTANT")
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)

            if model.mitListIsEmpty {
                Text(IntentionRitualCopy.firstRunInvitation)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                    .accessibilityIdentifier("mit.firstRun")
            }

            ForEach(model.mits, id: \.id) { mit in
                row(mit)
            }

            placeholderRow
        }
    }

    // MARK: A single MIT row (ADR-004/-008)

    private func row(_ mit: MIT) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                model.toggleComplete(mit)
            } label: {
                Image(systemName: mit.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mit.status == .completed ? tokens.colors.accent : tokens.colors.textMuted)
            }
            .accessibilityIdentifier("mit.toggle")

            VStack(alignment: .leading, spacing: 2) {
                Text(mit.text)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textPrimary)
                    .strikethrough(mit.status == .completed)
                if let reason = mit.reason, !reason.isEmpty {
                    Text(reason)
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit(mit) }

            Spacer()

            Button {
                model.softDelete(mit)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(tokens.colors.textMuted)
            }
            .accessibilityIdentifier("mit.delete")
        }
        .padding(.vertical, 6)
    }

    // MARK: The dashed placeholder row → intention ritual (ADR-024)

    private var placeholderRow: some View {
        Button(action: onOpenRitual) {
            HStack {
                Image(systemName: "plus")
                Text(IntentionRitualCopy.placeholderRowTitle(for: tokens.theme))
                Spacer()
            }
            .font(tokens.typography.body)
            .foregroundStyle(tokens.colors.textSecondary)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        tokens.colors.divider,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
        }
        .accessibilityIdentifier("mit.placeholder")
    }
}
