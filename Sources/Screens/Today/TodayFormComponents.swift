import SwiftUI

/// Shared chrome for the full-screen Today entry sheets (intention ritual, feeling,
/// MIT edit). Each sheet has the SAME masthead (guiding eyebrow + wide-format date +
/// hairline divider, ADR-024) and the SAME primary-save button treatment (ledger-red
/// fill, paper text), differing only in their copy. Extracting them keeps the treatment
/// in one place and every sheet reads its styling BY ROLE from the `\.theme` tokens
/// (ADR-036) — no hard-coded color/font.

/// The guiding eyebrow + date masthead shared by the Today entry sheets (ADR-024).
struct SheetMasthead: View {
    @Environment(\.theme) private var tokens

    let eyebrow: String
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
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
    }
}

/// The primary "save" button label shared by the Today entry sheets: a full-width
/// ledger-red fill with paper text (ADR-024). The button's own action, disabled/opacity
/// state, and accessibility identifier stay at each call site.
struct SheetSaveLabel: View {
    @Environment(\.theme) private var tokens

    let title: String

    var body: some View {
        Text(title)
            .font(tokens.typography.title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(tokens.colors.background)
            .background(tokens.colors.accentFill, in: RoundedRectangle(cornerRadius: 12))
    }
}
