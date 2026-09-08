import SwiftUI

/// The full-screen evening-feeling entry (ADR-019/-020, ADR-046b).
///
/// Entered from the small feeling card on Today — the same two-step pattern as the
/// intention ritual (ADR-024): the card shows filled/empty state, tapping opens this
/// full-screen page to set the values. Low-chrome: a guiding eyebrow + date masthead, two
/// 0–5 SLIDERS (mood, stress) with a live value, an OPTIONAL "why" note, and a save.
///
/// On save it calls back with mood/stress/why; the caller upserts today's `DailyFeeling`
/// (via ``TodayViewModel/saveFeeling(mood:stress:why:)``, INV-7) and dismisses. Same-day
/// editable; a cross-day entry is read-only (INV-8) — the caller passes `editable`.
struct FeelingSheetView: View {
    @Environment(\.theme) private var tokens
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let editable: Bool
    /// Seed values (today's saved entry, or the 3/3 midpoint for a fresh entry).
    let initialMood: Int
    let initialStress: Int
    let initialWhy: String
    /// Called with the chosen mood/stress and optional why when the user saves.
    let onSave: (_ mood: Int, _ stress: Int, _ why: String) -> Void

    @State private var mood: Double
    @State private var stress: Double
    @State private var why: String

    init(
        date: Date,
        editable: Bool,
        initialMood: Int,
        initialStress: Int,
        initialWhy: String,
        onSave: @escaping (_ mood: Int, _ stress: Int, _ why: String) -> Void
    ) {
        self.date = date
        self.editable = editable
        self.initialMood = initialMood
        self.initialStress = initialStress
        self.initialWhy = initialWhy
        self.onSave = onSave
        _mood = State(initialValue: Double(initialMood))
        _stress = State(initialValue: Double(initialStress))
        _why = State(initialValue: initialWhy)
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(alignment: .leading, spacing: 28) {
                // Masthead: eyebrow + date, mirroring the intention ritual (ADR-024).
                VStack(alignment: .leading, spacing: 6) {
                    Text("How today felt".uppercased())
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

                slider(label: "Mood", value: $mood)
                slider(label: "Stress", value: $stress)

                // Optional note.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why? (optional)")
                        .font(tokens.typography.eyebrow)
                        .foregroundStyle(tokens.colors.textMuted)
                    TextField("Why? (optional)", text: $why, axis: .vertical)
                        .font(tokens.typography.body)
                        .foregroundStyle(tokens.colors.textPrimary)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(tokens.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                        .disabled(!editable)
                        .accessibilityIdentifier("feeling.why")
                }

                Spacer()

                Button {
                    onSave(Int(mood.rounded()), Int(stress.rounded()), why)
                    dismiss()
                } label: {
                    Text("Save how today felt")
                        .font(tokens.typography.title)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(tokens.colors.background)
                        .background(tokens.colors.accentFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!editable)
                .opacity(editable ? 1 : 0.5)
                .accessibilityIdentifier("feeling.save")
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

    // MARK: A labelled 0-5 slider with a live value (ADR-019/-020)

    private func slider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(tokens.typography.body)
                    .foregroundStyle(tokens.colors.textSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(tokens.typography.title)
                    .foregroundStyle(tokens.colors.textPrimary)
            }
            Slider(value: value, in: 0...5, step: 1)
                .tint(tokens.colors.accentOnBackground)
                .disabled(!editable)
                .accessibilityIdentifier("feeling.\(label.lowercased())")
        }
    }
}
