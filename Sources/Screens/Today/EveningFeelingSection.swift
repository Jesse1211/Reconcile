import SwiftUI

/// The evening DailyFeeling entry (ADR-019/-020).
///
/// Two `0...5` pickers (mood, stress) plus an optional "why" text field, upserting
/// today's single entry via T11 (``DailyFeelingService``, INV-7). Same-day editable;
/// a rolled entry is read-only (INV-8). Styling is read by role from the `\.theme`
/// tokens (ADR-036).
struct EveningFeelingSection: View {
    @Environment(\.theme) private var tokens
    @ObservedObject var model: TodayViewModel

    @State private var mood: Int = 3
    @State private var stress: Int = 3
    @State private var why: String = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(TodayCopy.feelingEyebrow.uppercased())
                .font(tokens.typography.eyebrow)
                .foregroundStyle(tokens.colors.textMuted)

            scalePicker(label: TodayCopy.moodLabel, value: $mood, id: "feeling.mood")
            scalePicker(label: TodayCopy.stressLabel, value: $stress, id: "feeling.stress")

            TextField(TodayCopy.whyPrompt, text: $why, axis: .vertical)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textPrimary)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(12)
                .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("feeling.why")

            Button {
                model.saveFeeling(mood: mood, stress: stress, why: why)
            } label: {
                Text(TodayCopy.feelingSaveTitle)
                    .font(tokens.typography.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(tokens.colors.background)
                    .background(tokens.colors.accentFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!model.feelingEditable)
            .opacity(model.feelingEditable ? 1 : 0.5)
            .accessibilityIdentifier("feeling.save")
        }
        .padding(20)
        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 16))
        .onAppear(perform: syncFromModel)
    }

    /// Seed the pickers from today's saved entry (INV-7), once, so re-editing shows
    /// the persisted values rather than resetting to the midpoint.
    private func syncFromModel() {
        guard !didLoad else { return }
        didLoad = true
        if let f = model.feeling {
            mood = f.mood
            stress = f.stress
            why = f.whyText ?? ""
        }
    }

    // MARK: A 0-5 scale picker (ADR-019/-020)

    private func scalePicker(label: String, value: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(tokens.typography.body)
                .foregroundStyle(tokens.colors.textSecondary)
            HStack(spacing: 8) {
                ForEach(0...5, id: \.self) { n in
                    Button {
                        value.wrappedValue = n
                    } label: {
                        Text("\(n)")
                            .font(tokens.typography.body)
                            .frame(width: 36, height: 36)
                            .foregroundStyle(
                                value.wrappedValue == n ? tokens.colors.background : tokens.colors.textPrimary
                            )
                            .background(
                                value.wrappedValue == n ? tokens.colors.accentFill : tokens.colors.surfaceRaised,
                                in: Circle()
                            )
                    }
                    .disabled(!model.feelingEditable)
                }
            }
            .accessibilityIdentifier(id)
        }
    }
}
