import SwiftUI

/// The small evening-feeling ENTRY CARD on Today (ADR-046b).
///
/// Two-step, like setting an MIT (ADR-024): this card just shows state and is a tap target
/// — the actual mood/stress/why entry happens in the full-screen ``FeelingSheetView``. When
/// no feeling is logged for today it shows an EMPTY (open) heart + "Tap to log how today
/// felt"; once logged it shows a FILLED heart + a "Mood M · Stress S" summary. Tapping
/// opens the sheet via the `onOpen` callback. Styling is read by role from `\.theme`.
struct EveningFeelingSection: View {
    @Environment(\.theme) private var tokens
    @ObservedObject var model: TodayViewModel

    /// Open the full-screen feeling sheet.
    let onOpen: () -> Void

    private var logged: DailyFeeling? { model.feeling }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: logged == nil ? "heart" : "heart.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(logged == nil
                                     ? tokens.colors.textMuted
                                     : tokens.colors.likedAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(TodayCopy.feelingEyebrow.uppercased())
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textMuted)
                    if let f = logged {
                        Text("Mood \(f.mood) · Stress \(f.stress)")
                            .font(tokens.typography.body)
                            .foregroundStyle(tokens.colors.textPrimary)
                    } else {
                        Text("Tap to log how today felt")
                            .font(tokens.typography.body)
                            .foregroundStyle(tokens.colors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.colors.textMuted)
            }
            .padding(16)
            .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feeling.card")
        .accessibilityLabel(logged == nil
                            ? "Log how today felt"
                            : "Today's feeling: mood \(logged!.mood), stress \(logged!.stress). Edit.")
    }
}
